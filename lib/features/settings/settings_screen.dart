import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printer_setup_screen.dart';
import 'payment_details_screen.dart';
import 'shop_details_screen.dart';

/// Language, theme, shop, how customers can pay, and whether the books are
/// sound.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final prefs = ref.watch(preferencesProvider);
    final notifier = ref.read(preferencesProvider.notifier);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlSectionHeader(s.settingsLanguage),
            const SizedBox(height: BlTokens.space2),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'ur',
                  label: Text(s.settingsLanguageRomanUrdu),
                ),
                ButtonSegment(
                  value: 'en',
                  label: Text(s.settingsLanguageEnglish),
                ),
              ],
              selected: {prefs.locale.languageCode},
              onSelectionChanged: (v) => notifier.setLocale(Locale(v.first)),
            ),
            const SizedBox(height: BlTokens.space5),

            BlSectionHeader(s.settingsTheme),
            const SizedBox(height: BlTokens.space2),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(s.settingsThemeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(s.settingsThemeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(s.settingsThemeDark),
                ),
              ],
              selected: {prefs.themeMode},
              onSelectionChanged: (v) => notifier.setThemeMode(v.first),
            ),
            const SizedBox(height: BlTokens.space5),

            BlSectionHeader(s.settingsShop),
            const SizedBox(height: BlTokens.space2),
            _Row(
              icon: Icons.storefront_outlined,
              label: s.settingsShop,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ShopDetailsScreen(),
                ),
              ),
            ),
            _Row(
              icon: Icons.account_balance_outlined,
              label: s.settingsPayment,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PaymentDetailsScreen(),
                ),
              ),
            ),
            _Row(
              icon: Icons.print_outlined,
              label: s.settingsPrinter,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrinterSetupScreen(),
                ),
              ),
            ),
            const SizedBox(height: BlTokens.space5),

            BlSectionHeader(s.settingsDataHealth),
            const SizedBox(height: BlTokens.space2),
            const _DataHealthCard(),
            const SizedBox(height: BlTokens.space5),

            BlSectionHeader(s.settingsAbout),
            const SizedBox(height: BlTokens.space2),
            BlCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: t.inkMuted),
                  const SizedBox(width: BlTokens.space3),
                  Expanded(
                    child: Text(
                      s.settingsAboutBody,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space8),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.inkMuted),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Whether the books are sound, in words a shopkeeper can act on.
///
/// Not a diagnostic panel. Silent accounting wrongness is invisible for six
/// months and then nothing balances, so the integrity check that runs on every
/// open is also something the owner can run themselves and see the result of.
class _DataHealthCard extends ConsumerWidget {
  const _DataHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final health = ref.watch(dataHealthProvider);

    return BlCard(
      child: health.when(
        loading: () => const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
        error: (error, _) => BlError(
          title: s.commonSomethingWentWrong,
          message: '$error',
          retryLabel: s.settingsDataHealthCheck,
          onRetry: () => ref.invalidate(dataHealthProvider),
        ),
        data: (report) {
          final problems = report.findings;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    problems.isEmpty
                        ? Icons.verified_outlined
                        : Icons.report_problem_outlined,
                    size: 20,
                    color: problems.isEmpty ? t.money : t.danger,
                  ),
                  const SizedBox(width: BlTokens.space3),
                  Expanded(
                    child: Text(
                      problems.isEmpty
                          ? s.settingsDataHealthOk
                          : s.settingsDataHealthProblem(problems.length),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: problems.isEmpty ? t.ink : t.danger,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(dataHealthProvider),
                    child: Text(s.settingsDataHealthCheck),
                  ),
                ],
              ),
              for (final problem in problems) ...[
                const SizedBox(height: BlTokens.space2),
                Text(problem, style: TextStyle(fontSize: 12, color: t.danger)),
              ],
            ],
          );
        },
      ),
    );
  }
}
