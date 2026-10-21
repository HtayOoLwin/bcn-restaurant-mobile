# OurCity Restaurant — Google Play production build

App display name: **OurCity Restaurant**  
Application ID: **com.bcn.restaurant.bcn_restaurant_mobile**  
Branch: `release/play-console-signing-20261021`

## Local signing (never commit the actual credentials)

1. Open `mobile/bcn_restaurant_mobile` in your terminal.
2. Create your upload keystore once:

```powershell
keytool -genkeypair -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 3072 -validity 10000 -alias upload
```

3. Copy `android/key.properties.example` to `android/key.properties`. Replace both passwords; leave `storeFile=../upload-keystore.jks`.
4. Keep the keystore and passwords in an encrypted offsite backup. Do NOT commit, email or paste them.
5. Inspect/update `pubspec.yaml` version (increase build number for every new upload) and confirm installed Flutter resolves `flutter.targetSdkVersion` to the currently Play-required API level.
6. Build:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Expected AAB: `build/app/outputs/bundle/release/app-release.aab`.

The Gradle build now uses a release signing configuration when local `android/key.properties` exists. Missing release keys cause a release task to fail instead of silently using debug keys.

Before uploading: validate AAB package ID, version code, target API, app icon, and Google Play's Play App Signing/onboarding and app-content requirements. Do not recreate or replace an existing app's original upload key without first confirming Play signing/enrollment state.
