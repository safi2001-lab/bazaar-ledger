import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_printer_android/pk_printer_android.dart';

import 'app/app.dart';
import 'app/localisation.dart';
import 'app/preferences.dart';
import 'app/providers.dart';
import 'design/components.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'l10n/app_strings.dart';

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

  // Preferences first, and they cannot fail: a corrupt file returns defaults.
  // So whatever happens next is at least readable in the right language.
  final prefs = await AppPreferences.load();

  final AppServices services;
  try {
    services = await AppServices.open(transports: _printerTransports());
  } on Object catch (error, stack) {
    // The database would not open: a corrupt file, a full disk, a schema from
    // a newer build. Before this, that was a black screen — the app died
    // before the first frame with nothing on it.
    //
    // A shopkeeper who opens the app to a crash has lost their business day.
    // One who is told what happened, in their own language, still has a phone
    // they can hand to someone who can help, and — from M5 — a restore button.
    runApp(_StartupFailureApp(prefs: prefs, error: error, stack: stack));
    return;
  }

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

/// The app when there is no database to run it against.
///
/// Deliberately its own MaterialApp with no ProviderScope: everything above
/// this point failed, so nothing below it may depend on anything that could
/// also fail. It needs the localisations and the tokens, and nothing else.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({
    required this.prefs,
    required this.error,
    required this.stack,
  });

  final AppPreferences prefs;
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bazaar Ledger',
      debugShowCheckedModeBanner: false,
      theme: blTheme(dark: false),
      darkTheme: blTheme(dark: true),
      themeMode: prefs.themeMode,
      locale: prefs.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [AppStrings.delegate, ...chromeDelegates],
      home: Builder(
        builder: (context) {
          final s = AppStrings.of(context);
          final t = context.bl;
          return Scaffold(
            backgroundColor: t.paper,
            body: SafeArea(
              child: Center(
                child: BlError(
                  title: s.errorStartupTitle,
                  message: '$error',
                  reassurance: s.errorStartupBody,
                  // No retry: whatever stopped the database opening will stop
                  // it again a second later, and a button that does nothing is
                  // worse than no button. The honest action is the one below.
                  retryLabel: s.errorStartupRecover,
                  onRetry: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.errorStartupNotReady)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The printers this build can talk to.
///
/// Named here rather than inside the bootstrap because this is the one place
/// that knows which platform the app is running on. `pk_bootstrap` stays
/// testable headless, and a test that does not name its transports gets none —
/// so nothing in a suite can accidentally open a real socket or reach for a
/// real radio.
///
/// Bluetooth is Android-only: the plugin is a method channel, and asking a
/// host test for a bonded device list would hang rather than fail.
List<PrinterTransport> _printerTransports() => [
  // The shop's own wi-fi. Needs INTERNET, which Android requires for ANY
  // socket including one to 192.168.x.x, and nothing more until targetSdk 37
  // brings ACCESS_LOCAL_NETWORK.
  const TcpPrinter(),
  if (!kIsWeb && Platform.isAndroid) const BluetoothPrinter(),
];
