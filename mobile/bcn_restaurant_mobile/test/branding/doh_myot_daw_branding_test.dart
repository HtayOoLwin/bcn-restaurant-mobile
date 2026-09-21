import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter branding uses the supplied Doh Myot Daw artwork without blocking startup', () {
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

    expect(mainSource, isNot(contains('await preloadDohMyotDawLogo')));
    expect(logoSource, contains('FutureBuilder<Uint8List>'));
    expect(logoSource, contains('rootBundle.loadString'));
    expect(logoSource, contains('Image.memory('));
    expect(logoSource, contains('FilterQuality.high'));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android launcher decodes the same supplied artwork into normal resource folders', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final adaptiveForeground = File(
      'android/app/src/main/res/drawable/dmd_launcher_foreground.xml',
    ).readAsStringSync();

    expect(gradle, contains('prepareDmdBrandingResources'));
    expect(gradle, contains('Base64.getDecoder().decode(encoded)'));
    expect(gradle, contains('src/main/res/drawable-nodpi'));
    expect(gradle, contains('src/main/res/mipmap-nodpi'));
    expect(gradle, isNot(contains('sourceSets.getByName')));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(adaptiveForeground, contains('@drawable/dmd_logo'));
  });

  test('native splash uses the same decoded real logo artwork', () {
    final launchBackground = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final launchBackgroundV21 = File(
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();
    final stylesV31 = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();

    expect(launchBackground, contains('@drawable/dmd_logo'));
    expect(launchBackgroundV21, contains('@drawable/dmd_logo'));
    expect(stylesV31, contains('@drawable/dmd_logo'));
  });
}
