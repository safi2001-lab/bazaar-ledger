import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/staff/employee_screen.dart';
import 'package:bazaar_ledger/features/staff/register_screen.dart';
import 'package:bazaar_ledger/features/staff/salary_screen.dart';
import 'package:bazaar_ledger/features/staff/staff_book_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The staff book through the screens (M65): the day's register marked a
/// tap a man; a month's wages worked out from it, an advance taken back
/// off them, the slip shared as a PDF and then cancelled, the books put
/// back; and every screen of it at 200% on a small phone.
void main() {
  final shareSheet = _FakeShareSheet();
  SharePlatform.instance = shareSheet;
  setUp(shareSheet.paths.clear);

  Future<Money> balance(Harness app, String key) async {
    final firm = await app.services.queries.currentFirm();
    return (await app.services.queries.chartOfAccounts(
      firm!.id,
    )).firstWhere((a) => a.systemKey == key).onItsSide;
  }

  testWidgets('the day register is marked a tap a man, and everyone else '
      'present with one more', (tester) async {
    final app = await _shop(tester);
    final bilal = await _hire(app, 'Bilal');
    final saleem = await _hire(app, 'Saleem');
    await _refresh(tester);

    await tapText(tester, 'Staff ki kitaab');
    expect(find.byType(StaffBookScreen), findsOneWidget);
    await tapButton(tester, 'Aaj ki hazri');
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Abhi hazri nahi lagi'), findsNWidgets(2));

    await tester.tap(find.byKey(ValueKey('mark-$bilal-absent')));
    await tester.pumpAndSettle();
    expect(find.text('Ghair haazir, Malik Sahib ne lagayi'), findsOneWidget);
    await tapButton(tester, 'Baqi sab haazir');
    expect(find.text('Haazir, Malik Sahib ne lagayi'), findsOneWidget);

    final marks = await app.rowsOf(
      'SELECT employee_id, day_local, mark FROM attendance '
      'ORDER BY mark',
    );
    expect(marks, [
      {'employee_id': bilal, 'day_local': '2026-10-03', 'mark': 'absent'},
      {'employee_id': saleem, 'day_local': '2026-10-03', 'mark': 'present'},
    ]);
  });

  testWidgets('a month of wages is worked out from the register, the '
      'advance comes off it, the slip goes out as a PDF, and a cancelled '
      'slip puts the books back', (tester) async {
    final app = await _shop(tester);
    final bilal = await _hire(app, 'Bilal');
    final book = app.services.staffBook;
    await book.mark(const BusinessDate('2026-09-03'), {
      bilal: AttendanceMark.absent,
    });
    await book.mark(const BusinessDate('2026-09-04'), {
      bilal: AttendanceMark.absent,
    });
    final firm = await app.services.queries.currentFirm();
    final cash = (await app.services.queries.paymentAccounts(
      firm!.id,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    await book.giveAdvance(
      AdvanceDraft(
        employeeId: bilal,
        amount: const Money.rupees(2000),
        paymentAccountId: cash,
        givenOn: const BusinessDate('2026-09-12'),
      ),
    );
    await _refresh(tester);

    await tapText(tester, 'Staff ki kitaab');
    expect(find.text('Peshgi Rs 2,000.00'), findsOneWidget);
    await tapText(tester, 'Bilal');
    expect(find.byType(EmployeeScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Pichla mahina'));
    await tester.pumpAndSettle();
    expect(find.text('Sep 2026'), findsOneWidget);
    await tapButton(tester, 'Sep 2026 ki tankhwah dein');
    expect(find.byType(SalaryScreen), findsOneWidget);
    // 30,000 under the 30-day rule, two days away: 28 of 30.
    expect(find.text('28 din ki tankhwah'), findsOneWidget);
    expect(find.text('28,000.00'), findsWidgets);

    await typeInto(tester, 'Kis cheez ka (jaise Eid bonus)', 'Eid bonus');
    await typeInto(tester, 'Raqam (Rs)', '1000');
    await tapButton(tester, 'Shamil karein');
    // The bonus is on the month: 28,000 and 1,000.
    expect(find.text('29,000.00'), findsOneWidget);
    // All of the advance comes back, the month bearing it.
    expect(find.widgetWithText(TextFormField, '2000.00'), findsOneWidget);
    expect(find.text('27,000.00'), findsOneWidget);
    await _scrollTo(tester, 'Tankhwah dein');
    await tapButton(tester, 'Tankhwah dein');

    expect(find.text('Haath mein'), findsOneWidget);
    expect(find.text('27,000.00'), findsOneWidget);
    expect(await balance(app, 'salaries'), const Money.rupees(29000));
    expect(await balance(app, 'staff_advances'), Money.zero);
    expect(await balance(app, 'cash_in_hand'), -const Money.rupees(29000));

    await tester.tap(find.byTooltip('Slip (PDF)'));
    await settleReal(tester, done: () => shareSheet.paths.isNotEmpty);
    expect(shareSheet.paths, hasLength(1));
    final pdf = (await tester.runAsync(
      () => File(shareSheet.paths.single).readAsBytes(),
    ))!;
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    await _scrollTo(tester, 'Yeh slip cancel karein');
    await tapButton(tester, 'Yeh slip cancel karein');
    await tester.enterText(find.byType(TextField).last, 'Galat mahina');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel karein'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, 'Cancel: Galat mahina', up: true);
    expect(find.text('Cancel: Galat mahina'), findsOneWidget);
    expect(await balance(app, 'salaries'), Money.zero);
    expect(await balance(app, 'staff_advances'), const Money.rupees(2000));
    expect(await balance(app, 'cash_in_hand'), -const Money.rupees(2000));
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the staff book, the register, a man page and his wages fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await _shop(tester);
      final bilal = await _hire(app, 'Muhammad Bilal Hussain');
      await app.services.staffBook.mark(const BusinessDate('2026-09-03'), {
        bilal: AttendanceMark.halfDay,
      });
      await _refresh(tester);

      await tapText(tester, 'Staff ki kitaab');
      _expectNothingPaintsOffScreen(tester);
      await tapButton(tester, 'Aaj ki hazri');
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText(tester, 'Muhammad Bilal Hussain');
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.byTooltip('Pichla mahina'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Sep 2026 ki tankhwah dein');
      expect(find.byType(SalaryScreen), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// Brings [text] into view in a long list, which builds only what shows.
Future<void> _scrollTo(
  WidgetTester tester,
  String text, {
  bool up = false,
}) async {
  if (find.text(text).evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    find.text(text),
    up ? -200 : 200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<Harness> _shop(WidgetTester tester) => Harness.startWithShop(
  tester,
  clock: FixedClock(DateTime.utc(2026, 10, 3, 5)),
);

Future<String> _hire(Harness app, String name) => app.services.staffBook.add(
  EmployeeDraft(
    name: name,
    basis: PayBasis.monthly,
    rate: const Money.rupees(30000),
    joinedOn: const BusinessDate('2026-08-01'),
  ),
);

Future<void> _refresh(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).first),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// 360x800 dp with the font at 200%, as `large_text_test.dart` lays the
/// app out.
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

