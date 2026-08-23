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

    // Four APKs instead of one fat binary. Play splits by ABI on its own for
    // an app bundle; this is for the direct-download and SHAREit path, which
    // is how a real proportion of these installs happen.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

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
