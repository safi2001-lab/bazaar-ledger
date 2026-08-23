import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Where a customer can send money, printed on the bill as plain text.
///
/// This app never takes a payment, never routes one, never settles one and
/// never holds a rupee. What it does is print the shopkeeper's own Raast alias
/// and IBAN on the receipt, exactly as it prints their phone number, so a
/// customer can push a payment from their own banking app.
///
/// It also never synthesizes a payment QR. Under §8.1(a) of the SBP
/// Interoperable QR Standard the scheme identifier in a QR payload is issued
/// by the State Bank only to authorized PSO/PSPs, and breaching an SBP
/// instruction is an offence under s.56 of the PS&EFT Act 2007 — up to three
/// years or PKR 3 million. A bank-issued QR the merchant already has can be
/// imported and reprinted as an image, which §4.2 of the same standard
/// expressly contemplates; one we generated would be a criminal exposure
/// shipped to every user.
class PaymentDetailsScreen extends ConsumerStatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  ConsumerState<PaymentDetailsScreen> createState() =>
      _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends ConsumerState<PaymentDetailsScreen> {
  final _raast = TextEditingController();
  final _bankName = TextEditingController();
  final _accountTitle = TextEditingController();
  final _iban = TextEditingController();

  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _raast.dispose();
    _bankName.dispose();
    _accountTitle.dispose();
    _iban.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // First statement, before the validate and before any await. A disabled
    // button only disables on the next build, so two taps in one frame both
    // reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    // Held across the await; see shop_details_screen for why.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).updateFirm({
        'raast_alias': _text(_raast),
        'bank_name': _text(_bankName),
        'bank_account_title': _text(_accountTitle),
        'bank_iban': _text(_iban)?.toUpperCase().replaceAll(' ', ''),
      });
      container.invalidate(firmProvider);
      container.bumpRefresh();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.actionDone)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsPayment)),
      body: SafeArea(
        child: firm.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(firmProvider),
            ),
          ),
          data: (profile) {
            if (profile == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            if (!_loaded) {
              _loaded = true;
              _raast.text = profile.raastAlias ?? '';
              _bankName.text = profile.bankName ?? '';
              _accountTitle.text = profile.bankAccountTitle ?? '';
              _iban.text = profile.bankIban ?? '';
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(BlTokens.space4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Note(icon: Icons.info_outline, text: s.settingsPaymentNote),
                      const SizedBox(height: BlTokens.space5),
                      BlField(
                        controller: _raast,
                        label: s.settingsRaastAlias,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: BlTokens.space4),
                      BlField(
                        controller: _bankName,
                        label: s.settingsBankName,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: BlTokens.space4),
                      BlField(
                        controller: _accountTitle,
                        label: s.settingsAccountTitle,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: BlTokens.space4),
                      BlField(
                        controller: _iban,
                        label: s.settingsIban,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_busy) _save();
                        },
                      ),
                      const SizedBox(height: BlTokens.space5),
                      _Note(icon: Icons.qr_code_2, text: s.settingsQrNote),
                      if (_failure != null) ...[
                        const SizedBox(height: BlTokens.space4),
                        Text(
                          _failure!,
                          style: TextStyle(fontSize: 13, color: t.danger),
                        ),
                      ],
                      const SizedBox(height: BlTokens.space6),
                      BlButton(
                        label: s.actionSave,
                        icon: Icons.check,
                        big: true,
                        busy: _busy,
                        onPressed: _busy ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Container(
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        border: Border.all(color: t.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: t.inkMuted),
          const SizedBox(width: BlTokens.space3),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.45, color: t.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
