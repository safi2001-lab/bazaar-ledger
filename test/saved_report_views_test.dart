import 'dart:io';

import 'package:bazaar_ledger/features/parties/party_picker.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:bazaar_ledger/features/reports/saved_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Saved report views (M61), from the screen: a report narrowed, sorted and
/// set to this week is kept under a name, sits under My views on the hub
/// above the favourites, opens again in one tap exactly so, survives the
/// app being closed, and is renamed and deleted from its menu — kept on the
/// phone, never in the books.
void main() {
  testWidgets(
    'a report saved as a view opens again from My views with the same period, filters and sort',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('report_views');
      final app = await Harness.startWithShop(
        tester,
        overrides: [
          reportShelfDirectoryProvider.overrideWith((ref) async => dir),
        ],
      );
      final rashid = await app.seedParty(name: 'Rashid Traders');
      final small = await _sell(app, rupees: 1500, partyId: rashid);
      final big = await _sell(app, rupees: 9000, partyId: rashid);
      await _sell(app, rupees: 700, paid: 700);

      await tapText(tester, 'Report');
      expect(find.text('MERI VIEWS'), findsNothing, reason: 'none saved yet');
      await tapText(tester, 'Bikri report');

      // This week, Rashid's bills, the biggest first.
      await tapText(tester, 'Is hafta');
      await tester.tap(find.widgetWithText(ActionChip, 'Party'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PartyPicker),
          matching: find.text('Rashid Traders'),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Total se tarteeb'));
      await tester.pumpAndSettle();
      semantics.dispose();

      await tester.tap(find.byTooltip('Yeh view save karein'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sirf is phone par'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Rashid ki udhaar',
      );
      await tester.tap(find.text('Save karein'));
      await tester.pumpAndSettle();
      expect(
        find.text('Meri views mein save ho gaya: Rashid ki udhaar'),
        findsOneWidget,
      );

      final kept = SavedViewsFile.loadFrom(dir).single;
      expect(kept.kind, ReportKind.saleReport);
      expect(kept.preset, DatePreset.thisWeek);
      expect(kept.filters.partyId, rashid);
      expect(kept.filters.partyName, 'Rashid Traders');
      expect(kept.sortColumn, 'Total');
      expect(kept.sortAscending, isFalse);

      // Back on the hub, under My views, above the favourites.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('MERI VIEWS'), findsOneWidget);
      expect(find.text('Rashid ki udhaar'), findsOneWidget);
      expect(
        find.textContaining('Bikri report · Is hafta · Party: Rashid Traders'),
        findsOneWidget,
      );

      // One tap opens it just so: the week, the party, the sort.
      await tester.tap(find.text('Rashid ki udhaar'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Is hafta'))
            .selected,
        isTrue,
      );
      expect(find.text('Party: Rashid Traders'), findsOneWidget);
      expect(find.text('2 bills'), findsOneWidget, reason: 'Rashid\'s alone');
      double y(String text) => tester.getTopLeft(find.text(text).first).dy;
      expect(y(big.docNo), lessThan(y(small.docNo)), reason: 'largest first');
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a view is kept when the app is closed, renamed and deleted from its menu, and the report itself is untouched',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('report_views');
      SavedViewsFile.saveTo(dir, const [
        SavedReportView(
          id: 'v1',
          name: 'Peer ki roznamcha',
          kind: ReportKind.dayBook,
          preset: DatePreset.yesterday,
        ),
      ]);
      await Harness.startWithShop(
        tester,
        overrides: [
          reportShelfDirectoryProvider.overrideWith((ref) async => dir),
        ],
      );
      await tapText(tester, 'Report');
      expect(find.text('Peer ki roznamcha'), findsOneWidget);
      expect(find.textContaining('Roznamcha · Kal'), findsOneWidget);

      await tester.tap(find.byTooltip('View ke options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Naam badlein').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Kal ka hisaab',
      );
      await tester.tap(find.text('Save karein'));
      await tester.pumpAndSettle();
      expect(find.text('Kal ka hisaab'), findsOneWidget);
      expect(SavedViewsFile.loadFrom(dir).single.name, 'Kal ka hisaab');

      // Opened, it reads yesterday's day book under its own name.
      await tester.tap(find.text('Kal ka hisaab'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Kal'))
            .selected,
        isTrue,
      );
      expect(find.text('Roznamcha'), findsOneWidget, reason: 'under its name');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('View ke options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View hatayein').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Report aur hisaab bilkul'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'View hatayein'));
      await tester.pumpAndSettle();
      expect(find.text('MERI VIEWS'), findsNothing);
      expect(SavedViewsFile.loadFrom(dir), isEmpty);
      expect(
        find.text('Roznamcha'),
        findsWidgets,
        reason: 'still in its group',
      );
    },
  );

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('My views, a view opened, and the save dialog fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final dir = Directory.systemTemp.createTempSync('report_views');
      SavedViewsFile.saveTo(dir, [
        SavedReportView(
          id: 'v1',
          name: 'Peer ki udhaar list, Mandi wale gahak',
          kind: ReportKind.saleReport,
          preset: DatePreset.thisWeek,
          filters: const ReportFilters(
            partyId: 'p-1',
            partyName: 'Rashid Traders Shah Alam Market',
            paymentStatus: PaymentStatus.unpaid,
          ),
        ),
      ]);
      await Harness.startWithShop(
        tester,
        overrides: [
          reportShelfDirectoryProvider.overrideWith((ref) async => dir),
        ],
      );
      await tapText(tester, 'Report');
      await tester.scrollUntilVisible(find.text('MERI VIEWS'), 200);
      _expectNothingPaintsOffScreen(tester);

      await tester.tap(find.text('Peer ki udhaar list, Mandi wale gahak'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);

      await tester.tap(find.byTooltip('Yeh view save karein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}

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

/// Every rendered piece of text still inside the screen it was drawn on,
/// and nothing overflowed.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    // Text inside a sideways-scrolling table or chip row is meant to run
    // past the edge.
    final scrolls = find
        .ancestor(
          of: find.byWidget(element.widget),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        )
        .evaluate()
        .isNotEmpty;
    if (scrolls) continue;
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

/// The test font draws every glyph as a square of the font size, which
/// measures nothing; a real font says what a phone would show.
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

/// A bill of one item at [rupees], [paid] of it in cash.
Future<PostedSale> _sell(
  Harness app, {
  required int rupees,
  int paid = 0,
  String? partyId,
}) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final itemId = await app.seedItem(name: 'Item $rupees', rupees: rupees);
  final item = (await services.queries.itemById(firm.id, itemId))!;
  final cash = (await services.queries.paymentAccounts(
    firm.id,
  )).firstWhere((a) => a.modeLabel == 'cash');
  return services.postSale(
    services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: item.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: item.unitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: [
        if (paid > 0)
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(paid),
          ),
      ],
    ),
  );
}
