import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenPath = 'lib/features/auth/presentation/login_screen.dart';

  late String source;

  setUpAll(() {
    source = File(screenPath).readAsStringSync();
  });

  test('login screen uses Doh Myot Daw restaurant branding', () {
    expect(source, contains("import '../../../core/branding/doh_myot_daw_logo.dart';"));
    expect(source, contains('DohMyotDawLogo('));
    expect(source, contains("'BCN Restaurant'"));
    expect(source, contains("'Restaurant Management System'"));
    expect(source, contains("'Powered by BCN'"));
  });

  test('page, card, and input fields use distinct brand surfaces', () {
    expect(source, contains('Color(0xFFEEF4FA)'));
    expect(source, contains('Color(0xFFFFFFFF)'));
    expect(source, contains('Color(0xFFEAF1F8)'));
    expect(source, contains('Color(0xFF1E5E96)'));
    expect(source, contains('filled: true'));
    expect(source, contains('fillColor: _inputFillColor'));
    expect(source, contains('BorderRadius.circular(24)'));
  });

  test('login form uses clear field icons and password visibility control', () {
    expect(source, contains('Icons.person_outline_rounded'));
    expect(source, contains('Icons.lock_outline_rounded'));
    expect(source, contains('Icons.visibility_rounded'));
    expect(source, contains('Icons.visibility_off_rounded'));
  });

  test('login action keeps existing authentication behavior', () {
    expect(source, contains('authControllerProvider.notifier'));
    expect(source, contains('username: _usernameController.text.trim()'));
    expect(source, contains('password: _passwordController.text'));
    expect(source, contains("'User is required'"));
    expect(source, contains("'Password is required'"));
  });
}
