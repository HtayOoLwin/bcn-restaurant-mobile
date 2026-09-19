import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BCN launcher and loading branding keep the full logo visible', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final launcher = File(
      'android/app/src/main/res/drawable/bcn_launcher_icon.xml',
    ).readAsStringSync();
    final splash = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();

    expect(pubspec, contains('assets/images/bcn_loading_logo.jpg'));
    expect(router, contains("Image.asset('assets/images/bcn_loading_logo.jpg'"));
    expect(router, contains('fit: BoxFit.contain'));
    expect(router, isNot(contains('ClipRRect(')));
    expect(router, contains("'BCN Restaurant'"));
    expect(manifest, contains('android:icon="@drawable/bcn_launcher_icon"'));
    expect(manifest, contains('android:label="BCN Restaurant"'));
    expect(launcher, contains('@drawable/bcn_app_icon'));
    expect(launcher, contains('android:left="8dp"'));
    expect(splash, contains('@drawable/bcn_app_icon'));
  });
}
