import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OurCity launcher uses an adaptive icon and inset foreground', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final icon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(icon, contains('@color/ic_launcher_background'));
    expect(icon, contains('@drawable/ic_launcher_foreground'));
    expect(icon, contains('android:inset="20%"'));
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
