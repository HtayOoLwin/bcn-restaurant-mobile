import '../../../core/network/api_client.dart';
import '../../bootstrap/domain/bootstrap_model.dart';

class AuthRepository {
  const AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<BootstrapModel> login({
    required String username,
    required String password,
  }) async {
    await _apiClient.login(username: username, password: password);
    return getBootstrap();
  }

  Future<BootstrapModel> getBootstrap() async {
    final data = await _apiClient.getMethod('bcn_restaurant.api.bootstrap.get_bootstrap');
    return BootstrapModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<bool> hasSession() => _apiClient.hasSession();

  Future<void> logout() => _apiClient.logout();
}
