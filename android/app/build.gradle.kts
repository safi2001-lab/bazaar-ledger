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
// Why the release build does not compile Flutter's GeneratedPluginRegistrant.java
// out of the source tree, and compiles a private copy of it instead.
//
// `integration_test` is a dev_dependency and has to stay one.
// integration_test/demo_script_test.dart and integration_test/cart_recovery_test.dart
// run against a real handset and are the device acceptance gate; dropping the
// dependency to make the release build compile would delete that gate.
//
// Flutter knows dev dependencies do not belong in a release APK, and says so in
// two places that agree with each other: the tool writes the registrant without
// IntegrationTestPlugin when it is building a release, and the Flutter Gradle
// plugin correspondingly refuses to put :integration_test on the release compile
// classpath. The trouble is that the registrant is a single file in the source
// tree, and *every* Flutter command rewrites it in that command's own build
// mode. `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`, an
// IDE running pub get on save -- all of them put IntegrationTestPlugin back.
//
// A release Gradle run takes about two and a half minutes and javac reads that
// file at the very end of it. So any of those commands, from another terminal or
// another agent sharing this checkout, turns a build that was correct when it
// started into:
//
//     GeneratedPluginRegistrant.java:19: error:
//     package dev.flutter.plugins.integration_test does not exist
//
// The try/catch the tool wraps each registration in is no help; the failure is at
// compile time, not run time. Debug and profile never notice, because
// dev-dependency plugins really are on their classpath -- which is why only
// release fails. `flutter build appbundle --release` runs the same javac task, so
// this blocks the Play upload and not merely a local APK.
//
// Upstream: https://github.com/flutter/flutter/issues/169336 -- same error, same
// generated line, still open. There is no supported flag to opt out; the
// filtering is meant to be automatic. Background: #161348 and #56591.
//
// Fixing the file in place does not work, and this was learned the expensive way.
// Stripping it in a task ordered before javac leaves the asset and resource tasks
// running in between, and a build here died in exactly that ten-second gap.
// Moving the strip into javac's own doFirst narrowed the gap to milliseconds and
// still lost to a writer running every two seconds. Anything that leaves javac
// reading a path outside build/ is a race against every other Flutter process on
// the machine, and races of that shape cannot be won, only narrowed.
//
// So javac does not read that path at all. The registrant is excluded from the
// main source set, and each build type compiles a copy generated into build/,
// which no Flutter command writes: release gets the copy with dev-dependency
// registrations removed, debug and profile get it verbatim so that
// `flutter test integration_test/... -d <device>` still registers
// IntegrationTestPlugin. Whatever happens to the source-tree file after the copy
// is taken is no longer the compiler's problem.
//
// This is deliberately loud. If a later Flutter stops putting dev dependencies
// back, the generator finds nothing to remove and says nothing. If the generated
// file changes shape so the removal silently stops working, the build fails here
// rather than letting javac fail later with the message this exists to prevent.
// Reads are retried first, because the same concurrency that motivates all of
// this can also catch the file halfway through being written, and a torn read is
// not a shape change.
// ---------------------------------------------------------------------------

abstract class GenerateFlutterPluginRegistrant : DefaultTask() {
    @get:Internal
    abstract val registrantSource: RegularFileProperty

    @get:Internal
    abstract val pluginManifest: RegularFileProperty

    @get:Input
    abstract val stripDevDependencies: Property<Boolean>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val source = registrantSource.get().asFile
        val manifest = pluginManifest.get().asFile
        check(source.isFile) {
            "$source is missing. Run `flutter build apk --config-only`."
        }
        check(manifest.isFile) {
            "$manifest is missing, so this build cannot tell which plugins are dev " +
                "dependencies. Run `flutter pub get`."
        }

        val devDependencyPlugins =
            if (stripDevDependencies.get()) devDependencyPluginNames() else emptyList()

        var problem: String? = null
        repeat(5) { attempt ->
            if (attempt > 0) {
                Thread.sleep(250L)
            }
            val original = source.readText()
            if (!original.contains("class GeneratedPluginRegistrant") ||
                !original.trimEnd().endsWith("}")
            ) {
                problem = "$source does not look like a complete Flutter plugin registrant"
                return@repeat
            }

            val stripped = mutableListOf<String>()
            val rewritten =
                if (devDependencyPlugins.isEmpty()) {
                    original
                } else {
                    withoutRegistrationsFor(original, devDependencyPlugins, stripped)
                }
            val survivors =
                devDependencyPlugins.filter {
                    rewritten.contains("Error registering plugin " + it + ",")
                }
            if (survivors.isNotEmpty()) {
                problem = "could not remove the dev-dependency plugin registration(s) " +
                    "$survivors from $source"
                return@repeat
            }

            val destination = outputDirectory.get().dir("io/flutter/plugins")
            destination.asFile.mkdirs()
            val copy = destination.file("GeneratedPluginRegistrant.java").asFile
            if (!copy.isFile || copy.readText() != rewritten) {
                copy.writeText(rewritten)
            }
            if (stripped.isNotEmpty()) {
                logger.lifecycle(
                    "Release plugin registrant: left out " + stripped.joinToString(", ") +
                        " (dev dependencies are not on the release classpath)",
                )
            }
            return
        }

