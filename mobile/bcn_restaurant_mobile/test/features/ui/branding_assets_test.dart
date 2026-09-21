import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BCN launcher uses adaptive icon resources with a scaled foreground', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final foreground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(manifest, contains('android:label="BCN Restaurant"'));
    expect(adaptiveIcon, contains('@color/bcn_launcher_blue'));
    expect(adaptiveIcon, contains('@drawable/ic_launcher_foreground'));
    expect(foreground, contains('@drawable/bcn_splash_mark'));
    expect(foreground, contains('android:gravity="fill"'));
  });

  test('BCN loading screen uses the transparent brand mark on blue', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final splash = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();

    expect(pubspec, contains('assets/images/bcn_brand_mark.png'));
    expect(router, contains("Image.asset('assets/images/bcn_brand_mark.png'"));
    expect(router, contains('backgroundColor: const Color(0xFF1E5E96)'));
    expect(router, contains('fit: BoxFit.contain'));
    expect(router, isNot(contains('bcn_loading_logo.jpg')));
    expect(splash, contains('@color/bcn_launcher_blue'));
    expect(splash, contains('@drawable/bcn_splash_mark'));
  });
}
