import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Doh Myot Daw logo is shared by Flutter loading and login screens', () {
    final logoSource = File(
      'lib/core/branding/doh_myot_daw_logo.dart',
    ).readAsStringSync();
    final loginSource = File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsStringSync();
    final routerSource = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();

    expect(logoSource, contains('class _DohMyotDawLogoPainter'));
    expect(logoSource, contains('static const int _gridSize = 40'));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android launcher and native splash use Doh Myot Daw branding', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
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

    expect(manifest, contains('android:icon="@drawable/dmd_logo_vector"'));
    expect(manifest, contains('android:roundIcon="@drawable/dmd_logo_vector"'));
    expect(launchBackground, contains('@drawable/dmd_logo_vector'));
    expect(launchBackgroundV21, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@color/dmd_brand_dark'));
    expect(colors, contains('<color name="dmd_brand_dark">#171614</color>'));
  });
}