        throw GradleException(
            "After five attempts over about a second, $problem. A concurrent `flutter` " +
                "command rewriting the file would have settled by now, so Flutter's " +
                "generated registrant has probably changed shape -- see the comment above " +
                "this task.",
        )
    }

    private fun devDependencyPluginNames(): List<String> {
        @Suppress("UNCHECKED_CAST")
        val parsed =
            groovy.json.JsonSlurper().parse(pluginManifest.get().asFile) as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        val androidPlugins =
            (parsed["plugins"] as Map<String, Any?>)["android"] as List<Map<String, Any?>>
        return androidPlugins
            .filter { it["dev_dependency"] == true }
            .map { it["name"] as String }
    }

    /**
     * One registration is one try { ... } catch (Exception e) { ... } block, and the
     * catch's log message is the only place the pub package name appears, so it is
     * what identifies which plugin a block belongs to.
     */
    private fun withoutRegistrationsFor(
        original: String,
        pluginNames: List<String>,
        removed: MutableList<String>,
    ): String {
        val lines = original.lines()
        val kept = mutableListOf<String>()
        var index = 0
        while (index < lines.size) {
            if (lines[index].trim() != "try {") {
                kept.add(lines[index])
                index++
                continue
            }
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
                pluginNames.firstOrNull { name ->
                    block.any { it.contains("Error registering plugin " + name + ",") }
                }
            if (owner == null) {
                kept.addAll(block)
            } else {
                removed.add(owner)
            }
            index = end + 1
        }
        return kept.joinToString("\n")
    }
}

val flutterRegistrantSource = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
val flutterPluginsDependenciesFile = file("../../.flutter-plugins-dependencies")

// Only release drops anything; debug and profile take a verbatim copy purely so
// that nothing compiles the shared file.
val registrantGenerators =
    listOf("debug" to false, "profile" to false, "release" to true).associate { (buildType, strip) ->
        val capitalized = buildType.replaceFirstChar { it.uppercase() }
        buildType to
            tasks.register<GenerateFlutterPluginRegistrant>(
                "generate${capitalized}FlutterPluginRegistrant",
            ) {
                group = "flutter"
                description =
                    "Copies Flutter's generated plugin registrant into build/ for the " +
                        "$buildType variant, so the compiler never reads the shared file."
                registrantSource.set(flutterRegistrantSource)
                pluginManifest.set(flutterPluginsDependenciesFile)
                stripDevDependencies.set(strip)
                outputDirectory.set(
                    layout.buildDirectory.dir("generated/flutterPluginRegistrant/$buildType"),
                )
                // The source is rewritten by other Flutter processes at unpredictable
                // times, so it is not worth tracking; regenerating is cheap and the
                // output is what javac's own up-to-date check looks at.
                outputs.upToDateWhen { false }
            }
    }

// Unqualified `java` inside a sourceSets lambda binds to the script's own java
// accessor rather than the source set's, so reach the extension explicitly, and
// the declared source-set interface does not expose the pattern filter even
// though the implementation behind it does.
val androidExtension =
    project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
(
    androidExtension.sourceSets.getByName("main").java
        as org.gradle.api.tasks.util.PatternFilterable
).exclude("io/flutter/plugins/GeneratedPluginRegistrant.java")

// AGP 9 refuses providers through the source-set API and directs generated
// directories to the variant API, which has the happy side effect of wiring the
// task dependency itself.
extensions
    .getByType(com.android.build.api.variant.ApplicationAndroidComponentsExtension::class.java)
    .onVariants { variant ->
        val generator =
            checkNotNull(registrantGenerators[variant.buildType]) {
                "Nothing generates a plugin registrant for build type " +
                    "${variant.buildType}, so the ${variant.name} variant would compile " +
                    "without one."
            }
        checkNotNull(variant.sources.java) {
            "The ${variant.name} variant has no Java sources to add the generated " +
                "plugin registrant to."
        }.addGeneratedSourceDirectory(generator) { it.outputDirectory }
    }
