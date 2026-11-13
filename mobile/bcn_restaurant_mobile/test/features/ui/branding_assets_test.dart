import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OurCity launcher uses valid adaptive icon resources', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final icon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(icon, contains('<adaptive-icon'));
    expect(icon, contains('@drawable/ic_launcher_foreground'));

    // Supports either the app's blue launcher resource or locally regenerated
    // Flutter launcher icon resources. Both must reference a declared color.
    final usesBlue = icon.contains('@color/bcn_launcher_blue');
    final usesGenerated = icon.contains('@color/ic_launcher_background');
    expect(
      usesBlue || usesGenerated,
      isTrue,
      reason: 'Adaptive icon must reference a supported background color.',
    );

    final colors = File('android/app/src/main/res/values/colors.xml');
    if (usesBlue) {
      expect(colors.existsSync(), isTrue);
      expect(colors.readAsStringSync(), contains('name="bcn_launcher_blue"'));
    } else {
      final colorResources = [
        'android/app/src/main/res/values/colors.xml',
        'android/app/src/main/res/values/ic_launcher_background.xml',
      ].where((path) => File(path).existsSync()).map(
        (path) => File(path).readAsStringSync(),
      ).join('\n');
      expect(
        colorResources,
        contains('name="ic_launcher_background"'),
        reason: 'The generated background color resource must be defined.',
      );
    }

    if (icon.contains('<inset')) {
      expect(icon, contains('android:inset="20%"'));
    } else {
      final foreground = File(
        'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      );
      expect(foreground.existsSync(), isTrue);
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
