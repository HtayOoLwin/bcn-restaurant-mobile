import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter branding uses a static real logo asset without blocking startup', () {
    final logoSource = File(
      'lib/core/branding/doh_myot_daw_logo.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final loginSource = File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsStringSync();
    final routerSource = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      logoSource,
      contains("Image.asset('assets/images/doh_myot_daw_logo.png'"),
    );
    expect(logoSource, contains('FilterQuality.high'));
    expect(logoSource, isNot(contains('rootBundle.loadString')));
    expect(logoSource, isNot(contains('base64Decode')));
    expect(logoSource, isNot(contains('FutureBuilder')));
    expect(mainSource, isNot(contains('preloadDohMyotDawLogo')));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo.png'));
    expect(pubspec, isNot(contains('doh_myot_daw_logo_1.b64')));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android launcher uses checked-in real logo resources', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final adaptiveRoundIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ).readAsStringSync();
    final adaptiveForeground = File(
      'android/app/src/main/res/drawable/dmd_launcher_foreground.xml',
    ).readAsStringSync();

    expect(gradle, isNot(contains('generateDmdBrandingResources')));
    expect(gradle, isNot(contains('generatedBrandingResDir')));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(adaptiveIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveIcon, contains('@drawable/dmd_launcher_foreground'));
    expect(adaptiveRoundIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveRoundIcon, contains('@drawable/dmd_launcher_foreground'));
    expect(adaptiveForeground, contains('@drawable/dmd_logo'));

    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File('android/app/src/main/res/mipmap-$density/ic_launcher.png')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/mipmap-$density/ic_launcher_round.png')
            .existsSync(),
        isTrue,
      );
    }

    expect(
      File('android/app/src/main/res/drawable-nodpi/dmd_logo.png').existsSync(),
      isTrue,
    );
  });

  test('native splash uses the same checked-in real logo bitmap', () {
    final launchBackground = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final launchBackgroundV21 = File(
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();
    final stylesV31 = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();

    expect(launchBackground, contains('@drawable/dmd_logo'));
    expect(launchBackgroundV21, contains('@drawable/dmd_logo'));
    expect(stylesV31, contains('@drawable/dmd_logo'));
    expect(stylesV31, contains('@color/dmd_brand_dark'));
    expect(colors, contains('<color name="dmd_brand_dark">#171614</color>'));
  });
}
