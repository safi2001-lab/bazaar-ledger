import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// What the goods on a shelf actually cost.
///
/// `avg_cost_milli_paisa` has been written once at item creation and never
/// moved. Until it does, every margin figure in this app is a guess: a shop
/// that opened an item at Rs 90 and has been buying at Rs 120 for six months
/// still reads a Rs 30 profit on every sale.
void main() {
  group('a delivery moves the average', () {
    test('the weighted step, with numbers a shopkeeper could check', () {
      // 10 units carried at Rs 90 = Rs 900. Add 10 at Rs 120 = Rs 1,200.
      // 20 units, Rs 2,100, Rs 105 each.
      final change = receiveStock(
        before: _at(qty: 10, avgRupees: 90),
        qtyIn: Qty.units(10),
        landedCost: const Money.rupees(1200),
      );

      expect(change.after.qty, Qty.units(20));
      expect(change.after.avg, const Rate.rupees(105));
      expect(change.after.value, const Money.rupees(2100));
      expect(change.adjustment, Money.zero);
    });

    test('freight is in the cost, because the shop paid it', () {
      // Rs 1,000 of rice and Rs 200 to the rickshaw is Rs 1,200 of rice on
      // the shelf. A margin computed against the invoice alone is a margin
      // that has never paid for delivery.
      final change = receiveStock(
        before: CostPosition.zero,
        qtyIn: Qty.units(10),
        landedCost: const Money.rupees(1200),
      );

      expect(change.after.avg, const Rate.rupees(120));
    });

    test('the first delivery sets the cost by itself', () {
      final change = receiveStock(
        before: CostPosition.zero,
        qtyIn: Qty.units(4),
        landedCost: const Money.rupees(1000),
      );

      expect(change.after.avg, const Rate.rupees(250));
      expect(change.after.value, const Money.rupees(1000));
    });

    test('a delivery onto an empty shelf ignores the old average', () {
      // The shop sold out at Rs 90 and the new delivery is Rs 130. There is
      // nothing left to weight against, so the new price is the price.
      final change = receiveStock(
        before: const CostPosition(
          qty: Qty.zero,
          value: Money.zero,
          avg: Rate.rupees(90),
        ),
        qtyIn: Qty.units(10),
        landedCost: const Money.rupees(1300),
      );

      expect(change.after.avg, const Rate.rupees(130));
    });

    test('a fractional quantity averages exactly', () {
      // 3.5 kg at Rs 150 and 1.5 kg at Rs 200: Rs 525 + Rs 300 = Rs 825 over
      // 5 kg = Rs 165.
      final change = receiveStock(
        before: _at(qty: 0, avgRupees: 0).copyWith(
          qty: Qty.parse('3.5'),
          value: const Money.rupees(525),
          avg: const Rate.rupees(150),
        ),
        qtyIn: Qty.parse('1.5'),
        landedCost: const Money.rupees(300),
      );

      expect(change.after.avg, const Rate.rupees(165));
      expect(change.after.value, const Money.rupees(825));
    });

    test('what it refuses', () {
      expect(
        () => receiveStock(
          before: CostPosition.zero,
          qtyIn: Qty.zero,
          landedCost: const Money.rupees(100),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => receiveStock(
          before: CostPosition.zero,
          qtyIn: Qty.units(1),
          landedCost: const Money.rupees(-1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('a sale does not', () {
    test('the average is untouched by an issue', () {
      // The most common thing to get wrong. An issue takes stock out at the
      // cost it is carried at; changing the cost because something left would
      // make a sale profitable by selling.
      final change = issueStock(
        before: _at(qty: 20, avgRupees: 105),
        qtyOut: Qty.units(8),
      );

      expect(change.after.avg, const Rate.rupees(105));
      expect(change.after.qty, Qty.units(12));
      expect(change.after.value, const Money.rupees(1260));
      expect(change.adjustment, Money.zero);
    });

    test('selling out keeps the average, never clears it', () {
      // A zero here posts zero COGS on the next sale if the next delivery is
      // entered a minute late, and a sale with no cost has infinite margin in
      // every report that reads it.
      final change = issueStock(
        before: _at(qty: 10, avgRupees: 90),
        qtyOut: Qty.units(10),
      );

      expect(change.after.qty, Qty.zero);
      expect(change.after.value, Money.zero);
      expect(
        change.after.avg,
        const Rate.rupees(90),
        reason: 'the next sale before the next delivery would post no cost',
      );
    });

    test('selling more than is on the shelf goes negative, not to zero', () {
      // It happens: the delivery was not entered, the customer took the tin.
      // Clamping to zero would hide the fact that the books and the shelf
      // disagree, which is the one thing a stock ledger is for.
      final change = issueStock(
        before: _at(qty: 2, avgRupees: 100),
        qtyOut: Qty.units(5),
      );

      expect(change.after.qty.inThousandths, -3000);
    });
  });

  group('the shortfall a late delivery covers', () {
    test('is written off, never averaged into the new stock', () {
      // The shop is 3 units short at Rs 100 each. The delivery of 10 at
      // Rs 1,300 must cost Rs 130 each, not Rs 100 — letting the absence
      // dilute the average makes everything on the shelf look cheaper than it
      // was, forever.
      final change = receiveStock(
        before: const CostPosition(
          qty: Qty.raw(-3000),
          value: Money.rupees(-300),
          avg: Rate.rupees(100),
        ),
        qtyIn: Qty.units(10),
        landedCost: const Money.rupees(1300),
      );

      expect(change.after.avg, const Rate.rupees(130));
      expect(change.fromShortfall, isTrue);
      expect(change.after.qty, Qty.units(7));

      // Inventory held -Rs 300 and the bill adds Rs 1,300, so the account is
      // at Rs 1,000 — but the seven units on the shelf are worth Rs 910. The
      // Rs 90 difference is what the three missing units really cost beyond
      // what the books took them out at, and it was never anybody's profit.
      expect(change.after.value, const Money.rupees(910));
      expect(change.adjustment, const Money.rupees(90));
    });

    test('an ordinary delivery writes nothing off', () {
      final change = receiveStock(
        before: _at(qty: 10, avgRupees: 90),
        qtyIn: Qty.units(10),
        landedCost: const Money.rupees(1200),
      );

      expect(change.fromShortfall, isFalse);
    });
  });

  group('the invariant', () {
    test('a residue appears where the division does not come out', () {
      // 1.833 kg of rice carried at Rs 85/kg is Rs 155.81. Add 1.5 kg for
      // Rs 100 and the average is Rs 76.74917/kg — a figure that cannot make
      // the value both round(avg x qty) and valueBefore + landedCost. One
      // paisa has nowhere to go, and without a journal line for it Inventory
      // drifts a paisa at a time until nobody can say when it started.
      //
      // The first version of this test used numbers that divided evenly, so
      // it asserted an equality that held whether the residue existed or not.
      // Deleting the residue line failed nothing, which is how it was found.
      final before = CostPosition(
        qty: const Qty.raw(1833),
        value: const Rate.rupees(85).amountFor(const Qty.raw(1833)),
        avg: const Rate.rupees(85),
      );
      expect(before.value, const Money.paisa(15581));

      final change = receiveStock(
        before: before,
        qtyIn: const Qty.raw(1500),
        landedCost: const Money.rupees(100),
      );

      expect(
        change.adjustment,
        const Money.paisa(1),
        reason: 'the paisa that cannot land in either place went missing',
      );
      expect(change.fromShortfall, isFalse);
      expect(change.after.value, const Money.paisa(25580));
      expect(
        change.after.value,
        change.after.avg.amountFor(change.after.qty),
        reason: 'the invariant broke',
      );
      expect(
        before.value + const Money.rupees(100),
        change.after.value + change.adjustment,
        reason: 'what the shop paid is not what it is carrying',
      );
    });

    test('property: value always equals round(avg x qty), 5000 movements', () {
      // The whole point of the residue. Held forward by induction, never by
      // re-summing history, so this asserts the induction never drifts.
      final random = Random(20260824);
      var position = CostPosition.zero;
      var residues = Money.zero;
      var paidIn = Money.zero;
      var issued = Money.zero;
      var residueCount = 0;

      for (var step = 0; step < 5000; step++) {
        final buying = position.qty.inThousandths <= 0 || random.nextBool();
        if (buying) {
          final qtyIn = Qty.raw(1 + random.nextInt(50000));
          final cost = Money.paisa(1 + random.nextInt(5000000));
          final change = receiveStock(
            before: position,
            qtyIn: qtyIn,
            landedCost: cost,
          );
          position = change.after;
          residues += change.adjustment;
          if (!change.adjustment.isZero) residueCount++;
          paidIn += cost;
        } else {
          final available = position.qty.inThousandths;
          final qtyOut = Qty.raw(1 + random.nextInt(available));
          final atCost = position.avg.amountFor(qtyOut);
          final change = issueStock(before: position, qtyOut: qtyOut);
          position = change.after;
          residues += change.adjustment;
          if (!change.adjustment.isZero) residueCount++;
          issued += atCost;
        }

        expect(
          position.value,
          position.qty.inThousandths == 0
              ? Money.zero
              : position.avg.amountFor(position.qty),
          reason: 'the invariant broke at step $step',
        );
      }

      // Conservation, which is what the residue is FOR. Everything the shop
      // paid is either still on the shelf, or has been issued at cost, or is
      // the residue. Nothing else. Summing to anything but zero means a
      // journal entry somewhere does not balance.
      expect(
        paidIn,
        position.value + issued + residues,
        reason: 'money entered or left the costing without a line for it',
      );
      expect(
        residues.abs.inPaisa,
        lessThan(paidIn.inPaisa),
        reason:
            'the adjustment is the size of the trade, so it is not a '
            'rounding step and not a shortfall — it is a bug',
      );

      // And residues really do occur, or the assertion above proves nothing.
      // They did not in the first version of this, because the seed happened
      // to divide evenly every time.
      expect(
        residueCount,
        greaterThan(100),
        reason:
            'no rounding step ever happened, so this run would pass with the '
            'residue deleted',
      );
    });

    test('property: an issue never changes the average, 2000 times', () {
      final random = Random(20260825);
      var position = receiveStock(
        before: CostPosition.zero,
        qtyIn: Qty.units(1000000),
        landedCost: const Money.rupees(9000000),
      ).after;

      for (var step = 0; step < 2000; step++) {
        final before = position.avg;
        position = issueStock(
          before: position,
          qtyOut: Qty.raw(1 + random.nextInt(100)),
        ).after;
        expect(position.avg, before, reason: 'the average moved at step $step');
      }
    });
  });

  group('overflow is refused, never wrapped', () {
    test('an absurd carried value throws rather than going negative', () {
      // avg is milli-paisa and qty is thousandths, so the product is six
      // orders of magnitude above the rupee figure a shopkeeper would
      // recognise. It wraps at int64 long before anything looks wrong.
      expect(
        () => receiveStock(
          before: const CostPosition(
            qty: Qty.raw(9000000000000000),
            value: Money.paisa(9000000000000000),
            avg: Rate.raw(9000000000),
          ),
          qtyIn: Qty.units(1),
          landedCost: const Money.rupees(100),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

CostPosition _at({required int qty, required int avgRupees}) => CostPosition(
  qty: Qty.units(qty),
  value: Rate.rupees(avgRupees).amountFor(Qty.units(qty)),
  avg: Rate.rupees(avgRupees),
);

extension on CostPosition {
  CostPosition copyWith({Qty? qty, Money? value, Rate? avg}) => CostPosition(
    qty: qty ?? this.qty,
    value: value ?? this.value,
    avg: avg ?? this.avg,
  );
}
