import '../../../core/network/api_client.dart';
import '../domain/menu_models.dart';

class MenuRepository {
  const MenuRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<MenuResponse> getMenu() async {
    final data = await _apiClient.getMethod('bcn_mobile_menu');
    return MenuResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
