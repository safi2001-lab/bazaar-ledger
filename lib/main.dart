import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'app/app.dart';
import 'app/preferences.dart';
import 'app/providers.dart';

/// Opens the books, then draws the counter.
///
/// Two awaits and nothing else. There is no sign-in, no token refresh, no
/// "checking your subscription" spinner and no network call of any kind on
/// this path, because there is nothing on the other end of a network to call.
/// A shopkeeper with a customer at the counter and no signal opens this app in
/// the same time as one on fibre.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A counter is used in portrait on a phone and landscape on a tablet, and
  // both are the standard Pakistani retail setup. Nothing is locked.
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  final services = await AppServices.open();
  final prefs = await AppPreferences.load();

  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        initialPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const BazaarLedgerApp(),
    ),
  );
}
