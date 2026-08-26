import '../../bootstrap/domain/bootstrap_model.dart';

class AuthState {
  const AuthState._({required this.isAuthenticated, this.bootstrap});

  const AuthState.unauthenticated()
      : this._(isAuthenticated: false, bootstrap: null);

  const AuthState.authenticated(BootstrapModel bootstrap)
      : this._(isAuthenticated: true, bootstrap: bootstrap);

  final bool isAuthenticated;
  final BootstrapModel? bootstrap;
}
