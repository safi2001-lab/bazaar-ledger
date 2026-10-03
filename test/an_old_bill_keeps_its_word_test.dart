import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/harness.dart';

/// An old bill, opened on the phone and sent again after its customer and
/// its item were edited, says what it said on the day (M62).
///
/// The paper itself is proved in pk_bootstrap's an_old_bill_keeps_its_word
/// test, design by design; this drives the screens a shopkeeper uses: the
/// bill found in the sales list by the customer's NEW name, opened, read on
/// screen, and sent from there into WhatsApp and as a PDF.
final _sheet = _FakeShareSheet();
final _whatsapp = _WhatsAppOnThePhone();

void main() {
  setUpAll(() {
    SharePlatform.instance = _sheet;
    UrlLauncherPlatform.instance = _whatsapp;
  });
  setUp(() {
    _sheet.reset();
    _whatsapp.reset();
  });

  testWidgets('a bill opened and sent after its customer and item were '
      'edited reads as it did on the day', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firmId = services.identity!.firmId;
    final pcs = (await services.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    final cash = (await services.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final rashid = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(
        name: 'Rashid Traders',
        phone: '0300-4471203',
        addressLine1: 'Shop 5, Shah Alam Market',
        city: 'Lahore',
        ntn: '7654321-0',
      ),
    );
    final oil = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    // The counter's draft: the party picked from the khata, and its name.
    final bill = await services.postSale(
      services.actorNow(),
      SaleDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(1000),
          ),
        ],
      ),
    );

    // The customer moved, changed number, re-registered and renamed the
    // firm; the item was renamed and repriced.
    await services.catalogue.updateParty(
      services.actorNow(),
      rashid,
      const PartyDraft(
        name: 'Rashid Brothers',
        phone: '0333-9998887',
        addressLine1: 'Plot 9, Badami Bagh',
        city: 'Faisalabad',
        ntn: '1111111-1',
      ),
    );
    await services.catalogue.updateItem(
      services.actorNow(),
      oil,
      ItemDraft(
        name: 'Dalda Oil Tin',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(2900),
      ),
    );

    // Found by the name the khata has now: a renamed customer still finds
    // their old bills (M30), and the row says what the bill says.
    await tester.pumpAndSettle();
    await tapText(tester, 'Farokht');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bill talash karein'),
      'brothers',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text(bill.docNo), findsOneWidget);
    expect(find.textContaining('Rashid Traders'), findsWidgets);
    expect(find.textContaining('Rashid Brothers'), findsNothing);

    await tapText(tester, bill.docNo);
    // The screen is the paper (M2): every line of it the bill's own.
    await settleReal(tester, until: find.textContaining('Cooking Oil 5L'));
    expect(find.textContaining('Rashid Traders'), findsWidgets);
    expect(find.textContaining('Cooking Oil 5L'), findsWidgets);
    expect(find.textContaining('2 pcs x 2,500.00'), findsWidgets);
    for (final word in ['Brothers', 'Dalda', '2,900.00', 'Badami']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    // The sheet that goes with the goods prints where they go: the address
    // the bill was made for, and the number that answers today.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transporter'));
    await settleReal(tester, until: find.textContaining('DELIVERY COPY'));
    expect(find.textContaining('Shah Alam'), findsOneWidget);
    expect(find.textContaining('Badami'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transporter'));
    await tester.pumpAndSettle();

    // Into the customer's chat: greeted by the bill's name, on the
    // khata's number of today.
    await tester.tap(find.widgetWithText(InkWell, 'WhatsApp'));
    await _settleWhileBusy(tester);
    final chat = Uri.parse(_whatsapp.opened.single);
    expect(chat.queryParameters['phone'], '923339998887');
    expect(
      chat.queryParameters['text'],
      allOf(contains('Rashid Traders'), isNot(contains('Brothers'))),
    );

    // As a PDF, in the shop's design: the address it was made with.
    await tester.tap(find.text('PDF bhejein'));
    await _settleWhileBusy(tester);
    final pdf = File(_sheet.paths.single).readAsBytesSync();
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final paper = (await services.billPaper(bill.documentId))!.receipt;
    expect(paper.customerAddress, 'Shop 5, Shah Alam Market, Lahore');
    expect(paper.customerNtn, '7654321-0');
    expect(_sheet.texts.single, contains('Rashid Traders'));
  });
}

/// Lets a share finish, which takes both a clock and a disk (see
/// a_bill_is_sent_again_test).
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];
  final texts = <String>[];

  void reset() {
    paths.clear();
    texts.clear();
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

final class _WhatsAppOnThePhone extends UrlLauncherPlatform {
  final opened = <String>[];

  void reset() => opened.clear();

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => url.startsWith('whatsapp://');

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}
