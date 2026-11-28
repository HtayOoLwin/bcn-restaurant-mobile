import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid_v4.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/cashier_models.dart';

final pendingPaymentCountProvider = FutureProvider<int>((ref) async =>
    (await ref.watch(apiClientProvider).pendingPayments()).length);

final offlinePaymentProvider =
    NotifierProvider<OfflinePaymentController, OfflinePaymentState>(
  OfflinePaymentController.new,
);

class OfflinePaymentState {
  const OfflinePaymentState({this.running = false, this.error, this.completed = 0});
  final bool running;
  final String? error;
  final int completed;
}

class OfflinePaymentController extends Notifier<OfflinePaymentState> {
  @override
  OfflinePaymentState build() => const OfflinePaymentState();

  Future<void> recordCash(CashierBill bill, CashierPaymentMode mode) => _record(bill, mode: mode);

  Future<void> recordCredit(CashierBill bill, String customer) => _record(bill, creditCustomer: customer);

  Future<void> recordSettlement(CashierBill bill, List<CashierPaymentTender> tenders,
      List<CashierPaymentMode> modes, {String? creditCustomer, double creditAmount = 0}) async {
    if (!creditAmount.isFinite || creditAmount < 0 || creditAmount > bill.grandTotal ||
        (creditAmount > 0) != (creditCustomer?.trim().isNotEmpty == true)) {
      throw StateError('Invalid credit amount or customer.');
    }
    final seen = <String>{};
    var cash = 0.0;
    var nonCash = 0.0;
    for (final tender in tenders) {
      final matches = modes.where((mode) => mode.name == tender.modeOfPayment);
      if (matches.length != 1 || tender.modeOfPayment.trim().toLowerCase() == 'credit' ||
          !seen.add(tender.modeOfPayment) || !tender.amount.isFinite || tender.amount <= 0) {
        throw StateError('Invalid or duplicate payment method.');
      }
      if (matches.single.isCash) {
        cash += tender.amount;
      } else {
        nonCash += tender.amount;
      }
    }
    final due = bill.grandTotal - creditAmount;
    if (nonCash > due + 0.01 || cash + nonCash < due - 0.01 ||
        (due <= 0.01 && tenders.isNotEmpty)) {
      throw StateError('Payment amounts do not match the bill.');
    }
    await _record(bill, creditCustomer: creditCustomer, tenders: tenders,
      creditAmount: creditAmount);
  }

  Future<void> _record(CashierBill bill, {CashierPaymentMode? mode, String? creditCustomer,
      List<CashierPaymentTender>? tenders, double creditAmount = 0}) async {
    if (state.running) throw StateError('Payment sync in progress.');
    final auth = ref.read(authControllerProvider).asData?.value.bootstrap;
    final storage = ref.read(sessionStorageProvider);
    final api = ref.read(apiClientProvider);
    final sid = await storage.readSid();
    if (sid == null || auth?.permissions.cashier != true ||
        !bill.localPreview || !bill.offlineCashEligible || bill.cashRecorded ||
        bill.offlineModified.isEmpty || (tenders == null && (creditCustomer == null ? mode?.isCash != true : creditCustomer.trim().isEmpty)) || bill.grandTotal <= 0 ||
        !bill.grandTotal.isFinite || bill.currency != 'MMK') {
      throw StateError('This bill is not eligible for offline cash payment.');
    }
    if (await api.canReachServer()) {
      throw StateError('ERPNext is online. Refresh the bill and use online payment.');
    }
    final id = 'offline-pay:${generateUuidV4()}';
    await storage.savePayment(id, {
      'request_id': id,
      'sales_order': bill.salesOrder,
      'customer': bill.customer,
      'expected_modified': bill.offlineModified,
      'amount': bill.grandTotal,
      'mode_of_payment': mode?.name ?? '',
      'credit_customer': ?creditCustomer,
      if (tenders != null) 'payments': jsonEncode(tenders.map((tender) => {'mode_of_payment': tender.modeOfPayment, 'amount': tender.amount}).toList()),
      if (tenders != null) 'credit_amount': creditAmount,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    }, expectedSid: sid);
    ref.invalidate(pendingPaymentCountProvider);
  }

  Future<void> sync() async {
    if (state.running) return;
    state = const OfflinePaymentState(running: true);
    var completed = 0;
    String? failure;
    try {
      final storage = ref.read(sessionStorageProvider);
      final api = ref.read(apiClientProvider);
      final auth = ref.read(authControllerProvider).asData?.value.bootstrap;
      final sid = await storage.readSid();
      if (sid == null || auth == null || !auth.permissions.cashier ||
          await api.getMethod('frappe.auth.get_logged_user') != auth.user) {
        throw StateError('An authenticated cashier session is required.');
      }
      final records = await storage.pendingPayments();
      if (records.isEmpty) return;
      final ping = await api.postMethod('bcn_sync_offline_payment', data: {'action': 'ping'});
      if (ping is! Map || ping['ready'] != true || ping['backend_version'] != 3) {
        throw StateError('Offline payment API is not ready.');
      }
      for (final entry in records.entries) {
        final data = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
        if (data['request_id'] != entry.key) throw StateError('Invalid payment request.');
        if (await storage.readSid() != sid) throw StateError('Login changed.');
        final result = await api.postMethod('bcn_sync_offline_payment',
          data: {...data, 'action': 'submit'});
        if (result is! Map || result['success'] != true ||
            result['sales_order'] != data['sales_order'] ||
            (result['sales_invoice']?.toString() ?? '').isEmpty) {
          throw StateError('Server did not confirm offline settlement.');
        }
        await storage.deletePendingPayment(entry.key, entry.value, expectedSid: sid);
        completed++;
      }
      if (completed > 0) {
        try {
          await api.getMethod('bcn_cashier_billing');
        } catch (_) {
          // A committed payment must not be replayed because refresh failed.
        }
      }
    } catch (error) {
      failure = error.toString();
    } finally {
      state = OfflinePaymentState(completed: completed, error: failure);
      ref.invalidate(pendingPaymentCountProvider);
    }
  }
}
