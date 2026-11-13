import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OurCity launcher uses the configured adaptive icon resources', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final icon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final colors =
        File('android/app/src/main/res/values/colors.xml').readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(icon, contains('<adaptive-icon'));
    expect(icon, contains('@color/bcn_launcher_blue'));
    expect(colors, contains('name="bcn_launcher_blue"'));
    expect(icon, contains('@drawable/ic_launcher_foreground'));

    // This foreground drawable uses a 20dp inset rather than an
    // android:inset attribute on the adaptive-icon itself.
    final foreground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    );
    if (foreground.existsSync()) {
      final xml = foreground.readAsStringSync();
      expect(xml, contains('<layer-list'));
      expect(xml, contains('android:left="20dp"'));
      expect(xml, contains('android:top="20dp"'));
    }
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
