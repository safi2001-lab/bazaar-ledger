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

// ---------------------------------------------------------------------------
// Why this task exists: the release build regenerates the plugin registrant
// behind its own back, and hands javac a file that cannot compile.
//
// `integration_test` is a dev_dependency and has to stay one.
// integration_test/demo_script_test.dart and integration_test/cart_recovery_test.dart
// run against a real handset and are the device acceptance gate; dropping the
// dependency to make the release build pass would delete that gate.
//
// Flutter already knows dev dependencies do not belong in a release APK, and
// gets it right twice. The front half of `flutter build apk --release` writes
// GeneratedPluginRegistrant.java with IntegrationTestPlugin correctly absent
// (flutter_tools injectPlugins(releaseMode: true) filters isDevDependency), and
// the Flutter Gradle plugin correspondingly refuses to put :integration_test on
// the release compile classpath (PluginHandler.configurePluginProject adds a
// dev-dependency plugin to every buildType's Api configuration except release).
// Those two agree, and the release APK is right.
//
// Then it undoes one half. `:app:compileFlutterBuildRelease` shells out to
// `flutter assemble`, and that process regenerates the registrant with no
// release filter applied: `flutter assemble` is handed its mode as the
// build-system define `-dBuildMode=release` and owns no `--release` flag, so
// FlutterCommand.getBuildMode() cannot see it and falls back to
// `defaultBuildMode` -- BuildMode.debug for any command that never called
// addBuildModeFlags(). The registration comes back, timestamped about ten
// seconds into that task, and :app:compileReleaseJavaWithJavac runs a minute
// later against the classpath that deliberately lacks the class:
//
//     GeneratedPluginRegistrant.java:19: error:
//     package dev.flutter.plugins.integration_test does not exist
//
// The try/catch the tool wraps each registration in is no help; the failure is
// at compile time, not run time. It reproduces from a cold
// `flutter clean && flutter pub get && flutter build apk --release` on Flutter
// 3.44.9, and hits `flutter build appbundle --release` identically -- so it
// blocks the Play upload, not merely a local APK. It looks intermittent only
// because an incremental build whose `flutter assemble` targets are all
// up-to-date never rewrites the file, and then javac sees the good one.
//
// Upstream: https://github.com/flutter/flutter/issues/169336 -- same error, same
// generated line, still open. There is no supported flag to opt out: the
// filtering is meant to be automatic, so there is nothing to configure.
//
// So: after `flutter assemble` has had its say and before javac reads the file,
// delete the registration blocks for whatever .flutter-plugins-dependencies
// marks "dev_dependency": true. Release variants only -- debug and profile keep
// every plugin, which is exactly what lets `flutter test integration_test/...`
// register IntegrationTestPlugin on a device.
//
// This is deliberately loud. If a later Flutter starts filtering correctly the
// task finds nothing and says nothing; but if the generated file changes shape
// so the stripping stops working, the task fails the build here rather than
// letting javac fail sixty seconds later with the message this exists to
// prevent.
// ---------------------------------------------------------------------------

val flutterPluginsDependenciesFile = file("../../.flutter-plugins-dependencies")
val generatedPluginRegistrantFile =
    file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")

val stripDevDependencyPluginRegistrations =
    tasks.register("stripDevDependencyPluginRegistrations") {
        group = "flutter"
        description =
            "Removes the dev_dependency plugin registrations that `flutter assemble` " +
                "writes back into GeneratedPluginRegistrant.java during release builds."

        // compileFlutterBuild<Variant> rewrites the registrant on every run that
        // is not fully up to date, so there is no state in which skipping this
        // is safe.
        outputs.upToDateWhen { false }

        doLast {
            check(flutterPluginsDependenciesFile.isFile) {
                "$flutterPluginsDependenciesFile is missing, so this build cannot tell " +
                    "which plugins are dev dependencies. Run `flutter pub get`."
            }
            check(generatedPluginRegistrantFile.isFile) {
                "$generatedPluginRegistrantFile is missing. Run `flutter build apk --config-only`."
            }

            @Suppress("UNCHECKED_CAST")
            val manifest =
                groovy.json.JsonSlurper().parse(flutterPluginsDependenciesFile)
                    as Map<String, Any?>

            @Suppress("UNCHECKED_CAST")
            val androidPlugins =
                (manifest["plugins"] as Map<String, Any?>)["android"] as List<Map<String, Any?>>
            val devDependencyPlugins =
                androidPlugins
                    .filter { it["dev_dependency"] == true }
                    .map { it["name"] as String }
            if (devDependencyPlugins.isEmpty()) {
                return@doLast
            }

            val original = generatedPluginRegistrantFile.readText()
            check(original.contains("class GeneratedPluginRegistrant")) {
                "$generatedPluginRegistrantFile does not look like Flutter's generated " +
                    "registrant; refusing to edit it."
            }

            val lines = original.lines()
            val kept = mutableListOf<String>()
            val strippedPlugins = mutableListOf<String>()
            var index = 0
            while (index < lines.size) {
                if (lines[index].trim() != "try {") {
                    kept.add(lines[index])
                    index++
                    continue
                }
                // One registration is one try { ... } catch (Exception e) { ... }
                // block, and the catch's log message is the only place the pub
                // package name appears, so it is what identifies the block's owner.
                val block = mutableListOf<String>()
                var end = index
                var sawCatch = false
                while (end < lines.size) {
                    block.add(lines[end])
                    if (lines[end].contains("catch (Exception e) {")) {
                        sawCatch = true
                    }
                    if (sawCatch && lines[end].trim() == "}") {
                        break
                    }
                    end++
                }
                val owner =
                    devDependencyPlugins.firstOrNull { name ->
                        block.any { it.contains("Error registering plugin " + name + ",") }
                    }
                if (owner == null) {
                    kept.addAll(block)
                } else {
                    strippedPlugins.add(owner)
                }
                index = end + 1
            }

            if (strippedPlugins.isEmpty()) {
                return@doLast
            }

            val rewritten = kept.joinToString("\n")
            val survivors =
                devDependencyPlugins.filter {
                    rewritten.contains("Error registering plugin " + it + ",")
                }
            check(survivors.isEmpty()) {
                "Could not strip the dev-dependency plugin registration(s) $survivors from " +
                    "$generatedPluginRegistrantFile. Flutter's generated registrant has " +
                    "changed shape -- see the comment above this task."
            }
            generatedPluginRegistrantFile.writeText(rewritten)
            logger.lifecycle(
                "Stripped dev-dependency plugin registration(s) from " +
                    "GeneratedPluginRegistrant.java for the release build: " +
                    strippedPlugins.joinToString(", "),
            )
        }
    }

tasks.matching { it.name.matches(Regex("^compile\\w*ReleaseJavaWithJavac$")) }.configureEach {
    dependsOn(stripDevDependencyPluginRegistrations)
}

stripDevDependencyPluginRegistrations.configure {
    // Must observe what `flutter assemble` left behind, not what preceded it.
    mustRunAfter(tasks.matching { it.name.matches(Regex("^compileFlutterBuild\\w*Release$")) })
}
