import '../../../core/network/api_client.dart';
import '../domain/table_models.dart';

class TablesRepository {
  const TablesRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<TablesResponse> getTables(String customerGroup) async {
    final data = await _apiClient.getMethod(
      'bcn_mobile_tables',
      queryParameters: {'customer_group': customerGroup},
    );
    return TablesResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
