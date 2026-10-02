import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Loans the shop has taken, from the screen (M48): taken, paid back in
/// part, the statement shared, a wrong repayment cancelled.
void main() {
  final shareSheet = _FakeShareSheet();
  SharePlatform.instance = shareSheet;
  setUp(shareSheet.paths.clear);

  Future<void> openLoans(WidgetTester tester) async {
    await tapText(tester, 'Hisaab kitaab');
    await tester.tap(find.byTooltip('Qarzay'));
    await tester.pumpAndSettle();
  }

  Future<String> bankId(Harness app) async {
    final firm = await app.services.queries.currentFirm();
    return (await app.services.queries.paymentAccounts(
      firm!.id,
    )).firstWhere((a) => a.modeLabel == 'bank_transfer').id;
  }

  Future<Money> balanceOf(
    Harness app,
    bool Function(ChartAccount) which,
  ) async {
    final firm = await app.services.queries.currentFirm();
    return (await app.services.queries.chartOfAccounts(
      firm!.id,
    )).firstWhere(which).onItsSide;
  }

  testWidgets('a loan is taken, paid back in part, and its statement goes '
      'out as a PDF and a CSV', (tester) async {
    final app = await Harness.startWithShop(tester);
    await openLoans(tester);
    expect(find.text('Koi qarza nahi'), findsOneWidget);

    await tester.tap(find.text('Naya qarza'));
    await tester.pumpAndSettle();
    await typeInto(
      tester,
      'Kis se liya (bank, committee, rishtedar)',
      'Meezan Bank',
    );
    await typeInto(tester, 'Qarze ki raqam', '500000');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bank'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Sood (markup), % saalana (marzi se)', '18');
    await typeInto(tester, 'Mahana qist (marzi se)', '25000');
    await typeInto(tester, 'Processing fee (marzi se)', '5000');
    expect(find.text('Fee ke baad haath mein: 4,95,000.00'), findsOneWidget);
    await tapButton(tester, 'Qarza save karein');
    // The "saved" note sits over the bottom of the next screen until it
    // times out, as it would on a phone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Loan from Meezan Bank'), findsOneWidget);
    expect(
      await balanceOf(app, (a) => a.systemKey == 'bank'),
      const Money.rupees(495000),
    );
    expect(
      await balanceOf(app, (a) => a.name == 'Loan from Meezan Bank'),
      const Money.rupees(500000),
    );

    await tapText(tester, 'Loan from Meezan Bank');
    await tester.tap(find.text('Qist dein'));
    await tester.pumpAndSettle();
    // The instalment from the loan's terms is filled in.
    expect(find.widgetWithText(TextFormField, '25000.00'), findsOneWidget);
    await typeInto(tester, 'Is mein sood (markup)', '7500');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bank'));
    await tester.pumpAndSettle();
    expect(find.text('17,500.00'), findsOneWidget);
    await tapButton(tester, 'Qist save karein');

    expect(find.text('Qarza mila'), findsOneWidget);
    expect(find.text('Qist di'), findsOneWidget);
    expect(
      await balanceOf(app, (a) => a.name == 'Loan from Meezan Bank'),
      const Money.rupees(482500),
    );
    final firm = await app.services.queries.currentFirm();
    final today = BusinessDate.now(app.services.clock);
    final pl = await app.services.reports.run(
      ReportKind.profitAndLoss,
      firmId: firm!.id,
      period: ReportPeriod.fiscalYearOf(today),
      today: today,
    );
    Object? row(String name) =>
        pl.rows.where((r) => r.cells.first == name).single.cells[1];
    expect(row('Loan Interest'), const Money.rupees(7500));
    expect(row('Loan Processing Fee'), const Money.rupees(5000));

    await tester.tap(find.byTooltip('Statement (PDF)'));
    await settleReal(tester, done: () => shareSheet.paths.isNotEmpty);
    expect(shareSheet.paths, hasLength(1));
    final pdf = (await tester.runAsync(
      () => File(shareSheet.paths.single).readAsBytes(),
    ))!;
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    shareSheet.paths.clear();
    await tester.tap(find.byTooltip('Statement (Excel, CSV)'));
    await settleReal(tester, done: () => shareSheet.paths.isNotEmpty);
    final csv = (await tester.runAsync(
      () => File(shareSheet.paths.single).readAsString(),
    ))!;
    expect(csv, contains('Principal paid'));
    expect(csv, contains('17500.00'));
    expect(csv, contains('482500.00'));
  });

  testWidgets('a repayment entered wrong is cancelled from the statement, '
      'with a reason', (tester) async {
    final app = await Harness.startWithShop(tester);
    final bank = await bankId(app);
    final today = BusinessDate.now(app.services.clock);
    final loan = await app.services.loans.take(
      LoanDraft(
        lender: 'Bhai Jan',
        amount: const Money.rupees(50000),
        intoPaymentAccountId: bank,
        takenOn: today,
      ),
    );
    await app.services.loans.repay(
      RepaymentDraft(
        loanId: loan,
        paid: const Money.rupees(5000),
        fromPaymentAccountId: bank,
        paidOn: today,
      ),
    );

    await openLoans(tester);
    await tapText(tester, 'Loan from Bhai Jan');
    final cancel = find.byTooltip('Ghalat hai, cancel karein').last;
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await typeInto(
      tester,
      'Kyun cancel kar rahe hain (zaroori)',
      'Paid twice by mistake',
    );
    await tester.tap(
      find.widgetWithText(TextButton, 'Ghalat hai, cancel karein'),
    );
    await settleReal(tester, until: find.textContaining('Cancel ho gaya ('));
    expect(find.textContaining('Cancel ho gaya ('), findsOneWidget);

    // The repayment is marked, and its cancellation is a line of its own.
    await tester.scrollUntilVisible(
      find.text('Cancel kiya'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cancel kiya'), findsOneWidget);
    expect(find.text('Cancel ho gaya'), findsOneWidget);
    expect(
      await balanceOf(app, (a) => a.id == loan),
      const Money.rupees(50000),
    );
    expect(
      await app.scalar<int>(
        'SELECT COUNT(*) FROM journal_entries '
        'WHERE reverses_entry_id IS NOT NULL',
      ),
      1,
    );
  });

  testWidgets('more off the loan than is owed is refused on the screen', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final today = BusinessDate.now(app.services.clock);
    await app.services.loans.take(
      LoanDraft(
        lender: 'Rehman Traders',
        amount: const Money.rupees(50000),
        intoPaymentAccountId: await bankId(app),
        takenOn: today,
      ),
    );

    await openLoans(tester);
    await tapText(tester, 'Loan from Rehman Traders');
    await tester.tap(find.text('Qist dein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kitne diye', '60000');
    await tapButton(tester, 'Qist save karein');

    expect(find.textContaining('still owed on it'), findsOneWidget);
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'manual'",
      ),
      1,
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('the loan screens fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final bank = await bankId(app);
      final today = BusinessDate.now(app.services.clock);
      final loan = await app.services.loans.take(
        LoanDraft(
          lender: 'Habib Metropolitan Bank',
          amount: const Money.rupees(2500000),
          fee: const Money.rupees(12500),
          intoPaymentAccountId: bank,
          takenOn: today,
          rateBp: 2150,
          termMonths: 36,
          instalment: const Money.rupees(95000),
          notes: 'Running finance against the Eid stock',
        ),
      );
      await app.services.loans.repay(
        RepaymentDraft(
          loanId: loan,
          paid: const Money.rupees(95000),
          interest: const Money.rupees(44178),
          charges: const Money.rupees(1500),
          fromPaymentAccountId: bank,
          paidOn: today,
        ),
      );

      await openLoans(tester);
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Loan from Habib Metropolitan Bank');
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Qist dein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Naya qarza'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// 360x800 dp — an Infinix Smart at its 720x1600 native resolution — with
/// the font at 200%, as `large_text_test.dart` lays the app out.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Every rendered piece of text still inside the screen it was drawn on.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}

/// A real font, because the test font's square glyphs make every width
/// assertion pass.
Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
