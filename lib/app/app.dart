import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../features/home/home_screen.dart';
import '../features/setup/setup_screen.dart';
import '../l10n/app_strings.dart';
import 'localisation.dart';
import 'providers.dart';

class BazaarLedgerApp extends ConsumerWidget {
  const BazaarLedgerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);

    return MaterialApp(
      title: 'Bazaar Ledger',
      debugShowCheckedModeBanner: false,
      theme: blTheme(dark: false),
      darkTheme: blTheme(dark: true),
      themeMode: prefs.themeMode,
      locale: prefs.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...chromeDelegates,
      ],
      builder: (context, child) {
        // Text scales to 200% without clipping, but a shopkeeper who has set
        // their phone to 300% would lose the money column entirely, so it is
        // clamped rather than left unbounded.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2.0,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _Root(),
    );
  }
}

/// Decides between the wizard and the counter.
///
/// There is no login here and there never will be: no account, no server, no
/// password to forget. "Is there a firm row" is the whole of the session
/// state.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firm = ref.watch(firmProvider);
    final t = context.bl;

    return firm.when(
      loading: () => Scaffold(
        backgroundColor: t.paper,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bazaar Ledger',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: BlTokens.space4),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
              ),
            ],
          ),
        ),
      ),
      // A failure here means the database would not open. Never a bare
      // exception on a logo screen: the shopkeeper is told what to do.
      error: (error, stack) => Scaffold(
        backgroundColor: t.paper,
        body: SafeArea(
          child: _StartupFailure(error: error, onRetry: () => ref.invalidate(firmProvider)),
        ),
      ),
      data: (profile) =>
          profile == null ? const SetupScreen() : const HomeScreen(),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BlTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_outlined, size: 44, color: t.danger),
            const SizedBox(height: BlTokens.space4),
            Text(
              'The books could not be opened',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              'Nothing has been lost. Close the app and open it again; if this '
              'keeps happening, restore from your last backup.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.inkFaint),
            ),
            const SizedBox(height: BlTokens.space5),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
