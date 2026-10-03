import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 10, 3, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// The mobile-shop pack through the services the app is built on (M50): a
/// used phone bought over the counter and the register it lands in; a phone
/// sold on qist, its plan, the register and what PTA said reaching the other
/// counter over a real socket, where the instalments fall due on its chase
/// list; and who may do what.
void main() {
  late _Ticking clock;
  late AppServices master;
  late String firmId;
  late String pcs;
  late String cash;
  late String phoneItem;
  late String customer;

  const imeiA = '356938035643809';
  const imeiA2 = '356938035643817';
  const imeiUsed = '352098765432107';

  setUp(() async {
    clock = _Ticking();
    master = await openInMemoryServices(clock: clock);
    await master.setUpShop(
      shopName: 'Hafeez Centre Mobiles',
      ownerName: 'Bilal Sahib',
      deviceLabel: 'Master',
    );
    await master.updateFirm({'business_kind': 'mobile'});
    firmId = (await master.queries.currentFirm())!.id;
    pcs = (await master.queries.units(
      firmId,
    )).singleWhere((u) => u.code == 'pcs').id;
    cash = (await master.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    phoneItem = await master.catalogue.addItem(
      master.actorNow(),
      ItemDraft(
        name: 'Samsung A15',
        baseUnitId: pcs,
        saleRate: Rate.rupees(60000),
        tracksSerial: true,
        warranty: const ItemWarranty(months: 12, kind: WarrantyKind.brand),
      ),
    );
    customer = await master.catalogue.addParty(
      master.actorNow(),
      const PartyDraft(name: 'Rashid Ali', phone: '03001234567'),
    );
  });

  tearDown(() => master.close());

  UsedPhoneBuyDraft usedPhone({String imei = imeiUsed}) => UsedPhoneBuyDraft(
    sellerName: 'Kashif Mehmood',
    sellerCnic: '35202-1234567-1',
    sellerPhone: '0300-7654321',
    conditionNote: 'Back cracked',
    itemId: phoneItem,
    itemName: 'Samsung A15',
    unitId: pcs,
    unitCode: 'pcs',
    phone: PhoneUnitDraft(imei1: imei, pta: PtaStatus.approved),
    price: Money.rupees(18000),
    paymentAccountId: cash,
  );

  test('a used phone bought through the services lands in stock and on the '
      'register, and a cashier may not buy one', () async {
    expect(await master.mobile.isMobileShop(), isTrue);
    final bought = await master.mobile.buyUsedPhone(usedPhone());

    final found = await master.mobile.findPhones('2107');
    expect(found.single.lotId, bought.lotId);
    expect(found.single.onHand, isTrue);
    final register = await master.reports.run(
      ReportKind.usedPhonesRegister,
      firmId: firmId,
      period: ReportPeriod(
        const BusinessDate('2026-10-01'),
        const BusinessDate('2026-10-31'),
      ),
      today: const BusinessDate('2026-10-03'),
    );
    final row = register.rows.first.cells;
    expect(row[2], 'Kashif Mehmood');
    expect(row[3], '35202-1234567-1');
    expect(row[6], imeiUsed);
    expect(row[9], Money.rupees(18000));

    await master.setPin(master.currentUser!.id, '9999');
    final boy = await master.addStaff(
      name: 'Imran',
      role: Role.cashier,
      pin: '2468',
    );
    expect(await master.signIn(boy, '2468'), isTrue);
    await expectLater(
      master.mobile.buyUsedPhone(usedPhone(imei: '861234056789012')),
      throwsA(isA<PermissionDenied>()),
      reason: 'goods onto the shelf and cash out of the drawer',
    );
    // At the counter he may write down what PTA said.
    await master.mobile.setPta(bought.lotId, PtaStatus.nonCompliant);
    expect(
      (await master.mobile.phone(bought.lotId))!.pta,
      PtaStatus.nonCompliant,
    );
    final health = await master.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  test('a phone on qist, the register and what PTA said reach the other '
      'counter, where the instalments fall due on its chase list', () async {
    // A new phone from the distributor, by both IMEIs.
    final distributor = await master.catalogue.addParty(
      master.actorNow(),
      const PartyDraft(name: 'Hall Road Distributors', partyType: 'supplier'),
    );
    await master.recordPurchase(
      master.actorNow(),
      PurchaseDraft(
        partyId: distributor,
        lines: [
          PurchaseLineDraft(
            itemId: phoneItem,
            itemName: 'Samsung A15',
            qty: Qty.one,
            baseQty: Qty.one,
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(50000),
            phones: const [
              PhoneUnitDraft(
                imei1: imeiA,
                imei2: imeiA2,
                pta: PtaStatus.approved,
              ),
            ],
          ),
        ],
      ),
    );
    final lot = (await master.mobile.findPhones(imeiA)).single;
    final sale = await master.postSale(
      master.actorNow(),
      SaleDraft(
        partyId: customer,
        partyName: 'Rashid Ali',
        lines: [
          SaleLineDraft(
            itemId: phoneItem,
            itemName: 'Samsung A15',
            qty: Qty.one,
            baseQty: Qty.one,
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(60000),
            lotId: lot.lotId,
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: Money.rupees(10000),
          ),
        ],
        extraCharges: Money.rupees(5000),
        qist: QistPlanDraft(
          count: 11,
          dueDay: 5,
          firstDue: const BusinessDate('2026-11-05'),
          guarantor: const Guarantor(name: 'Tariq Ali'),
        ),
      ),
    );
    await master.mobile.buyUsedPhone(usedPhone());

    final port = await master.sync.startHosting(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    final counter = await openInMemoryServices(clock: clock);
    addTearDown(counter.close);
    await counter.sync.join(
      host: '127.0.0.1',
      port: port,
      code: master.sync.openJoining(),
      label: 'Counter 2',
    );

    expect(await counter.mobile.isMobileShop(), isTrue);
    final plan = (await counter.mobile.planForBill(sale.documentId))!;
    expect(plan.financed, Money.rupees(55000));
    expect(plan.count, 11);
    expect(plan.markup, Money.rupees(5000));
    expect(plan.guarantor?.name, 'Tariq Ali');
    final story = (await counter.mobile.story(lot.lotId))!;
    expect(story.unit.imei2, imeiA2);
    expect(story.unit.pta, PtaStatus.approved);
    expect(story.warrantyUntil?.value, '2027-10-03');
    expect(
      (await counter.mobile.usedPhonesBought()).single.seller.cnic,
      '3520212345671',
    );

    final chase = await counter.udhaar.queries.dueParties(
      firmId,
      asOfDateLocal: '2026-11-06',
    );
    expect(chase.single.party.id, customer);
    expect(chase.single.overdue, Money.rupees(5000));
    final instalments = await counter.reports.run(
      ReportKind.qistInstalments,
      firmId: firmId,
      period: ReportPeriod(
        const BusinessDate('2026-10-03'),
        const BusinessDate('2026-10-03'),
      ),
      today: const BusinessDate('2026-11-06'),
    );
    final cells = instalments.rows.first.cells;
    expect(cells[0], 'Rashid Ali');
    expect(cells[6], Money.rupees(55000));
    expect(cells[9], Money.rupees(5000), reason: 'November is late');
    expect(cells[12], 'Overdue');

    final paper = (await counter.queries.receiptFor(firmId, sale.documentId))!;
    expect(paper.lines.single.details, contains('IMEI 2: $imeiA2'));
    expect(paper.lines.single.details, contains('Warranty till 3 Oct 2027'));
    final health = await counter.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });
}
