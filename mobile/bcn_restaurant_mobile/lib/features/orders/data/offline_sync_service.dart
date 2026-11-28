import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/session_storage.dart';
import '../../auth/presentation/auth_controller.dart';

final offlineSyncProvider =
    NotifierProvider<OfflineSyncController, OfflineSyncState>(
  OfflineSyncController.new,
);

class OfflineSyncState {
  const OfflineSyncState({
    this.running = false,
    this.completed = 0,
    this.errors = const {},
  });

  final bool running;
  final int completed;
  final Map<String, String> errors;
}

class OfflineSyncController extends Notifier<OfflineSyncState> {
  @override
  OfflineSyncState build() => const OfflineSyncState();

  Future<void> sync() async {
    if (state.running) return;
    state = const OfflineSyncState(running: true);
    final api = ref.read(apiClientProvider);
    final storage = ref.read(sessionStorageProvider);
    final errors = <String, String>{};
    var completed = 0;
    try {
      final sid = await storage.readSid();
      final bootstrap = ref.read(authControllerProvider).asData?.value.bootstrap;
      if (sid == null || bootstrap == null || !bootstrap.permissions.waiter) {
        throw StateError('An authenticated waiter session is required.');
      }
      final user = await api.getMethod('frappe.auth.get_logged_user');
      if (user != bootstrap.user) {
        throw StateError('ERPNext login has changed. Sync stopped.');
      }
      final records = await storage.pendingOrders();
      if (records.isEmpty) return;
      final ping = _message(await api.postMethod('bcn_sync_offline_order',
        data: {'action': 'ping'}));
      if (ping['ready'] != true || ping['backend_version'] != 1) {
        throw StateError('Offline Sync API is not ready.');
      }

      final pending = <_PendingRecord>[];
      for (final entry in records.entries) {
        try {
          pending.add(_PendingRecord.parse(entry));
        } catch (error) {
          errors[entry.key] = 'Invalid local record: $error';
        }
      }
      // Do not reorder or submit valid records around a corrupt record.
      if (errors.isNotEmpty) return;
      pending.sort((a, b) {
        final order = a.created.compareTo(b.created);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });

      final blockedCustomers = <String>{};
      for (final record in pending) {
        if (blockedCustomers.contains(record.customer)) {
          errors[record.id] = 'Earlier order for this table requires review.';
          continue;
        }
        try {
          await _checkSession(storage, sid);
          // A previous attempt may have committed before its response was lost.
          final status = _message(await api.postMethod('bcn_sync_offline_order',
            data: {'action': 'status', 'client_order_id': record.id}));
          if (status['found'] != true && status['found'] != false) {
            throw StateError('Invalid status response.');
          }

          // Bind a new-table follow-up to its recorded predecessor receipt.
          // Persist the bound payload before submission so retries are identical.
          var rawToDelete = record.raw;
          final predecessor = (jsonDecode(record.raw) as Map)['predecessor']?.toString() ?? '';
          if (status['found'] == false && predecessor.isNotEmpty &&
              (record.payload['session']?.toString() ?? '').isEmpty) {
            final prior = _message(await api.postMethod('bcn_sync_offline_order',
              data: {'action': 'status', 'client_order_id': predecessor}));
            final target = prior['sales_order']?.toString() ?? '';
            if (prior['found'] != true || target.isEmpty) {
              throw StateError('Earlier offline order has not been confirmed.');
            }
            await _checkSession(storage, sid);
            if ((await storage.pendingOrders())[record.id] != record.raw) {
              throw StateError('Local order changed during sync.');
            }
            record.payload['session'] = target;
            final saved = Map<String, dynamic>.from(jsonDecode(record.raw) as Map);
            saved['payload'] = record.payload;
            rawToDelete = jsonEncode(saved);
            await storage.writeOffline('order:${record.id}', rawToDelete);
          }
          // Always submit the ORIGINAL payload. The server compares the payload
          // even for duplicates; status alone does not prove payload equality.
          await _checkSession(storage, sid);
          final result = _message(await api.postMethod('bcn_sync_offline_order',
            data: {...record.payload, 'action': 'submit'}));
          final salesOrder = result['sales_order']?.toString() ?? '';
          if (result['success'] != true || salesOrder.isEmpty) {
            throw StateError('Server did not confirm the order.');
          }
          if (status['found'] == true && status['sales_order'] != salesOrder) {
            throw StateError('Sync receipt Sales Order mismatch.');
          }
          await _checkSession(storage, sid);
          // Delete only the exact acknowledged local record.
          final current = await storage.pendingOrders();
          if (current[record.id] != rawToDelete) {
            throw StateError('Local record changed during sync. Review it.');
          }
          await storage.deletePendingOrder(record.id, expectedSid: sid);
          completed++;
        } catch (error) {
          errors[record.id] = error.toString();
          blockedCustomers.add(record.customer);
        }
      }
      if (completed > 0) {
        // Refresh the persisted server snapshot before showing merged totals.
        try {
          await api.getMethod('bcn_waiter_order_progress');
        } catch (_) {
          // Receipts are already committed; UI refresh can be retried.
        }
      }
    } catch (error) {
      errors['_sync'] = error.toString();
    } finally {
      state = OfflineSyncState(completed: completed, errors: Map.unmodifiable(errors));
    }
  }

  Future<void> _checkSession(SessionStorage storage, String sid) async {
    if (await storage.readSid() != sid) {
      throw StateError('Login session changed. Sync stopped.');
    }
  }

  Map<String, dynamic> _message(dynamic data) {
    if (data is! Map) throw StateError('Invalid offline sync response.');
    var result = Map<String, dynamic>.from(data);
    for (var i = 0; i < 4; i++) {
      final nested = result['message'];
      if (nested is! Map) break;
      result = Map<String, dynamic>.from(nested);
    }
    return result;
  }
}

class _PendingRecord {
  const _PendingRecord(this.id, this.raw, this.payload, this.created, this.customer);
  final String id;
  final String raw;
  final Map<String, dynamic> payload;
  final DateTime created;
  final String customer;

  factory _PendingRecord.parse(MapEntry<String, String> entry) {
    final record = jsonDecode(entry.value) as Map;
    final payload = Map<String, dynamic>.from(record['payload'] as Map);
    final customer = payload['customer']?.toString() ?? '';
    final created = DateTime.tryParse(record['created_at']?.toString() ?? '');
    if (payload['client_order_id'] != entry.key || customer.isEmpty ||
        created == null || payload['items'] is! String) {
      throw const FormatException('Missing request ID, table, date or items.');
    }
    return _PendingRecord(entry.key, entry.value, payload, created, customer);
  }
}
