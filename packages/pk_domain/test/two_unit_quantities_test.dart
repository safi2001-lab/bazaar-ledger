import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// M45: quantities the way the shop counts them — "2 ctn + 5 pcs", "1 kg
/// 500 g" — shown, typed and printed, and never a decimal of a pack.
///
/// Vyapar's top review of September 2026 (+403) is a carton shown as
/// "0.4756". Everything here is integer thousandths of the base unit, so the
/// words add back to exactly what the shelf holds and what was typed reads
/// back to exactly what the bill charges for.
void main() {
  ItemPack pack(String code, num size) =>
      ItemPack(unitId: 'unit-$code', unitCode: code, size: Qty.parse('$size'));

  final carton = pack('carton', 24);
  final pieces = CountingLadder(
    baseCode: 'pcs',
    packs: [carton],
    baseDecimals: 0,
  );

  group('two-unit quantities', () {
    test('53 pieces of a carton of 24 read 2 ctn + 5 pcs, and 2 ctn 5 reads '
        'back as exactly 53 pieces', () {
      expect(pieces.words(Qty.units(53)), '2 ctn + 5 pcs');
      final typed = pieces.read('2 ctn 5')!;
      expect(typed.bare, isFalse);
      expect(typed.qty, Qty.units(53));
      expect(typed.qty.inThousandths, 53000);
    });

    test('shown as the largest whole pack and what is left, never a decimal '
        'of a pack', () {
      final cases = <(CountingLadder, String, String)>[
        (pieces, '53', '2 ctn + 5 pcs'),
        (pieces, '48', '2 ctn'),
        (pieces, '24', '1 ctn'),
        (pieces, '5', '5 pcs'),
        (pieces, '0', '0 pcs'),
        (pieces, '-53', '-(2 ctn + 5 pcs)'),
        (pieces, '-5', '-5 pcs'),
        (
          CountingLadder(baseCode: 'kg', packs: [pack('bori', 50)]),
          '62',
          '1 bori + 12 kg',
        ),
        (
          CountingLadder(baseCode: 'kg', packs: [pack('bori', 50)]),
          '62.5',
          '1 bori + 12 kg 500 g',
        ),
        (
          CountingLadder(baseCode: 'kg', packs: [pack('bori', 50)]),
          '0.75',
          '750 g',
        ),
        (CountingLadder(baseCode: 'kg'), '1.5', '1 kg 500 g'),
        (
          CountingLadder(baseCode: 'pcs', packs: [pack('dozen', 12)]),
          '40',
          '3 doz + 4 pcs',
        ),
        (
          CountingLadder(
            baseCode: 'pcs',
            packs: [pack('dabba', 10), pack('carton', 120)],
          ),
          '253',
          '2 ctn + 1 dabba + 3 pcs',
        ),
        (
          CountingLadder(baseCode: 'tablet', packs: [pack('strip', 10)]),
          '35',
          '3 strip + 5 tablet',
        ),
        // Not a pack: a "pack" of one piece, or of a part of one, only
        // repeats the piece under another name.
        (
          CountingLadder(baseCode: 'pcs', packs: [pack('packet', 1)]),
          '7',
          '7 pcs',
        ),
      ];
      for (final (ladder, qty, words) in cases) {
        expect(ladder.words(Qty.parse(qty)), words, reason: qty);
      }
    });

    test('every quantity reads back from its own words exactly, and no part '
        'of it is a fraction of a pack', () {
      final eggs = CountingLadder(
        baseCode: 'pcs',
        packs: [pack('carton', 30), pack('dozen', 12)],
        baseDecimals: 0,
      );
      final atta = CountingLadder(baseCode: 'kg', packs: [pack('bori', 40)]);
      for (var n = 0; n <= 400; n++) {
        final q = Qty.units(n);
        expect(eggs.read(eggs.words(q))!.qty, q, reason: eggs.words(q));
        final w = Qty.raw(n * 137);
        expect(atta.read(atta.words(w))!.qty, w, reason: atta.words(w));
      }
      for (final words in [
        eggs.words(Qty.units(397)),
        pieces.words(Qty.units(53)),
      ]) {
        for (final part in words.split(' + ')) {
          expect(part.split(' ').first, isNot(contains('.')), reason: words);
        }
      }
    });

    test('typed in English, Roman Urdu or Urdu, run together or spaced, the '
        'count is the same', () {
      final shop = CountingLadder(
        baseCode: 'pcs',
        packs: [carton],
        alsoReads: [pack('dozen', 12)],
        baseDecimals: 0,
      );
      final cases = <String, int>{
        '2 ctn 5': 53,
        '2c 5p': 53,
        '2 carton 5 pcs': 53,
        '2 ctn + 5 pcs': 53,
        '2ctn5': 53,
        '2 CTN 5 PC': 53,
        '2 peti 5 adad': 53,
        '2 karton aur 5 nag': 53,
        '۲ کارٹن ۵': 53,
        '2 کارٹن 5 عدد': 53,
        '0.5 ctn': 12,
        '1 ctn 1 doz': 36,
        '3 darjan 4': 40,
        '2 doz': 24,
        '5 pcs': 5,
        '1,000 pcs': 1000,
      };
      for (final MapEntry(key: typed, value: n) in cases.entries) {
        final read = shop.read(typed);
        expect(read, isNotNull, reason: typed);
        expect(read!.bare, isFalse, reason: typed);
        expect(read.qty, Qty.units(n), reason: typed);
      }
    });

    test(
      'kilos with grams, and the mann, are typed the way they are called',
      () {
        final atta = CountingLadder(
          baseCode: 'kg',
          packs: [pack('bori', 50)],
          alsoReads: [pack('maund', 40), pack('g', 0.001)],
        );
        final cases = <String, String>{
          '1 kg 250': '1.25',
          '1 kilo 250 gram': '1.25',
          '1kg250g': '1.25',
          '1.25 kg': '1.25',
          '250 g': '0.25',
          '1 mann 5': '45',
          '1 bori 12': '62',
          '1 bori 12 500': '62.5',
          '2 کلو 500 گرام': '2.5',
        };
        for (final MapEntry(key: typed, value: kg) in cases.entries) {
          expect(atta.read(typed)?.qty, Qty.parse(kg), reason: typed);
        }
      },
    );

    test('a figure on its own is in the unit the box is already in, as it '
        'always was', () {
      for (final typed in ['53', '1.5', ' 7 ', '۵۳']) {
        final read = pieces.read(typed)!;
        expect(read.bare, isTrue, reason: typed);
      }
      expect(pieces.read('53')!.qty, Qty.units(53));
      expect(pieces.read('1.5')!.qty, Qty.parse('1.5'));
    });

    test('what cannot be read exactly is refused, never guessed', () {
      for (final typed in [
        '',
        'abc',
        'ctn 5',
        '2 xyz 5',
        '5 2 ctn',
        '1.5 pcs', // half a piece of something sold whole
        '0.1 ctn', // 2.4 pieces
        '2 ctn -5',
        '1.2345',
        '2 ctn 5 3', // a figure after the piece has nowhere to go
      ]) {
        expect(pieces.read(typed), isNull, reason: typed);
      }
      // "p" is a piece and a packet: the piece, which the shelf counts in.
      final both = CountingLadder(
        baseCode: 'pcs',
        packs: [carton, pack('packet', 6)],
        baseDecimals: 0,
      );
      expect(both.read('1 p')!.qty, Qty.units(1));
      expect(both.read('1 pkt')!.qty, Qty.units(6));
      // "d" is a dozen and a dabba, and neither is the piece: refused.
      final ambiguous = CountingLadder(
        baseCode: 'pcs',
        packs: [pack('dabba', 10)],
        alsoReads: [pack('dozen', 12)],
        baseDecimals: 0,
      );
      expect(ambiguous.read('1 d'), isNull);
    });

    test('2 ctn + 5 pcs is charged exactly: 53 pieces at the piece price the '
        'carton price carries to', () {
      final units = UnitConverter([
        const UnitEdge(
          fromUnitId: 'unit-carton',
          toUnitId: 'unit-pcs',
          factorThousandths: 24000,
          itemId: 'gala',
        ),
      ]);
      final perPiece = units.convertRate(
        Rate.rupees(960),
        fromUnitId: 'unit-carton',
        toUnitId: 'unit-pcs',
        itemId: 'gala',
      );
      expect(perPiece, Rate.rupees(40));
      final qty = pieces.read('2 ctn 5')!.qty;
      expect(perPiece.amountFor(qty), Money.rupees(2120));
      // And the same 53 pieces by the carton come to the same money.
      expect(
        Rate.rupees(960).amountFor(
              units.convert(
                Qty.units(48),
                fromUnitId: 'unit-pcs',
                toUnitId: 'unit-carton',
                itemId: 'gala',
              ),
            ) +
            perPiece.amountFor(Qty.units(5)),
        Money.rupees(2120),
      );
      // At Rs 41.50 a piece, to the paisa.
      expect(Rate.parse('41.50').amountFor(qty), Money.parse('2199.50'));
      // A carton price that is no whole price per piece is not carried.
      expect(
        () => units.convertRate(
          Rate.rupees(1000),
          fromUnitId: 'unit-carton',
          toUnitId: 'unit-pcs',
          itemId: 'gala',
        ),
        throwsA(isA<UnitConversionException>()),
      );
    });

    test('the carton calculator: a carton price says the piece price, and a '
        'piece price the carton price', () {
      final fromCarton = pieces.pricesFrom(Rate.rupees(960), per: carton.size);
      expect(fromCarton.single.unitCode, 'pcs');
      expect(fromCarton.single.rate, Rate.rupees(40));
      expect(fromCarton.single.exact, isTrue);

      final fromPiece = pieces.pricesFrom(Rate.rupees(40), per: Qty.one);
      expect(fromPiece.single.unitCode, 'carton');
      expect(fromPiece.single.rate, Rate.rupees(960));

      // Rs 1,000 a carton of 24 is Rs 41.666... a piece: shown to the
      // paisa, and said to be approximate.
      final odd = pieces.pricesFrom(Rate.rupees(1000), per: carton.size);
      expect(odd.single.rate, Rate.parse('41.67'));
      expect(odd.single.exact, isFalse);
    });

    test('a shop\'s ladders come from its conversions: an item\'s own packs '
        'are shown, the shop\'s dozen only when a line is sold in it, and '
        'every exact unit is understood', () {
      final units = UnitConverter([
        const UnitEdge(
          fromUnitId: 'u-dozen',
          toUnitId: 'u-pcs',
          factorThousandths: 12000,
        ),
        const UnitEdge(
          fromUnitId: 'u-g',
          toUnitId: 'u-kg',
          factorThousandths: 1,
        ),
        const UnitEdge(
          fromUnitId: 'u-maund',
          toUnitId: 'u-kg',
          factorThousandths: 40000,
        ),
        const UnitEdge(
          fromUnitId: 'u-carton',
          toUnitId: 'u-pcs',
          factorThousandths: 24000,
          itemId: 'gala',
        ),
        const UnitEdge(
          fromUnitId: 'u-bori',
          toUnitId: 'u-kg',
          factorThousandths: 50000,
          itemId: 'atta',
        ),
      ]);
      final book = CountingBook(
        units,
        codes: const {
          'u-pcs': 'pcs',
          'u-dozen': 'dozen',
          'u-carton': 'carton',
          'u-kg': 'kg',
          'u-g': 'g',
          'u-maund': 'maund',
          'u-bori': 'bori',
        },
      );

      final gala = book.ladder(itemId: 'gala', baseUnitCode: 'pcs');
      expect(gala.words(Qty.units(53)), '2 ctn + 5 pcs');
      expect(
        book.ladder(itemId: 'eggs', baseUnitCode: 'pcs').words(Qty.units(40)),
        '40 pcs',
      );
      expect(
        book
            .ladder(
              itemId: 'eggs',
              baseUnitCode: 'pcs',
              countedInUnitId: 'u-dozen',
            )
            .words(Qty.units(40)),
        '3 doz + 4 pcs',
      );
      expect(
        book
            .ladder(itemId: 'atta', baseUnitCode: 'kg')
            .words(Qty.parse('62.5')),
        '1 bori + 12 kg 500 g',
      );
      final typing = book.entryLadder(
        itemId: 'atta',
        baseUnitCode: 'kg',
        baseUnitId: 'u-kg',
      );
      expect(typing.read('1 mann 5')!.qty, Qty.units(45));
      expect(typing.read('1 bori 250 g')!.qty, Qty.parse('50.25'));
      expect(
        book
            .entryLadder(itemId: 'eggs', baseUnitCode: 'pcs', baseDecimals: 0)
            .read('2 darjan 4')!
            .qty,
        Qty.units(28),
      );
      // Another item's carton is not this one's.
      expect(
        book.entryLadder(itemId: 'eggs', baseUnitCode: 'pcs').read('1 ctn'),
        isNull,
      );
      expect(
        CountingBook.none.ladder(baseUnitCode: 'kg').words(Qty.parse('1.5')),
        '1 kg 500 g',
      );
    });

    test('on paper: in packs where the line is not, and nothing where the '
        'figure already says it', () {
      expect(
        paperQuantity(
          qty: Qty.units(53),
          unitCode: 'pcs',
          baseQty: Qty.units(53),
          baseCode: 'pcs',
          packs: [carton],
        ),
        (words: '2 ctn 5 pc', inPacks: true),
      );
      expect(
        paperQuantity(
          qty: Qty.parse('1.5'),
          unitCode: 'kg',
          baseQty: Qty.parse('1.5'),
          baseCode: 'kg',
        ),
        (words: '1 kg 500 g', inPacks: false),
      );
      // Sold by the carton: "2 carton" is the line already.
      expect(
        paperQuantity(
          qty: Qty.units(2),
          unitCode: 'carton',
          baseQty: Qty.units(48),
          baseCode: 'pcs',
          packs: [carton],
        ),
        isNull,
      );
      // Sold when the carton was 20: the bill's own size, not today's.
      expect(
        paperQuantity(
          qty: Qty.units(2),
          unitCode: 'carton',
          baseQty: Qty.units(40),
          baseCode: 'pcs',
          packs: [carton],
        ),
        isNull,
      );
      // A mann and a quarter is a mann and ten kilos.
      expect(
        paperQuantity(
          qty: Qty.parse('1.25'),
          unitCode: 'maund',
          baseQty: Qty.units(50),
          baseCode: 'kg',
        ),
        (words: '1 maund 10 kg', inPacks: true),
      );
      for (final (qty, unit) in [('5', 'pcs'), ('2', 'kg'), ('250', 'g')]) {
        expect(
          paperQuantity(
            qty: Qty.parse(qty),
            unitCode: unit,
            baseQty: unit == 'g' ? Qty.parse('0.25') : Qty.parse(qty),
            baseCode: unit == 'g' ? 'kg' : unit,
            packs: [carton],
          ),
          isNull,
          reason: '$qty $unit',
        );
      }
    });
  });
}
