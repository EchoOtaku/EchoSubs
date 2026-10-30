plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A process-scoped opt-in keeps integration tests out of the user's app data.
val isolatedIntegration = providers.environmentVariable("ECHOSUBS_INTEGRATION_TEST").orNull == "1"
val dartTarget = providers.gradleProperty("target").orNull?.replace('\\', '/') ?: ""
val integrationTarget = dartTarget.contains("integration_test/")
check(!integrationTarget || isolatedIntegration) {
    "Integration targets require ECHOSUBS_INTEGRATION_TEST=1; use integration_test/support/run_native.ps1"
}

android {
    namespace = "dev.echootaku.echo_subs"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.echootaku.echo_subs"
        manifestPlaceholders["appLabel"] = "EchoSubs 订阅簿"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            if (isolatedIntegration) {
                applicationIdSuffix = ".integration"
                manifestPlaceholders["appLabel"] = "EchoSubs 集成测试"
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    beforeVariants(selector().all()) { variant ->
        // Non-debug integration variants must not exist: their applicationId
        // would otherwise still be the production ID. Leave normal builds alone.
        if (integrationTarget && variant.buildType != "debug") variant.enable = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
