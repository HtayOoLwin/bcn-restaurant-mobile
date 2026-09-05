import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../printing/domain/known_print_job_controller.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';

final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(sessionStorage: ref.watch(sessionStorageProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    if (!await _repository.hasSession()) {
      return const AuthState.unauthenticated();
    }

    try {
      final bootstrap = await _repository.getBootstrap();
      return AuthState.authenticated(bootstrap);
    } catch (_) {
      await _repository.logout();
      return const AuthState.unauthenticated();
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    ref.read(lastAcceptedPrintJobProvider.notifier).clear();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final bootstrap = await _repository.login(
        username: username,
        password: password,
      );
      return AuthState.authenticated(bootstrap);
    });
  }

  Future<void> logout() async {
    await _repository.logout();
    ref.read(lastAcceptedPrintJobProvider.notifier).clear();
    state = const AsyncData(AuthState.unauthenticated());
  }
}
