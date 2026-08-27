import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../kitchen/presentation/kitchen_notification_badge.dart';
import '../data/mobile_notifications_repository.dart';
import '../domain/mobile_notification.dart';

final mobileNotificationsRepositoryProvider = Provider<MobileNotificationsRepository>(
  (ref) => MobileNotificationsRepository(ref.watch(apiClientProvider)),
);

final mobileNotificationsProvider = FutureProvider<List<MobileNotification>>((ref) async {
  final auth = ref.watch(authControllerProvider).asData?.value;
  if (auth?.isAuthenticated != true) {
    return const <MobileNotification>[];
  }
  return ref.watch(mobileNotificationsRepositoryProvider).getNotifications();
});

class MobileNotificationWatcher extends ConsumerStatefulWidget {
  const MobileNotificationWatcher({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<MobileNotificationWatcher> createState() => _MobileNotificationWatcherState();
}

class _MobileNotificationWatcherState extends ConsumerState<MobileNotificationWatcher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(mobileNotificationsProvider);
        ref.invalidate(kitchenNewOrderCountProvider);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
