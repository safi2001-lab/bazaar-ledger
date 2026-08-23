import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What this app asks a shopkeeper's phone for.
///
/// A permission list is a promise, and it is the one promise a shopkeeper can
/// check without trusting anybody: it is printed on the Play listing. So it is
/// asserted here rather than left to whatever a plugin's manifest happens to
/// merge in.
///
/// Two failures this is guarding against, and both have already happened once
/// in this codebase:
///
///   * A permission arriving by accident. Several of the Bluetooth packages on
///     pub.dev declare ACCESS_FINE_LOCATION in their own manifests, and the
///     Android manifest merger pulls it into the app whether the app uses it
///     or not. Location is a restricted permission under Play policy, with a
///     declaration form and a review — earned by a billing app trying to find
///     a printer.
///   * A permission missing that a feature needs. The LAN printer transport
///     shipped against a release manifest with no INTERNET permission at all,
///     which Android requires for ANY socket, including one to a printer on
///     the shop's own Wi-Fi. Every test passed, because tests run on a host
///     where Android's permission model does not exist. It would have failed
///     on the first real phone.
void main() {
  final manifests = <String, File>{
    'app': File('android/app/src/main/AndroidManifest.xml'),
    'printer plugin': File(
      'packages/pk_printer_android/android/src/main/AndroidManifest.xml',
    ),
  };

  /// Every `android.permission.X` a manifest declares.
  Set<String> permissionsIn(File file) {
    final text = file.readAsStringSync();
    return RegExp(
      r'android:name="android\.permission\.([A-Z_]+)"',
    ).allMatches(text).map((m) => m.group(1)!).toSet();
  }

  test('every manifest that ships is present', () {
    for (final entry in manifests.entries) {
      expect(
        entry.value.existsSync(),
        isTrue,
        reason: 'the ${entry.key} manifest is missing',
      );
    }
  });

  test('nothing asks for location, ever', () {
    // The one that would cost a Play review, and the one most likely to
    // arrive by accident through a dependency rather than by decision.
    for (final entry in manifests.entries) {
      final asked = permissionsIn(entry.value);
      expect(
        asked.where((p) => p.contains('LOCATION')),
        isEmpty,
        reason:
            'the ${entry.key} manifest asks for location. A billing app '
            'does not need to know where the shopkeeper is standing, and '
            'location is a restricted permission with a declaration form.',
      );
    }
  });

  test('the app asks for exactly what its features need, and nothing else', () {
    // Every entry here has a feature behind it. A permission with no feature
    // behind it makes the Play Data Safety form a lie, so this list grows with
    // the milestone that earns it and not before.
    expect(
      permissionsIn(manifests['app']!),
      {
        // Android gates the creation of ANY socket behind this, including one
        // to a printer at 192.168.x.x on the shop's own Wi-Fi. There is no
        // narrower permission until ACCESS_LOCAL_NETWORK at targetSdk 37.
        'INTERNET',
        // Reading a barcode off a packet. Runtime-dangerous, not a Play
        // RESTRICTED permission: no declaration form, only an honest listing
        // and a privacy policy. Asked for when a shopkeeper taps scan and
        // never before, so a shop using a USB gun is never prompted.
        //
        // Deliberately still absent: READ_MEDIA_IMAGES. Item photographs go
        // through Android's own Photo Picker, which needs nothing at all, and
        // Play restricts that permission to apps whose core function the
        // picker cannot serve.
        'CAMERA',
      },
      reason:
          'the app manifest asks for something no feature needs, or is '
          'missing something a feature does',
    );
  });

  test('Bluetooth is asked for by the plugin that uses it', () {
    expect(permissionsIn(manifests['printer plugin']!), {
      // Capped at API 30 so Android 12 and above do not grant them.
      'BLUETOOTH',
      'BLUETOOTH_ADMIN',
      // Talking to an already-paired printer.
      'BLUETOOTH_CONNECT',
      // Declared with neverForLocation, asserted below.
      'BLUETOOTH_SCAN',
    });
  });

  test('scanning is declared as never being about location', () {
    // Without this flag Android treats a Bluetooth scan as a location signal
    // and requires ACCESS_FINE_LOCATION alongside it — which is how a printer
    // search turns into a location permission on the Play listing.
    final text = manifests['printer plugin']!.readAsStringSync();
    expect(
      text,
      contains('android:usesPermissionFlags="neverForLocation"'),
      reason: 'BLUETOOTH_SCAN without neverForLocation drags location in',
    );
  });

  test('the legacy Bluetooth pair stop at Android 11', () {
    final text = manifests['printer plugin']!.readAsStringSync();
    for (final legacy in const ['BLUETOOTH"', 'BLUETOOTH_ADMIN"']) {
      final at = text.indexOf('android.permission.$legacy');
      expect(at, greaterThan(-1));
      expect(
        text.substring(at, at + 200),
        contains('android:maxSdkVersion="30"'),
        reason: '$legacy is granted on Android 12+ where it does nothing',
      );
    }
  });

  test('the books are kept out of every backup Android performs', () {
    // The first screen of this app promises, in Roman Urdu, that the
    // shopkeeper's hisaab stays on this phone. `allowBackup` defaults to TRUE,
    // so without this it would be uploaded to a Google account they never
    // asked about.
    final text = manifests['app']!.readAsStringSync();
    expect(text, contains('android:allowBackup="false"'));
    expect(text, contains('android:dataExtractionRules='));
  });
}
