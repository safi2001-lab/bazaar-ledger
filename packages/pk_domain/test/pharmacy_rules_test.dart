import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The pharmacy pack's rules (M49) with no database: the printed price, a
/// held batch, the salt key substitutes are found by, the near-expiry list
/// by supplier, and what a Schedule sale must say.
void main() {
  group('the printed retail price', () {
    test('a line is above its MRP only when what the customer pays for it is '
        'more than the printed price allows; below is always allowed', () {
      final ceiling = retailValueOf(
        mrp: Money.rupees(50),
        baseQty: Qty.units(3),
      );
      expect(ceiling, Money.rupees(150));
      expect(
        aboveMrp(
          itemName: 'Disprin',
          qty: Qty.units(3),
          charged: Money.rupees(150),
          ceiling: ceiling,
        ),
        isNull,
      );
      expect(
        aboveMrp(
          itemName: 'Disprin',
          qty: Qty.units(3),
          charged: Money.rupees(135),
          ceiling: ceiling,
        ),
        isNull,
        reason: '10% off MRP',
      );
      final over = aboveMrp(
        itemName: 'Disprin',
        qty: Qty.units(3),
        charged: Money.paisa(15001),
        ceiling: ceiling,
      )!;
      expect(over.over, Money.paisa(1));
      expect(
        aboveMrp(
          itemName: 'Ghee',
          qty: Qty.one,
          charged: Money.rupees(999),
          ceiling: null,
        ),
        isNull,
        reason: 'no printed price, nothing to be above',
      );
    });

    test("the counter's warning and the pharmacy's refusal are one check, "
        'on one printed price', () {
      // A carton of 24 packs at Rs 120 a pack: the printed price of the
      // line is Rs 2,880, whoever asks.
      final retail = retailValueOf(
        mrp: Money.rupees(120),
        baseQty: Qty.units(24),
      );
      expect(retail, Money.rupees(2880));
      for (final (charged, above) in [
        (Money.rupees(2880), false),
        (Money.rupees(2592), false),
        (Money.paisa(288001), true),
      ]) {
        expect(isAboveRetail(charged, retail), above);
        expect(
          sellsAboveMrp(
            mrp: Money.rupees(120),
            baseQty: Qty.units(24),
            lineValue: charged,
          ),
          above,
          reason: "M59's note under the line",
        );
        expect(
          aboveMrp(
                itemName: 'Shampoo',
                qty: Qty.units(24),
                charged: charged,
                ceiling: retail,
              ) !=
              null,
          above,
          reason: "M49's refusal in a pharmacy",
        );
      }
      expect(retailValueOf(mrp: null, baseQty: Qty.one), isNull);
      expect(retailValueOf(mrp: Money.zero, baseQty: Qty.one), isNull);
    });

    test('a pharmacy is refused, any other shop is warned', () {
      expect(mrpRuleFor(isPharmacy: true), MrpRule.block);
      expect(mrpRuleFor(isPharmacy: false), MrpRule.warn);
      expect(const PharmacyRules(isPharmacy: true).mrpRule, MrpRule.block);
      expect(PharmacyRules.none.mrpRule, MrpRule.warn);
    });
  });

  group('a batch on hold', () {
    final today = const BusinessDate('2026-10-03');
    LotBalance lot(String no, int qty, String expiry, {String? held}) =>
        LotBalance(
          lotId: no,
          lotNo: no,
          qty: Qty.units(qty),
          expiry: BusinessDate(expiry),
          holdReason: held,
        );

    test('is passed by first-expiry-first-out, and refused in its own words '
        'when nothing else will do', () {
      final lots = [
        lot('OLD', 5, '2026-12-31', held: 'DRAP recall'),
        lot('NEW', 5, '2027-12-31'),
      ];
      expect(
        takeFefo(
          needed: Qty.units(4),
          lots: lots,
          unlotted: Qty.zero,
          today: today,
        ),
        [(lotId: 'NEW', qty: Qty.units(4))],
      );
      expect(
        () => takeFefo(
          needed: Qty.units(7),
          lots: lots,
          unlotted: Qty.zero,
          today: today,
        ),
        throwsA(
          isA<StockRefused>().having(
            (e) => e.reason,
            'reason',
            'Batch OLD is on hold and cannot be sold: DRAP recall',
          ),
        ),
      );
    });
  });

  group('the salt', () {
    test('two medicines of one salt and strength share one key, however the '
        'strength is written; another strength does not', () {
      expect(
        genericSearchColumn('Paracetamol', '500 mg'),
        genericSearchColumn('paracetamol', '500mg'),
      );
      expect(
        genericSearchColumn('Paracetamol', '500 mg'),
        isNot(genericSearchColumn('Paracetamol', '250 mg')),
      );
      expect(genericSearchColumn(null, '500 mg'), isNull);
      expect(genericSearchColumn('  ', null), isNull);
      expect(
        const MedicineDetails(
          genericName: 'Paracetamol',
          strength: '500 mg',
        ).label,
        'Paracetamol 500 mg',
      );
      expect(const MedicineDetails(manufacturer: ' ').isEmpty, isTrue);
      expect(ScheduleClass.fromCode('B'), ScheduleClass.b);
      expect(ScheduleClass.fromCode(null), isNull);
    });
  });

  group('a Schedule sale', () {
    test('needs the patient, the prescriber and the registration number', () {
      expect(
        const Prescription(
          patientName: 'Bilal',
          prescriberName: 'Dr Ayesha',
          prescriberRegNo: '123',
        ).gaps,
        isEmpty,
      );
      expect(
        const Prescription(
          patientName: ' ',
          prescriberName: 'Dr Ayesha',
          prescriberRegNo: '',
        ).gaps,
        ['patient', "prescriber's registration number"],
      );
    });
  });

  group('near expiry', () {
    ExpiringBatch batch(String no, String expiry, String? supplier) =>
        ExpiringBatch(
          lotId: no,
          itemId: 'i',
          itemName: 'Panadol',
          lotNo: no,
          qty: Qty.units(10),
          unitCode: 'pcs',
          cost: Rate.rupees(3),
          expiry: BusinessDate(expiry),
          supplierId: supplier,
          supplierName: supplier,
        );

    test('is listed under the supplier each batch came from, soonest first, '
        'and the batches from nobody last', () {
      final groups = expiriesBySupplier([
        batch('B3', '2026-12-01', 'Shaheen Pharma'),
        batch('B1', '2026-11-01', null),
        batch('B2', '2026-10-15', 'Medi Distributors'),
        batch('B4', '2026-10-10', 'Shaheen Pharma'),
      ]);
      expect(
        [for (final g in groups) g.supplierName],
        ['Medi Distributors', 'Shaheen Pharma', null],
      );
      expect([for (final b in groups[1].batches) b.lotNo], ['B4', 'B3']);
      expect(groups[1].value, Money.rupees(60));
      expect(
        groups.first.batches.single.isExpiredOn(
          const BusinessDate('2026-10-16'),
        ),
        isTrue,
      );
    });
  });
}
