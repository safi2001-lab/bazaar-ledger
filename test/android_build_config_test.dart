import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the Android build is configured to do, asserted on the files rather
/// than trusted.
///
/// None of this needs an emulator, which is the point: these are the Android
/// facts a host machine can still prove when no device is attached, and they
/// are the ones that decide whether an artefact is shippable at all.
///
/// Three failures this guards, all of which were live in this repository:
///
///   * The release build was signed with the ANDROID DEBUG KEY. A TODO said so,
///     and `analysis_options.base.yaml` sets `todo: ignore`, so the analyser
///     never mentioned it. Every release APK CI had ever produced was
///     unpublishable, and nothing said a word.
///   * `compileSdk` and `targetSdk` were inherited from whatever Android SDK
///     the developer's Flutter install had resolved. targetSdk decides the
///     runtime permission model, whether `allowBackup` or `dataExtractionRules`
///     governs backup, and — from API 36 — whether edge-to-edge enforcement
///     applies with no opt-out. That is not a thing to inherit.
///   * The Gradle wrapper was gitignored. `**/android/gradle/` swept up
///     `gradle-wrapper.properties`, the only place Gradle 9.1.0 is pinned for
///     AGP 9.0.1, so a fresh clone built against whatever was lying around.
void main() {
  final appGradle = File('android/app/build.gradle.kts');
  final pluginGradle = File(
    'packages/pk_printer_android/android/build.gradle.kts',
  );

  /// The integer assigned to `name`, e.g. `compileSdk = 36`.
  int? assignedInt(File file, String name) {
    final match = RegExp(
      '$name\\s*=\\s*(\\d+)',
    ).firstMatch(file.readAsStringSync());
    return match == null ? null : int.parse(match.group(1)!);
  }

  test('the SDK levels are literals, not whatever the toolchain resolved', () {
    final source = appGradle.readAsStringSync();
    for (final property in const ['compileSdk', 'targetSdk']) {
      expect(
        source,
        isNot(contains('$property = flutter.')),
        reason:
            '$property tracks the developer\'s Flutter install, so the '
            'app\'s permission model changes with a toolchain upgrade and no '
            'diff in this repository',
      );
    }
  });

  test('the app targets API 36, which Play requires from 31 August 2026', () {
    expect(assignedInt(appGradle, 'compileSdk'), 36);
    expect(assignedInt(appGradle, 'targetSdk'), 36);
  });

  test('the floor stays at 24, where a fifth of the market lives', () {
    // Roughly a fifth of Android handsets in Pakistan predate Android 11, and
    // Transsion is about 44% of the bottom end. Raising this to pick up a
    // newer API is a decision to stop selling to the shops this exists for.
    expect(assignedInt(appGradle, 'minSdk'), 24);
    expect(assignedInt(pluginGradle, 'minSdk'), 24);
  });

  test('the app and its printer plugin compile against the same SDK', () {
    expect(
      assignedInt(pluginGradle, 'compileSdk'),
      assignedInt(appGradle, 'compileSdk'),
      reason:
          'the app and the plugin have drifted apart, so the manifest '
          'merger is reconciling two different platform contracts',
    );
  });

  test('a release build is never signed with the debug key', () {
    final source = appGradle.readAsStringSync();
    expect(
      source,
      isNot(contains('signingConfigs.getByName("debug")')),
      reason:
          'the release build falls back to the Android debug key, which '
          'produces an artefact that looks fine, uploads to nothing, and '
          'cannot be published',
    );
    expect(
      source,
      contains('key.properties'),
      reason:
          'the release signing config should come from a gitignored '
          'key.properties',
    );
    expect(
      source,
      contains('if (hasUploadKey)'),
      reason:
          'without a key the release build must fail rather than sign '
          'itself with something else',
    );
  });

  test('a release build without a key stops instead of shipping unsigned', () {
    // Setting `signingConfig = null` was not enough, and finding that out cost
    // a build: Gradle assembled an UNSIGNED APK and `flutter build apk
    // --release` exited 0 with "Built app-release.apk (23.4MB)". `apksigner
    // verify` on that file says DOES NOT VERIFY / Missing META-INF/MANIFEST.MF.
    // So the build stopped producing a debug-signed artefact that looks
    // publishable and started producing an unsigned one that looks
    // publishable. The task-graph guard is what actually refuses.
    final source = appGradle.readAsStringSync();
    expect(
      source,
      contains('gradle.taskGraph.whenReady'),
      reason:
          'nothing refuses a keyless release build, so it will hand over '
          'an unsigned APK and report success',
    );
    expect(source, contains('throw GradleException'));
    expect(
      source,
      contains('--profile'),
      reason:
          'the error should name the escape hatch for bench work, or the '
          'next person will reach for the debug key again',
    );
  });

  test('the keystore and its passwords are not in the repository', () {
    final ignored = File('.gitignore').readAsStringSync();
    for (final pattern in const ['key.properties', '*.jks', '*.keystore']) {
      expect(
        ignored,
        contains(pattern),
        reason:
            '$pattern is not ignored; committing it lets anyone publish '
            'as us, and losing it means never updating the app again',
      );
    }
    expect(File('android/key.properties').existsSync(), isFalse);
  });

  test('the Gradle wrapper is committed and pins a version', () {
    final properties = File('android/gradle/wrapper/gradle-wrapper.properties');
    expect(
      properties.existsSync(),
      isTrue,
      reason: 'a fresh clone has no pinned Gradle, and AGP 9.0.1 needs one',
    );
    expect(properties.readAsStringSync(), contains('distributionUrl'));

    final tracked = Process.runSync('git', const [
      'ls-files',
      'android/gradle/wrapper/',
    ], runInShell: true).stdout.toString();
    expect(
      tracked,
      contains('gradle-wrapper.properties'),
      reason:
          'the wrapper exists on this machine but git is not tracking it, '
          'which is exactly the state that hid the missing pin',
    );
  });

  test('the JVM crash dumps are gone and stay gone', () {
    // Two of these, 4.4 MB between them, sat in android/ for days.
    final strays = Directory('android')
        .listSync()
        .whereType<File>()
        .where(
          (f) => f.path.contains('hs_err_pid') || f.path.contains('replay_pid'),
        )
        .toList();
    expect(strays, isEmpty);
    expect(File('.gitignore').readAsStringSync(), contains('hs_err_pid'));
  });

  test('R8 and resource shrinking are on for release', () {
    final source = appGradle.readAsStringSync();
    expect(source, contains('isMinifyEnabled = true'));
    expect(source, contains('isShrinkResources = true'));
  });

  test('only the two locales the app can render are packaged', () {
    // Flutter's default pulls in every language's resources. A shopkeeper
    // sideloading this over Bluetooth during a shutdown pays for each
    // megabyte in minutes.
    expect(
      appGradle.readAsStringSync(),
      contains('resourceConfigurations += listOf("en", "ur")'),
    );
  });
}
