import 'dart:io';

import 'package:bazaar_ledger/features/khata/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// A customer's statement as a PDF, and the purchase register (M24).
void main() {
  final shareSheet = _FakeShareSheet();
  SharePlatform.instance = shareSheet;
  setUp(shareSheet.paths.clear);

  testWidgets('a customer\'s statement goes to the share sheet as a PDF', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Hisaab ka statement (PDF)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shuru se ab tak'));
    await settleReal(tester, done: () => shareSheet.paths.isNotEmpty);

    expect(shareSheet.paths, hasLength(1));
    final pdf = (await tester.runAsync(
      () => File(shareSheet.paths.single).readAsBytes(),
    ))!;
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    final party = (await tester.runAsync(
      () async => (await app.services.queries.searchParties(
        (await app.services.queries.currentFirm())!.id,
        query: 'Rashid',
      )).single,
    ))!;
    final table = (await tester.runAsync(
      () => statementFor(
        app.services,
        party,
        span: StatementSpan.all,
        owedToUs: true,
      ),
    ))!;
    expect(table.rows.last.cells.last, const Money.rupees(4500));
  });

  testWidgets('a purchase shows on the purchase register', (tester) async {
    final app = await Harness.startWithShop(tester);
    final firmId = (await app.services.queries.currentFirm())!.id;
    final mill = await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
    );
    final rice = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
    final pcs = (await app.services.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    await app.services.recordPurchase(
      app.services.actorNow(),
      PurchaseDraft(
        partyId: mill,
        supplierBillNo: 'PRM/771',
        lines: [
          PurchaseLineDraft(
            itemId: rice,
            itemName: 'Chawal Basmati',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(120),
          ),
        ],
      ),
    );

    final table = await app.services.reports.run(
      ReportKind.purchaseRegister,
      firmId: firmId,
      period: ReportPeriod.monthOf(BusinessDate.now(app.services.clock)),
      today: BusinessDate.now(app.services.clock),
    );
    expect(table.rows, hasLength(2));
    expect(table.rows.first.cells[2], 'Punjab Rice Mills');
    expect(table.rows.first.cells[3], 'PRM/771');
    expect(table.rows.last.cells[7], const Money.rupees(1200));

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(
      find.text('Khareed register'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Khareed register'), findsOneWidget);
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
