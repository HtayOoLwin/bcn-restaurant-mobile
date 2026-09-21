import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Doh Myot Daw logo is preloaded before Flutter UI starts', () {
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

    expect(logoSource, contains('Future<void> preloadDohMyotDawLogo()'));
    expect(
      logoSource,
      contains("rootBundle.loadString('assets/images/doh_myot_daw_logo_1.b64')"),
    );
    expect(
      logoSource,
      contains("rootBundle.loadString('assets/images/doh_myot_daw_logo_2.b64')"),
    );
    expect(
      logoSource,
      contains("rootBundle.loadString('assets/images/doh_myot_daw_logo_3.b64')"),
    );
    expect(logoSource, contains('Image.memory('));
    expect(logoSource, contains('FilterQuality.high'));
    expect(logoSource, isNot(contains('FutureBuilder')));
    expect(mainSource, contains('await preloadDohMyotDawLogo();'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_1.b64'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_2.b64'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_3.b64'));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android build generates launcher bitmaps from the same real logo data', () {
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

    expect(gradle, contains('generateDmdBrandingResources'));
    expect(gradle, contains('Base64.getDecoder().decode(encoded)'));
    expect(gradle, contains('dmd_logo.jpg'));
    expect(gradle, contains('ic_launcher.jpg'));
    expect(gradle, contains('ic_launcher_round.jpg'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(adaptiveIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveIcon, contains('@drawable/dmd_launcher_foreground'));
    expect(adaptiveRoundIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveRoundIcon, contains('@drawable/dmd_launcher_foreground'));
    expect(adaptiveForeground, contains('@drawable/dmd_logo'));
  });

  test('native splash uses the generated real logo bitmap on the dark brand background', () {
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
