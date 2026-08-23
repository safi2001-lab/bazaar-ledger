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
// Why this task exists: GeneratedPluginRegistrant.java is one shared file that
// every Flutter command rewrites in its own build mode, and the release Gradle
// build reads it two minutes after the only command that writes it correctly.
//
// `integration_test` is a dev_dependency and has to stay one.
// integration_test/demo_script_test.dart and integration_test/cart_recovery_test.dart
// run against a real handset and are the device acceptance gate; dropping the
// dependency to make the release build compile would delete that gate.
//
// Flutter knows dev dependencies do not belong in a release APK. Two halves
// implement that, and they agree with each other:
//
//   * flutter_tools injectPlugins(releaseMode: true) drops isDevDependency
//     plugins from the registrant, so `flutter build apk --release` writes the
//     file with IntegrationTestPlugin absent, before it ever calls Gradle.
//   * PluginHandler.configurePluginProject adds a dev-dependency plugin to
//     every buildType's `Api` configuration EXCEPT release, so :integration_test
//     is deliberately not on the release compile classpath.
//
// What breaks it is that releaseMode is only ever true for the handful of
// commands that own a `--release` flag. `flutter pub get`, `flutter analyze`,
// `flutter test`, `flutter run`, and any IDE or editor plugin that runs a pub
// get on save all regenerate the same file with releaseMode: false, and put
// IntegrationTestPlugin straight back. Verified here: a bare `flutter pub get`
// flips the file, and so does a bare `flutter analyze`.
//
// `flutter build apk --release` takes about two and a half minutes, and
// :app:compileReleaseJavaWithJavac reads the registrant at the very end of it.
// So any of those commands landing in that window -- another terminal, an IDE
// analysing on save, a parallel CI step sharing the checkout -- poisons a build
// that was correct when it started, and javac dies on a class that is missing
// from the release classpath by design:
//
//     GeneratedPluginRegistrant.java:19: error:
//     package dev.flutter.plugins.integration_test does not exist
//
// The try/catch the tool wraps each registration in is no help; the failure is
// at compile time, not run time. Debug and profile never notice, because
// dev-dependency plugins really are on their classpath -- which is exactly why
// `flutter build apk --debug` and `flutter test integration_test/...` pass while
// only release fails, and why the failure reads as deterministic even though
// it is a race. `flutter build appbundle --release` runs the same javac task,
// so this blocks the Play upload, not merely a local APK.
//
// Upstream: https://github.com/flutter/flutter/issues/169336 -- same error, same
// generated line, still open (P2, c: regression). It is filed against `--no-pub`,
// which reaches the same state by a different road: skipping the regeneration
// leaves whatever non-release registrant was last written. The underlying
// design -- one mode-dependent generated file, rewritten by every command -- is
// what both share. Background: #161348 (dev dependencies removed from release
// registrants) and #56591 (plugins should not come from dev_dependencies).
//
// So: immediately before javac, and after everything Gradle itself runs, take
// whatever is in the file and delete the registration blocks for plugins that
// .flutter-plugins-dependencies marks "dev_dependency": true. Release variants
// only -- debug and profile keep every plugin, which is what lets
// `flutter test integration_test/... -d <device>` register IntegrationTestPlugin.
// This narrows the window from the whole Gradle run to the moments between this
// task and javac; it does not make it correct to run `flutter analyze` against
// this checkout while a release build is in flight.
//
// This is deliberately loud. If a later Flutter stops putting dev dependencies
// back, the task finds nothing and says nothing. But if the generated file
// changes shape so the stripping silently stops working, the task fails the
// build here rather than letting javac fail a minute later with the message
// this exists to prevent.
// ---------------------------------------------------------------------------

val flutterPluginsDependenciesFile = file("../../.flutter-plugins-dependencies")
val generatedPluginRegistrantFile =
    file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")

val stripDevDependencyPluginRegistrations =
    tasks.register("stripDevDependencyPluginRegistrations") {
        group = "flutter"
        description =
            "Removes dev_dependency plugin registrations from GeneratedPluginRegistrant.java " +
                "before the release variant compiles it."

        // Anything at all may have rewritten the registrant since the last run,
        // so there is no state in which skipping this is safe.
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

            // Checked before the early return on purpose: a registrant whose shape
            // has changed enough that no block matched would otherwise leave the
            // dev-dependency registration in place and say nothing about it.
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

            if (strippedPlugins.isEmpty()) {
                return@doLast
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
    // Must read what Gradle's own Flutter tasks left behind, not what preceded them.
    mustRunAfter(tasks.matching { it.name.matches(Regex("^compileFlutterBuild\\w*Release$")) })
}
