plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sonus.sonus_next"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sonus.sonus_next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two installs of Sonus (App Update 1.2 device QA):
    // - prod: the app as it has always been, com.sonus.sonus_next;
    // - qa: com.sonus.sonus_next.qa, "Sonus QA", beside it. A separate package
    //   has its own database, preferences, artwork and sign-in state, so QA
    //   can never touch the real library. tool/build-qa.ps1 builds it with no
    //   account settings, so it has no cloud at all.
    flavorDimensions += "distribution"
    productFlavors {
        create("prod") {
            dimension = "distribution"
            resValue("string", "app_name", "Sonus")
        }
        create("qa") {
            dimension = "distribution"
            applicationIdSuffix = ".qa"
            resValue("string", "app_name", "Sonus QA")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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
