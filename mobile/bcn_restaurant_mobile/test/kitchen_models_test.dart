import 'package:bcn_restaurant_mobile/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kitchen item maps only the valid next action', () {
    expect(KitchenOrderItem.fromJson({'row_name': '1', 'preparation_status': 'New'}).nextAction, 'Accept');
    expect(KitchenOrderItem.fromJson({'row_name': '2', 'preparation_status': 'Accepted'}).nextAction, 'Start Preparation');
    expect(KitchenOrderItem.fromJson({'row_name': '3', 'preparation_status': 'Preparing'}).nextAction, 'Mark Ready');
    expect(KitchenOrderItem.fromJson({'row_name': '4', 'preparation_status': 'Ready'}).nextAction, isNull);
  });
}
