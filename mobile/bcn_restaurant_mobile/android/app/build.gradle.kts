import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val dmdLogoParts = listOf(
    file("../../assets/images/doh_myot_daw_logo_1.b64"),
    file("../../assets/images/doh_myot_daw_logo_2.b64"),
    file("../../assets/images/doh_myot_daw_logo_3.b64"),
)

// Use a concrete File here instead of a Provider. Newer Android Gradle Plugin
// versions reject Provider instances passed to the legacy SourceSet API.
val generatedBrandingResDir = file("$buildDir/generated/dmdBranding/res")

val generateDmdBrandingResources = tasks.register("generateDmdBrandingResources") {
    inputs.files(dmdLogoParts)
    outputs.dir(generatedBrandingResDir)

    doLast {
        val encoded = dmdLogoParts.joinToString("") { logoPart ->
            logoPart.readText().filterNot { it.isWhitespace() }
        }
        val logoBytes = Base64.getDecoder().decode(encoded)
        val resRoot = generatedBrandingResDir
        val drawableDir = resRoot.resolve("drawable-nodpi").apply { mkdirs() }
        val mipmapDir = resRoot.resolve("mipmap-nodpi").apply { mkdirs() }

        drawableDir.resolve("dmd_logo.jpg").writeBytes(logoBytes)
        mipmapDir.resolve("ic_launcher.jpg").writeBytes(logoBytes)
        mipmapDir.resolve("ic_launcher_round.jpg").writeBytes(logoBytes)
    }
}

android {
    namespace = "com.bcn.restaurant.bcn_restaurant_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bcn.restaurant.bcn_restaurant_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets.getByName("main").res.srcDir(generatedBrandingResDir)

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(generateDmdBrandingResources)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
