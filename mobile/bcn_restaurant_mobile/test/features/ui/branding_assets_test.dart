import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BCN launcher and loading branding are wired into the app', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final splash = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();

    expect(pubspec, contains('assets/images/bcn_loading_logo.png'));
    expect(router, contains("Image.asset('assets/images/bcn_loading_logo.png'"));
    expect(router, contains("'BCN Restaurant'"));
    expect(splash, contains('@drawable/launch_image'));
  });
}
