import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter branding loads after runApp and never blocks application startup', () {
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

    expect(mainSource, isNot(contains('await preloadDohMyotDawLogo')));
    expect(mainSource, isNot(contains('preloadDohMyotDawLogo')));
    expect(logoSource, contains('FutureBuilder<Uint8List>'));
    expect(logoSource, contains('rootBundle.loadString'));
    expect(logoSource, contains('Image.memory('));
    expect(logoSource, contains('FilterQuality.high'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_1.b64'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_2.b64'));
    expect(pubspec, contains('assets/images/doh_myot_daw_logo_3.b64'));
    expect(loginSource, contains('DohMyotDawLogo('));
    expect(routerSource, contains('DohMyotDawLogo('));
  });

  test('Android launcher and splash do not depend on generated resources', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
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

    expect(gradle, isNot(contains('generateDmdBrandingResources')));
    expect(gradle, isNot(contains('generatedBrandingResDir')));
    expect(manifest, contains('android:icon="@drawable/dmd_logo_vector"'));
    expect(manifest, contains('android:roundIcon="@drawable/dmd_logo_vector"'));
    expect(launchBackground, contains('@drawable/dmd_logo_vector'));
    expect(launchBackgroundV21, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@drawable/dmd_logo_vector'));
    expect(stylesV31, contains('@color/dmd_brand_dark'));
  });
}
