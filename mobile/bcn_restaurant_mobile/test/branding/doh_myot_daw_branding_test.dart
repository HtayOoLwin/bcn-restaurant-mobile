import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Doh Myot Daw logo uses embedded high-resolution artwork on Flutter screens', () {
    final logoSource = File(
      'lib/core/branding/doh_myot_daw_logo.dart',
    ).readAsStringSync();
    final loginSource = File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsStringSync();
    final routerSource = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(logoSource, contains('base64Decode(_dohMyotDawLogoBase64Chunks.join())'));
    expect(logoSource, contains('Image.memory('));
    expect(logoSource, contains('FilterQuality.high'));
    expect(logoSource, isNot(contains('rootBundle.loadString')));
    expect(logoSource, isNot(contains('FutureBuilder')));
    expect(pubspec, isNot(contains('assets/images/doh_myot_daw_logo.b64')));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android launcher uses a high-detail adaptive Doh Myot Daw icon', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final adaptiveRoundIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ).readAsStringSync();
    final vector = File(
      'android/app/src/main/res/drawable/dmd_logo_vector.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(adaptiveIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveIcon, contains('@drawable/dmd_logo_vector'));
    expect(adaptiveRoundIcon, contains('@color/dmd_brand_dark'));
    expect(adaptiveRoundIcon, contains('@drawable/dmd_logo_vector'));
    expect(vector, contains('android:viewportWidth="192"'));
    expect(vector, contains('android:viewportHeight="192"'));
  });

  test('native splash uses the same high-detail artwork on the dark brand background', () {
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

    expect(launchBackground, contains('@drawable/dmd_logo_vector'));
    expect(launchBackgroundV21, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@color/dmd_brand_dark'));
    expect(colors, contains('<color name="dmd_brand_dark">#171614</color>'));
  });
}
