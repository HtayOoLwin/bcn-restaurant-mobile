import '../../../core/network/api_client.dart';
import '../domain/mobile_notification.dart';

class MobileNotificationsRepository {
  const MobileNotificationsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<MobileNotification>> getNotifications() async {
    final data = await _apiClient.getMethod('bcn_mobile_notifications');
    final map = Map<String, dynamic>.from(data as Map);
    return (map['notifications'] as List? ?? const [])
        .map((row) => MobileNotification.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> markAllRead() async {
    await _apiClient.postMethod(
      'bcn_mobile_notifications',
      data: const {'action': 'mark_all_read'},
    );
  }
}
