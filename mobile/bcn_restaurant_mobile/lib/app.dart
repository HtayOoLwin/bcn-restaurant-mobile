import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/layout/adaptive_orientation.dart';
import 'core/router/app_router.dart';

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class BcnRestaurantApp extends ConsumerWidget {
  const BcnRestaurantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BCN Restaurant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      routerConfig: router,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      builder: (context, child) =>
          AdaptiveOrientation(child: child ?? const SizedBox.shrink()),
    );
  }
}
