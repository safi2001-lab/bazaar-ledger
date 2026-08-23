import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Which bills a payment settles.
///
/// A wholesale customer hands over Rs 50,000 against four open bills and says
/// nothing about which. Being unable to answer *which bills did this settle*
/// is the single most-complained-about gap in the products this competes
/// with, and a shopkeeper who cannot answer it cannot argue about it with a
/// customer either.
void main() {
  group('oldest first', () {
    test('one payment clears the two oldest and part of the third', () {
      final result = allocateFifo(const Money.rupees(5000), [
        _bill('c', '2026-08-10', 3, 2000),
        _bill('a', '2026-06-01', 1, 3000),
        _bill('b', '2026-07-15', 2, 1500),
      ]);

      expect(result.allocations.map((a) => a.documentId), ['a', 'b', 'c']);
      expect(result.allocations[0].amount, const Money.rupees(3000));
      expect(result.allocations[1].amount, const Money.rupees(1500));
      expect(result.allocations[2].amount, const Money.rupees(500));
      expect(result.unapplied, Money.zero);
    });

    test('the input order does not matter and the input is not mutated', () {
      final bills = [
        _bill('b', '2026-07-15', 2, 1500),
        _bill('a', '2026-06-01', 1, 3000),
      ];
      allocateFifo(const Money.rupees(100), bills);

      expect(
        bills.map((b) => b.documentId),
        ['b', 'a'],
        reason: 'the caller list was reordered underneath it',
      );
    });

    test('a backdated bill sorts by its date, not by when it was typed', () {
      // A shopkeeper doing Friday's paperwork on Sunday. The bill is older
      // than the one raised in between, and the customer thinks of it that
      // way, so it has to clear first.
      final result = allocateFifo(const Money.rupees(1000), [
        _bill('typed-first', '2026-08-14', 1, 1000),
        _bill('dated-earlier', '2026-08-11', 9, 1000),
      ]);

      expect(result.allocations.single.documentId, 'dated-earlier');
    });

    test('same-day bills clear in the order they were raised', () {
      final result = allocateFifo(const Money.rupees(1500), [
        _bill('second', '2026-08-11', 42, 1000),
        _bill('first', '2026-08-11', 41, 1000),
      ]);

      expect(result.allocations.first.documentId, 'first');
      expect(result.allocations.first.amount, const Money.rupees(1000));
      expect(result.allocations.last.amount, const Money.rupees(500));
    });

    test('the order is total, so the same input gives the same answer', () {
      // Two bills a sort could legitimately call equal. A comparator that
      // stops at date and sequence leaves their order to the sort's internals,
      // and an allocation that is not reproducible is not evidence.
      List<String> run() => allocateFifo(const Money.rupees(1000), [
        _bill('zzz', '2026-08-11', 1, 600),
        _bill('aaa', '2026-08-11', 1, 600),
      ]).allocations.map((a) => a.documentId).toList();

      expect(run(), run());
      expect(run().first, 'aaa');
    });
  });

  group('what must never happen', () {
    test('a settled bill is skipped, never netted against', () {
      // The tempting bug: take the overshoot off the next bill in the list.
      // It produces the right total and the wrong khata — the shop's record
      // shows a bill part-paid that the customer paid in full, and the
      // argument at the counter is unwinnable from either side.
      final result = allocateFifo(const Money.rupees(1000), [
        _bill('settled', '2026-06-01', 1, 0),
        _bill('open', '2026-07-01', 2, 1000),
      ]);

      expect(result.allocations.map((a) => a.documentId), ['open']);
      expect(result.allocations.single.amount, const Money.rupees(1000));
    });

    test('a bill that has somehow gone negative is left alone', () {
      // Not reachable through a well-formed list, and this is the allocator's
      // one chance to refuse to make it worse.
      final result = allocateFifo(const Money.rupees(500), [
        _bill('overpaid', '2026-06-01', 1, -200),
        _bill('open', '2026-07-01', 2, 500),
      ]);

      expect(result.allocations.map((a) => a.documentId), ['open']);
    });

    test('no allocation is ever larger than the bill it points at', () {
      final result = allocateFifo(const Money.rupees(9999), [
        _bill('a', '2026-06-01', 1, 100),
        _bill('b', '2026-07-01', 2, 250),
      ]);

      expect(result.allocations[0].amount, const Money.rupees(100));
      expect(result.allocations[1].amount, const Money.rupees(250));
    });

    test('no allocation is ever zero', () {
      // A zero row is a claim that this payment touched that bill, and it did
      // not. It also makes every "which bills did this settle" answer longer
      // and wronger than the truth.
      final result = allocateFifo(const Money.rupees(1000), [
        _bill('a', '2026-06-01', 1, 1000),
        _bill('b', '2026-07-01', 2, 500),
      ]);

      expect(result.allocations, hasLength(1));
      expect(result.allocations.every((a) => a.amount.isPositive), isTrue);
    });
  });

  group('money left over', () {
    test('becomes an advance rather than an allocation', () {
      // A customer paying more than they owe is not an error and must not be
      // refused: leaving credit is ordinary in a shop that takes standing
      // orders. Parking the remainder on the oldest bill would write an
      // allocation larger than the bill it points at, and
      // findOverAllocatedPayments() is the check that finds that — six months
      // later, with no way left to reconstruct what was meant.
      final result = allocateFifo(const Money.rupees(5000), [
        _bill('a', '2026-06-01', 1, 3000),
      ]);

      expect(result.allocations, hasLength(1));
      expect(result.allocations.single.amount, const Money.rupees(3000));
      expect(result.unapplied, const Money.rupees(2000));
    });

    test('a customer with nothing outstanding pays entirely on account', () {
      final result = allocateFifo(const Money.rupees(5000), const []);

      expect(result.allocations, isEmpty);
      expect(result.unapplied, const Money.rupees(5000));
    });
  });

  group('the arithmetic', () {
    test('a payment of nothing is refused in words', () {
      expect(
        () => allocateFifo(Money.zero, const []),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => allocateFifo(const Money.rupees(-100), const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('paisa are exact, not near enough', () {
      // Three bills of a third of a rupee each. Anything that went through a
      // double here would leave a paisa on the floor, and a paisa on the
      // floor every day is a khata that never reconciles.
      final result = allocateFifo(const Money.paisa(100), [
        _bill('a', '2026-06-01', 1, 0, paisa: 33),
        _bill('b', '2026-06-02', 2, 0, paisa: 33),
        _bill('c', '2026-06-03', 3, 0, paisa: 34),
      ]);

      expect(result.applied, const Money.paisa(100));
      expect(result.unapplied, Money.zero);
    });

    test('property: 2000 random payments never create or destroy a paisa', () {
      // The one that matters. Allocations plus the remainder must sum back to
      // exactly what the customer handed over, whatever the shape of the
      // books, or the shop's cash and its khata disagree by an amount nobody
      // can account for.
      final random = Random(20260824);

      for (var run = 0; run < 2000; run++) {
        final bills = <OpenBill>[
          for (var i = 0; i < random.nextInt(8); i++)
            _bill(
              'doc-$i',
              '2026-0${1 + random.nextInt(9)}-1${random.nextInt(9)}',
              random.nextInt(50),
              0,
              // Zero and negative outstandings deliberately in the mix.
              paisa: random.nextInt(500000) - 50000,
            ),
        ];
        final amount = Money.paisa(1 + random.nextInt(400000));

        final result = allocateFifo(amount, bills);

        expect(
          result.applied + result.unapplied,
          amount,
          reason: 'run $run lost or invented money',
        );
        expect(result.unapplied.isNegative, isFalse, reason: 'run $run');
        for (final allocation in result.allocations) {
          expect(allocation.amount.isPositive, isTrue, reason: 'run $run');
          final bill = bills.firstWhere(
            (b) => b.documentId == allocation.documentId,
          );
          expect(
            allocation.amount <= bill.outstanding,
            isTrue,
            reason: 'run $run over-allocated ${allocation.documentId}',
          );
        }
      }
    });

    test('property: allocations are always oldest first', () {
      final random = Random(20260825);

      for (var run = 0; run < 500; run++) {
        final bills = <OpenBill>[
          for (var i = 0; i < 6; i++)
            _bill(
              'doc-$i',
              '2026-0${1 + random.nextInt(9)}-1${random.nextInt(9)}',
              random.nextInt(50),
              0,
              paisa: 1 + random.nextInt(100000),
            ),
        ];

        final result = allocateFifo(const Money.rupees(100000), bills);
        final keys = result.allocations.map((a) {
          final bill = bills.firstWhere((b) => b.documentId == a.documentId);
          // Padded, because the allocator orders sequence numerically and a
          // bare string key would make 45 sort before 5 — the first version
          // of this failed for that reason and the allocator was right.
          final seq = bill.sequence.toString().padLeft(4, '0');
          return '${bill.dateLocal}#$seq';
        }).toList();

        final sorted = [...keys]..sort();
        expect(keys, sorted, reason: 'run $run applied a newer bill first');
      }
    });
  });
}

OpenBill _bill(
  String id,
  String date,
  int sequence,
  int rupees, {
  int paisa = 0,
}) => OpenBill(
  documentId: id,
  dateLocal: date,
  sequence: sequence,
  outstanding: Money.paisa(rupees * 100 + paisa),
);
