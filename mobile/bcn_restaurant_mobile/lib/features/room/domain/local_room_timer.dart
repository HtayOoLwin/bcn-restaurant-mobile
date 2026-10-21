/// Local-only room timer prototype shared by the waiter menu and table screen.
/// No network requests or disk persistence. Clears when the app process exits.
class LocalRoomTimer {
  LocalRoomTimer._();
  static final Map<String, RoomTimerDraft> _rooms = {};

  static RoomTimerDraft? get(String customer) => _rooms[customer];

  static RoomTimerDraft start(String customer) {
    return _rooms.putIfAbsent(customer, () => RoomTimerDraft(DateTime.now()));
  }

  static void markBilling(String customer, {required double foodTotal}) {
    final draft = _rooms[customer];
    if (draft == null || draft.stoppedAt != null) return;
    draft.billing = true;
    draft.foodTotal = foodTotal;
  }

  static RoomTimerDraft? stop(String customer) {
    final draft = _rooms[customer];
    if (draft == null || !draft.billing) return null;
    draft.stoppedAt ??= DateTime.now();
    return draft;
  }

  static void clear(String customer) => _rooms.remove(customer);
}

class RoomTimerDraft {
  RoomTimerDraft(this.startedAt);

  final DateTime startedAt;
  DateTime? stoppedAt;
  bool billing = false;
  double foodTotal = 0;

  Duration get elapsed => (stoppedAt ?? DateTime.now()).difference(startedAt);
  int get billableHours => (elapsed.inMilliseconds / 3600000).ceil().clamp(1, 99999);
  double get roomCharges => billableHours * 10000.0;
  double get foodTax => foodTotal * 0.05;
  double get foodService => foodTotal * 0.10;
  double get total => foodTotal + foodTax + foodService + roomCharges;
}
