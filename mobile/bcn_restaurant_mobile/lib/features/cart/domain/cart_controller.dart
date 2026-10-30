import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid_v4.dart';
import '../../menu/domain/menu_models.dart';

class CartLine {
  const CartLine({
    required this.item,
    required this.qty,
    this.kitchenNote = '',
    this.foc = false,
    this.parcel = false,
  });

  final MenuItemModel item;
  final double qty;
  final String kitchenNote;
  final bool foc;
  final bool parcel;

  double get amount => (foc ? 0 : item.rate) * qty;

  CartLine copyWith({double? qty, String? kitchenNote}) {
    return CartLine(
      item: item,
      qty: qty ?? this.qty,
      kitchenNote: kitchenNote ?? this.kitchenNote,
      foc: foc,
      parcel: parcel,
    );
  }
}

class CartState {
  const CartState({
    required this.lines,
    this.customer,
    this.session,
    this.remarks = '',
    this.clientOrderId,
    this.roomChargeItemCode,
  });

  const CartState.empty() : this(lines: const []);

  final List<CartLine> lines;
  final String? customer;
  final String? session;
  final String remarks;
  final String? clientOrderId;
  final String? roomChargeItemCode;

  double get totalQty => lines.fold(0, (sum, line) => sum + line.qty);
  double get grandTotal => lines.fold(0, (sum, line) => sum + line.amount);

  CartState copyWith({
    List<CartLine>? lines,
    String? customer,
    String? session,
    bool clearSession = false,
    String? remarks,
    String? clientOrderId,
    bool clearClientOrderId = false,
    String? roomChargeItemCode,
    bool clearRoomCharge = false,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      customer: customer ?? this.customer,
      session: clearSession ? null : (session ?? this.session),
      remarks: remarks ?? this.remarks,
      clientOrderId: clearClientOrderId
          ? null
          : (clientOrderId ?? this.clientOrderId),
      roomChargeItemCode: clearRoomCharge ? null : (roomChargeItemCode ?? this.roomChargeItemCode),
    );
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState.empty();

  void setOrderContext({required String customer, String? session}) {
    if (state.customer != null &&
        state.customer != customer &&
        state.lines.isNotEmpty) {
      state = CartState(
        lines: const [],
        customer: customer,
        session: session,
        clientOrderId: generateUuidV4(),
      );
      return;
    }
    state = CartState(
      lines: state.lines,
      customer: customer,
      session: session,
      remarks: state.remarks,
      roomChargeItemCode: state.roomChargeItemCode,
      clientOrderId: state.clientOrderId ?? generateUuidV4(),
    );
  }

  void add(MenuItemModel item, {bool foc = false, bool parcel = false}) {
    final lines = [...state.lines];
    final index = lines.indexWhere(
      (line) => line.item.itemCode == item.itemCode && line.item.uom == item.uom && line.foc == foc && line.parcel == parcel,
    );
    if (index == -1) {
      lines.add(CartLine(item: item, qty: 1, foc: foc, parcel: parcel));
    } else {
      lines[index] = lines[index].copyWith(qty: lines[index].qty + 1);
    }
    state = state.copyWith(lines: lines);
  }

  void selectRoomCharge(MenuItemModel item) {
    final lines = state.lines.where((line) => line.item.itemCode != state.roomChargeItemCode && line.item.itemCode != item.itemCode).toList();
    lines.add(CartLine(item: item, qty: 1));
    state = state.copyWith(lines: lines, roomChargeItemCode: item.itemCode);
  }

  void decrement(String itemCode, {String? uom, bool foc = false, bool parcel = false}) {
    if (itemCode == state.roomChargeItemCode) return;
    final lines = [...state.lines];
    final index = lines.indexWhere((line) => line.item.itemCode == itemCode && (uom == null || line.item.uom == uom) && line.foc == foc && line.parcel == parcel);
    if (index == -1) return;
    final nextQty = lines[index].qty - 1;
    if (nextQty <= 0) {
      lines.removeAt(index);
    } else {
      lines[index] = lines[index].copyWith(qty: nextQty);
    }
    state = state.copyWith(lines: lines);
  }

  void remove(String itemCode, {String? uom}) {
    state = state.copyWith(
      clearRoomCharge: itemCode == state.roomChargeItemCode,
      lines: state.lines
          .where((line) => line.item.itemCode != itemCode || (uom != null && line.item.uom != uom))
          .toList(),
    );
  }

  void setKitchenNote(String itemCode, String note, {String? uom, bool foc = false, bool parcel = false}) {
    state = state.copyWith(
      lines: state.lines
          .map(
            (line) => line.item.itemCode == itemCode && (uom == null || line.item.uom == uom) && line.foc == foc && line.parcel == parcel
                ? line.copyWith(kitchenNote: note.trim())
                : line,
          )
          .toList(),
    );
  }

  void setRemarks(String value) {
    state = state.copyWith(remarks: value.trim());
  }

  void clear() {
    state = const CartState.empty();
  }
}
