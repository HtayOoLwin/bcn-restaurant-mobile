import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/kitchen_repository.dart';

final kitchenNewOrderCountProvider = FutureProvider<int>((ref) async {
  final auth = ref.watch(authControllerProvider).asData?.value;
  if (auth?.isAuthenticated != true || auth?.bootstrap?.permissions.kitchen != true) {
    return 0;
  }

  final repository = KitchenRepository(ref.watch(apiClientProvider));
  final response = await repository.getOrders(status: 'New');
  return response.orders.length;
});
