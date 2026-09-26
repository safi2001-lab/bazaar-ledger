import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// The demand notice, from the drawer to the share sheet.
///
/// The bounce told the shop the date by which the 489-F notice had to go,
/// and then left it to find a munshi to type it. Every word of it is already
/// in the books, so the notice is drawn up from them and handed to whatever
/// the shop sends files with.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);

  testWidgets('a bounced cheque shares its demand notice as a PDF', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _bounce(app, no: '004512');

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');
    expect(find.textContaining('wakeel ko zaroor dikhayein'), findsOneWidget);
    await tester.tap(find.text('Notice PDF share karein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    final file = File(_sheet.paths.single);
    expect(file.path, endsWith('notice-004512.pdf'));
    final text = String.fromCharCodes(file.readAsBytesSync());
    expect(text.substring(0, 5), '%PDF-');
    expect(text, contains('Demand notice, cheque 004512'));
  });
}

/// Rashid Traders owes Rs 45,000, pays by a cheque due today, and the bank
/// returns it.
Future<void> _bounce(Harness app, {required String no}) async {
  final rashid = await app.seedParty(name: 'Rashid Traders', owedRupees: 45000);
  final firm = await app.services.queries.currentFirm();
  final accounts = await app.services.queries.paymentAccounts(firm!.id);
  final today = BusinessDate.now(app.services.clock);
  final cheque = await app.services.recordReceipt(
    app.services.actorNow(),
    ReceiptDraft(
      partyId: rashid,
      amount: const Money.rupees(45000),
      mode: 'cheque',
      paymentAccountId: accounts.firstWhere((a) => a.modeLabel == 'cheque').id,
      chequeNo: no,
      chequeBank: 'Meezan',
      chequeDateUtcMillis: chequeDueUtcMillis(today),
    ),
  );
  await app.services.cheques.bounce(
    app.services.actorNow(),
    cheque.paymentId,
    reason: 'Funds insufficient',
  );
}

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
