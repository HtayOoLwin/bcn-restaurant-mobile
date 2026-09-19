import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BCN launcher and loading branding keep the full logo visible', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final splash = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();

    expect(pubspec, contains('assets/images/bcn_loading_logo.png'));
    expect(router, contains("Image.asset('assets/images/bcn_loading_logo.png'"));
    expect(router, contains('fit: BoxFit.contain'));
    expect(router, isNot(contains('ClipRRect(')));
    expect(router, contains("'BCN Restaurant'"));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:label="BCN Restaurant"'));
    expect(splash, contains('@drawable/launch_image'));
  });
}
