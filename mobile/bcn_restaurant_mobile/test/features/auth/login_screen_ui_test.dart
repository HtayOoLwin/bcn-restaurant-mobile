import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenPath = 'lib/features/auth/presentation/login_screen.dart';

  late String source;

  setUpAll(() {
    source = File(screenPath).readAsStringSync();
  });

  test('login screen uses BCN branding and restaurant subtitle', () {
    expect(
      source,
      contains("Image.asset('assets/images/bcn_brand_mark.png'"),
    );
    expect(source, contains("'BCN Restaurant'"));
    expect(source, contains("'Restaurant Management System'"));
    expect(source, contains("'Powered by BCN'"));
  });

  test('login form uses branded card and input icons', () {
    expect(source, contains('Color(0xFFF4F7FB)'));
    expect(source, contains('BorderRadius.circular(24)'));
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
