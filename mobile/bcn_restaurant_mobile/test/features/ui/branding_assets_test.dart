import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OurCity launcher uses an adaptive icon and inset foreground', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final icon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final roundIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ).readAsStringSync();
    final foreground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));

    for (final adaptiveIcon in [icon, roundIcon]) {
      expect(adaptiveIcon, contains('<adaptive-icon'));
      expect(adaptiveIcon, contains('@color/bcn_launcher_blue'));
      expect(adaptiveIcon, contains('@drawable/ic_launcher_foreground'));
    }
    expect(colors, contains('name="bcn_launcher_blue"'));
    for (final side in ['left', 'right', 'top', 'bottom']) {
      expect(foreground, contains('android:$side="20dp"'));
    }
    expect(foreground, contains('@drawable/bcn_splash_mark'));
  });

  test('OurCity loading and login screens use OurCity assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    final login = File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsStringSync();

    expect(pubspec, contains('assets/images/OurCityLogo.png'));
    expect(router, contains("AssetImage('assets/images/OurCityLogo.png')"));
    expect(login, contains("'assets/images/OurCityLogo.png'"));
    expect(router, contains('fit: BoxFit.contain'));
  });
}
