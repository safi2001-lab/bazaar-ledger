import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/text_size.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/audit_screen.dart';
import '../backup/backup_screen.dart';
import '../control/control_settings_screen.dart'; // M68
import '../firms/firms_screen.dart';
import '../import/import_screen.dart';
import '../items/shelf_rule.dart';
import '../loyalty/loyalty_settings_screen.dart'; // M66
import '../printing/printer_setup_screen.dart';
import '../recycle/recycle_screen.dart';
import '../scale/scale_screen.dart';
import '../staff/staff_rules_screen.dart'; // M65
import '../subscription/plans_screen.dart';
import '../subscription/play_billing.dart';
import '../sync/sync_screen.dart';
import '../tax/tax_screen.dart';
import '../users/users_screen.dart';
import 'bill_design_screen.dart';
import 'books_lock_screen.dart';
import 'payment_details_screen.dart';
import 'receipt_offer_screen.dart'; // M70
import 'reminder_templates_screen.dart';
import 'schemes_screen.dart'; // M43
import 'shop_details_screen.dart';

/// Language, theme, shop, how customers can pay, and whether the books are
/// sound.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
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

            // How big the words are, on top of the phone's own setting (M56).
            // Applied the moment it is tapped, so the shopkeeper sees the
            // answer on this very screen rather than being told about it.
            BlSectionHeader(s.settingsTextSize),
            const SizedBox(height: BlTokens.space2),
            SegmentedButton<BlTextSize>(
              segments: [
                ButtonSegment(
                  value: BlTextSize.normal,
                  label: Text(s.settingsTextSizeNormal),
                ),
                ButtonSegment(
                  value: BlTextSize.large,
                  label: Text(s.settingsTextSizeLarge),
                ),
                ButtonSegment(
                  value: BlTextSize.larger,
                  label: Text(s.settingsTextSizeLarger),
                ),
              ],
              selected: {prefs.textSize},
              onSelectionChanged: (v) => notifier.setTextSize(v.first),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              s.settingsTextSizeHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space5),

            BlSectionHeader(s.settingsShop),
            const SizedBox(height: BlTokens.space2),
            // The plan this phone is on, and the way to another (M21).
            _Row(
              icon: Icons.workspace_premium_outlined,
              label: s.planCurrent(planName(ref.watch(planProvider))),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
              ),
            ),
            if (services.can(Permission.manageUsers))
              _Row(
                icon: Icons.store_mall_directory_outlined,
                label: s.firmsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FirmsScreen()),
                ),
              ),
            if (services.can(Permission.audit))
              _Row(
                icon: Icons.history,
                label: s.auditTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AuditScreen()),
                ),
              ),
            if (services.can(Permission.manageUsers))
              _Row(
                icon: Icons.badge_outlined,
                label: s.usersTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const UsersScreen()),
                ),
              ),
            // Beside staff and PINs, because Data Lock asks for those PINs
            // (M42). The owner's alone: nobody else may close the books.
            if (services.audit.isOwner)
              _Row(
                icon: Icons.lock_clock_outlined,
                label: s.booksLockTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BooksLockScreen(),
                  ),
                ),
              ),
            // M68: credit rules, days that close by themselves, the random
            // stock check and cashier mode. Beside the closing of the books,
            // whose date the second of them moves.
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.rule_outlined,
                label: s.controlSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ControlSettingsScreen(),
                  ),
                ),
              ),
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.storefront_outlined,
                label: s.settingsShop,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ShopDetailsScreen(),
                  ),
                ),
              ),
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.account_balance_outlined,
                label: s.settingsPayment,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PaymentDetailsScreen(),
                  ),
                ),
              ),
            // Beside how customers pay, because the payment QR is set in
            // both and an owner looking for one finds the other (M51).
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.palette_outlined,
                label: s.settingsBillDesign,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BillDesignScreen(),
                  ),
                ),
              ),
            // The words reminders go out in, per language (M39). Beside the
            // payment details, which fill their {wallet}.
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.campaign_outlined,
                label: s.settingsReminders,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReminderTemplatesScreen(),
                  ),
                ),
              ),
            // M70: the receipt offered when money moves, beside the other
            // message the shop sends its customers.
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.mark_chat_read_outlined,
                label: s.settingsReceiptOffer,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReceiptOfferScreen(),
                  ),
                ),
              ),
            // M53: what the counter does when an item would go below
            // nothing. Everyone may read it; only the owner changes it.
            _Row(
              icon: Icons.inventory_outlined,
              label: s.shelfRuleTitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ShelfRuleScreen(),
                ),
              ),
            ),
            // M65: the staff book's rules, the owner's.
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.badge_outlined,
                label: s.staffRulesTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StaffRulesScreen(),
                  ),
                ),
              ),
            // M43: bonus, quantity slabs and the big-bill discount. Everyone
            // may read them; only the owner changes them.
            _Row(
              icon: Icons.local_offer_outlined,
              label: s.schemesTitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SchemesScreen()),
              ),
            ),
            // M66: loyalty points, and the profit at the counter. Everyone
            // may read the rule; only the owner changes it.
            _Row(
              icon: Icons.stars_outlined,
              label: s.settingsLoyalty,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LoyaltySettingsScreen(),
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
            // Beside the health check, because both answer "is my hisaab
            // safe", and a shopkeeper looking for one is looking for the
            // other.
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.account_balance_wallet_outlined,
                label: s.taxTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TaxScreen()),
                ),
              ),
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.table_view_outlined,
                label: s.importTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
                ),
              ),
            if (services.can(Permission.settings))
              _Row(
                icon: Icons.scale_outlined,
                label: s.scaleTitle,
                onTap: () => openWithPlan(
                  context,
                  ref,
                  PlanFeature.scaleLabels,
                  () => const ScaleScreen(),
                ),
              ),
            _Row(
              icon: Icons.wifi_tethering,
              label: s.syncTitle,
              onTap: () => openWithPlan(
                context,
                ref,
                PlanFeature.lanSync,
                () => const SyncScreen(),
              ),
            ),
            if (services.can(Permission.backups))
              _Row(
                icon: Icons.backup_outlined,
                label: s.backupTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                ),
              ),
            _Row(
              icon: Icons.restore_from_trash_outlined,
              label: s.recycleTitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RecycleScreen()),
              ),
            ),
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
    final encrypted = ref.watch(appServicesProvider).booksEncrypted;
    final journal = ref.watch(crashJournalProvider);

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
          final crashes = journal?.entries() ?? const <CrashEntry>[];
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
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  Icon(
                    encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 16,
                    color: t.inkMuted,
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(
                      encrypted
                          ? s.settingsBooksEncrypted
                          : s.settingsBooksPlain,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                  ),
                ],
              ),
              if (crashes.isNotEmpty) ...[
                const SizedBox(height: BlTokens.space2),
                Row(
                  children: [
                    Icon(Icons.bug_report_outlined, size: 16, color: t.warning),
                    const SizedBox(width: BlTokens.space2),
                    Expanded(
                      child: Text(
                        s.settingsCrashes('${crashes.length}'),
                        style: TextStyle(fontSize: 12, color: t.ink),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        journal?.clear();
                        ref.invalidate(dataHealthProvider);
                      },
                      child: Text(s.settingsCrashesClear),
                    ),
                  ],
                ),
                Text(
                  crashes.last.error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
