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

// Decode the exact supplied Doh Myot Daw artwork directly into Android's
// normal resource folders before Android resource processing starts.
// This avoids generated SourceSet Provider issues and keeps launcher/splash
// using the same artwork as Flutter login/loading screens.
val prepareDmdBrandingResources = tasks.register("prepareDmdBrandingResources") {
    inputs.files(dmdLogoParts)

    val drawableDir = file("src/main/res/drawable-nodpi")
    val mipmapDir = file("src/main/res/mipmap-nodpi")
    outputs.files(
        drawableDir.resolve("dmd_logo.jpg"),
        mipmapDir.resolve("ic_launcher.jpg"),
        mipmapDir.resolve("ic_launcher_round.jpg"),
    )

    doLast {
        val encoded = dmdLogoParts.joinToString("") { logoPart ->
            logoPart.readText().filterNot { it.isWhitespace() }
        }
        val logoBytes = Base64.getDecoder().decode(encoded)

        drawableDir.mkdirs()
        mipmapDir.mkdirs()

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
        applicationId = "com.bcn.restaurant.bcn_restaurant_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(prepareDmdBrandingResources)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
