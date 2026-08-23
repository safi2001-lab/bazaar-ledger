plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pk.bazaarledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "pk.bazaarledger"

        // 24, not 29 or 30. Roughly a fifth of the Android handsets in
        // Pakistan predate Android 11, and Transsion (Infinix, Tecno, itel)
        // is about 44% of the market at the bottom end. Raising the floor to
        // pick up a newer API is a decision to not sell to the shops this
        // product exists for.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only what the app can actually render. Flutter's default pulls in
        // every Material icon and every language's resources; a shopkeeper
        // sideloading this over Bluetooth during a shutdown pays for each
        // megabyte in minutes.
        resourceConfigurations += listOf("en", "ur")
    }

    buildTypes {
        release {
            // TODO: replace with a real upload key before the first Play
            // internal-track build. Debug keys are here only so
            // `flutter run --release` works on a bench device.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Per-ABI APKs instead of one fat binary matter here: Play splits an app
    // bundle on its own, but a real proportion of these installs arrive over
    // Bluetooth or SHAREit during a shutdown, and each megabyte is paid for in
    // minutes. That split is `flutter build apk --split-per-abi`, and it is
    // the Flutter tool's job, not this file's.
    //
    // Declaring `splits { abi { ... } }` here instead looked equivalent and
    // was not: the Flutter Gradle plugin sets `ndk.abiFilters` on every build,
    // and AGP refuses a project that carries both. It failed at configuration
    // time, before a single source file was read, so EVERY `flutter build apk`
    // and `flutter run` on Android died with "Conflicting configuration" — the
    // app had never once been installed on a handset. Nothing in the Dart
    // suite could see it, because none of it goes near Gradle.

    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.kotlin_module",
            )
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
