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
import 'features/backup/backup_providers.dart';
import 'features/backup/restore_screen.dart';
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

  // Errors nothing else caught are written down on the phone, since there is
  // nowhere else to send them, and shown in Data Health.
  try {
    final journal = CrashJournal(
      File('${(await AppServices.booksDirectory()).path}/crashes.jsonl'),
    );
    _crashJournal = journal;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      journal.record(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      journal.record(error, stack);
      return true;
    };
  } on Object {
    // No journal is no reason not to open the shop.
  }

  runApp(_Boot(first: await _open()));
}

CrashJournal? _crashJournal;

/// What opening the books produced: the services, or why there are none.
final class _Opened {
  const _Opened.ready(this.prefs, AppServices this.services)
    : error = null,
      stack = null;

  const _Opened.failed(this.prefs, Object this.error, StackTrace this.stack)
    : services = null;

  final AppPreferences prefs;
  final AppServices? services;
  final Object? error;
  final StackTrace? stack;
}

Future<_Opened> _open() async {
  // Preferences first, and they cannot fail: a corrupt file returns defaults.
  // So whatever happens next is at least readable in the right language.
  final prefs = await AppPreferences.load();
  try {
    return _Opened.ready(
      prefs,
      await AppServices.open(transports: _printerTransports()),
    );
  } on Object catch (error, stack) {
    // The database would not open: a corrupt file, a full disk, a schema from
    // a newer build. Before this, that was a black screen — the app died
    // before the first frame with nothing on it.
    //
    // A shopkeeper who opens the app to a crash has lost their business day.
    // One who is told what happened, in their own language, still has a phone
    // they can hand to someone who can help, and a restore button.
    return _Opened.failed(prefs, error, stack);
  }
}

/// Holds the open books, and can close and reopen them.
///
/// A restore is staged beside the live file and swapped in by
/// `AppServices.open`, before anything can be holding the database. Asking
/// the shopkeeper to kill the app and start it again would work, and on an
/// Android Go handset "close the app" means something different on every
/// ROM. So the app does it: closes the books, reopens them, and rebuilds
/// everything above the counter from scratch — a new ProviderScope, so no
/// provider is left holding a row from the books that were replaced.
class _Boot extends StatefulWidget {
  const _Boot({required this.first});

  final _Opened first;

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late _Opened _opened = widget.first;
  var _generation = 0;
  var _reopening = false;

  Future<void> _reopen() async {
    setState(() => _reopening = true);
    await _opened.services?.close();
    final next = await _open();
    if (!mounted) return;
    setState(() {
      _opened = next;
      _generation++;
      _reopening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    if (_reopening) return _Reopening(prefs: opened.prefs);

    final services = opened.services;
    if (services == null) {
      return _StartupFailureApp(
        key: ValueKey(_generation),
        prefs: opened.prefs,
        error: opened.error!,
        stack: opened.stack!,
        onRestored: _reopen,
      );
    }
    return ProviderScope(
      key: ValueKey(_generation),
      overrides: [
        appServicesProvider.overrideWithValue(services),
        initialPreferencesProvider.overrideWithValue(opened.prefs),
        restartAppProvider.overrideWithValue(_reopen),
        crashJournalProvider.overrideWithValue(_crashJournal),
      ],
      child: const BazaarLedgerApp(),
    );
  }
}

/// The few hundred milliseconds between closing the books and reopening
/// them. Nothing may read the database here, so nothing is drawn that could.
class _Reopening extends StatelessWidget {
  const _Reopening({required this.prefs});

  final AppPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: blTheme(dark: false),
      darkTheme: blTheme(dark: true),
      themeMode: prefs.themeMode,
      locale: prefs.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [AppStrings.delegate, ...chromeDelegates],
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.bl.paper,
          body: Center(child: Text(AppStrings.of(context).restoreRestarting)),
        ),
      ),
    );
  }
}

/// The app when there is no database to run it against.
///
/// Deliberately its own MaterialApp with no ProviderScope: everything above
/// this point failed, so nothing below it may depend on anything that could
/// also fail. It needs the localisations and the tokens, and nothing else.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({
    super.key,
    required this.prefs,
    required this.error,
    required this.stack,
    required this.onRestored,
  });

  final AppPreferences prefs;
  final Object error;
  final StackTrace stack;
  final Future<void> Function() onRestored;

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
                  // worse than no button. The honest action is a restore,
                  // which replaces the file that would not open and keeps it
                  // aside rather than deleting it.
                  retryLabel: s.errorStartupRecover,
                  onRetry: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RestoreScreen(
                        pickFile: pickBackupFile,
                        databasePath: AppServices.defaultDatabasePath,
                        onRestored: onRestored,
                      ),
                    ),
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
  if (!kIsWeb && Platform.isAndroid) ...[
    // The battery printer a delivery man carries.
    const BluetoothPrinter(),
    // The one already cabled to the counter, which is the shape most
    // Pakistani shop counters actually have. Needs no permission at all: USB
    // access is granted per device by the system at the moment of use, so it
    // adds nothing to the Play listing.
    const UsbPrinter(),
  ],
];
