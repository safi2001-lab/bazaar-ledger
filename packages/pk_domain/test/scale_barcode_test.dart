import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Builds a label as a scale prints it: prefix, PLU, value, check digit.
String label(String prefix, String plu, String value) {
  final body = '$prefix$plu$value';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = body.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return '$body${(10 - sum % 10) % 10}';
}

void main() {
  group('scale label', () {
    test('a weight label gives the PLU and the grams', () {
      final data = parseScaleBarcode(
        label('21', '00042', '01500'),
        ScaleFormat.standard,
      )!;
      expect(data.plu, '42');
      expect(data.grams, 1500);
      expect(data.price, isNull);
    });

    test('a price label gives the PLU and the rupees', () {
      final data = parseScaleBarcode(
        label('23', '00007', '01250'),
        ScaleFormat.standard,
      )!;
      expect(data.plu, '7');
      expect(data.price, const Money.rupees(1250));
      expect(
        parseScaleBarcode(
          label('23', '00007', '01250'),
          const ScaleFormat(priceDecimals: 2),
        )!.price,
        Money.paisa(1250),
      );
    });

    test('a torn label or an ordinary barcode is not a scale label', () {
      final good = label('21', '00042', '01500');
      final torn = '${good.substring(0, 12)}${(int.parse(good[12]) + 1) % 10}';
      expect(parseScaleBarcode(torn, ScaleFormat.standard), isNull);
      expect(parseScaleBarcode('8964000123456', ScaleFormat.standard), isNull);
      expect(
        parseScaleBarcode(label('27', '00042', '01500'), ScaleFormat.standard),
        isNull,
        reason: 'a prefix the shop has not named',
      );
    });

    test('a four-digit PLU leaves six digits of weight', () {
      final data = parseScaleBarcode(
        label('22', '0042', '012345'),
        const ScaleFormat(pluDigits: 4),
      )!;
      expect(data.plu, '42');
      expect(data.grams, 12345);
    });

    test('the format a shop set is kept, and a broken one is not used', () {
      const custom = ScaleFormat(
        weightPrefixes: {'20'},
        pricePrefixes: {'25', '26'},
        pluDigits: 6,
        priceDecimals: 2,
      );
      final back = ScaleFormat.fromJson(custom.toJson());
      expect(back.weightPrefixes, {'20'});
      expect(back.pricePrefixes, {'25', '26'});
      expect(back.pluDigits, 6);
      expect(back.priceDecimals, 2);
      expect(ScaleFormat.fromJson('nonsense').pluDigits, 5);
      expect(
        ScaleFormat.fromJson(
          const ScaleFormat(
            weightPrefixes: {'21'},
            pricePrefixes: {'21'},
          ).toJson(),
        ).pricePrefixes,
        {'23', '24'},
        reason: 'one prefix cannot mean both',
      );
    });
  });
}
