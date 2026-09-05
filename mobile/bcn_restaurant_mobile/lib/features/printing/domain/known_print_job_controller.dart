import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'windows_print_status.dart';

final lastAcceptedPrintJobProvider =
    NotifierProvider<LastAcceptedPrintJobController, KnownPrintJobContext?>(
      LastAcceptedPrintJobController.new,
    );

class LastAcceptedPrintJobController extends Notifier<KnownPrintJobContext?> {
  @override
  KnownPrintJobContext? build() => null;

  void retain(KnownPrintJobContext context) {
    state = context;
  }

  void clear() {
    state = null;
  }
}
