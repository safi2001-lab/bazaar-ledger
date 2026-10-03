import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// M45 on paper: a line sold by the piece says how many cartons that is,
/// on every roll the shop may have, without pushing a single figure past the
/// edge or cutting the amount.
void main() {
  const renderer = ThermalReceiptRenderer();

  const gala = ReceiptLine(
    name: 'Gala Biscuit Family Pack',
    qtyDisplay: '53',
    unitCode: 'pcs',
    rate: Rate.rupees(40),
    amount: Money.rupees(2120),
    qtyWords: '2 ctn 5 pc',
  );
  const cheeni = ReceiptLine(
    name: 'Cheeni',
    qtyDisplay: '1.5',
    unitCode: 'kg',
    rate: Rate.rupees(160),
    amount: Money.rupees(240),
  );
  const oil = ReceiptLine(
    name: 'Cooking Oil 5L',
    qtyDisplay: '2',
    unitCode: 'pcs',
    rate: Rate.rupees(2500),
    amount: Money.rupees(5000),
  );

  ReceiptData bill(List<ReceiptLine> lines, {ReceiptCopy? copy}) => ReceiptData(
    shop: const ReceiptShop(name: 'Chishti Kiryana Store'),
    docNo: 'INV-2627-0045',
    dateTimeLabel: '03-10-2026  6:15 PM',
    cashierName: 'Malik Sahib',
    lines: lines,
    subtotal: const Money.rupees(7360),
    total: const Money.rupees(7360),
    tenders: const [ReceiptTender(label: 'Cash', amount: Money.rupees(7360))],
    paid: const Money.rupees(7360),
    balance: Money.zero,
    change: Money.zero,
    copy: copy,
  );

  group('two units on paper', () {
    for (final paper in ReceiptPaper.values) {
      test('a line sold by the piece prints its cartons on '
          '${paper.columns} columns, and nothing runs past the edge', () {
        final lines = renderer.toPreview(
          bill(const [gala, cheeni, oil]),
          paper: paper,
        );
        for (final line in lines) {
          expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
        }
        final text = lines.join('\n');
        expect(text, contains('2 ctn 5 pc'), reason: 'the cartons are gone');
        expect(text, contains('53 pcs'), reason: 'the figure is gone');
        expect(
          lines.any((l) => l.endsWith('2,120.00')),
          isTrue,
          reason: 'the amount lost its place at the right margin',
        );
        // The rate is still the piece's, and still whole.
        expect(text, contains('x 40.00'));
        // A line with nothing to add prints exactly as it always did.
        expect(text, contains('  2 pcs x 2,500.00'));
      });
    }

    test('on 80 mm the cartons sit beside the figure, on one row with the '
        'amount', () {
      final lines = renderer.toPreview(bill(const [gala]));
      expect(
        lines,
        contains('  53 pcs (2 ctn 5 pc) x 40.00${' ' * 11}2,120.00'),
      );
    });

    test('on 58 mm the cartons take a line of their own under the figure', () {
      final lines = renderer.toPreview(
        bill(const [gala]),
        paper: ReceiptPaper.mm58,
      );
      final at = lines.indexWhere((l) => l.startsWith('  53 pcs x 40.00'));
      expect(at, isNonNegative);
      expect(lines[at], endsWith('2,120.00'));
      expect(lines[at + 1], '    (2 ctn 5 pc)');
    });

    test('a weight prints as it always did, plain enough to multiply out', () {
      for (final paper in ReceiptPaper.values) {
        final text = renderer
            .toPreview(bill(const [cheeni]), paper: paper)
            .join('\n');
        expect(text, contains('  1.5 kg x 160.00'), reason: '${paper.columns}');
        expect(text, isNot(contains('500 g')));
      }
    });

    test('a count too long for any row wraps onto lines of its own, never '
        'clipped', () {
      const odd = ReceiptLine(
        name: 'Surf Excel',
        qtyDisplay: '1,000.000',
        unitCode: 'bori-50kg-special-import',
        rate: Rate.rupees(12450),
        amount: Money.rupees(1234567),
        qtyWords: '12 bori-50kg-special-import 3 dabba-of-ten 5 pc',
      );
      for (final paper in ReceiptPaper.values) {
        final lines = renderer.toPreview(bill(const [odd]), paper: paper);
        for (final line in lines) {
          expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
        }
        final text = lines.join(' ');
        for (final word in odd.qtyWords!.split(' ')) {
          expect(text, contains(word), reason: '${paper.columns}: $word');
        }
        expect(lines.any((l) => l.trimLeft() == '12,34,567.00'), isTrue);
      }
    });

    test('the transporter copy counts in cartons, and still carries no '
        'money', () {
      for (final paper in ReceiptPaper.values) {
        final lines = renderer.toPreview(
          bill(const [gala], copy: ReceiptCopy.transporter),
          paper: paper,
        );
        final text = lines.join('\n');
        expect(text, contains('2 ctn 5 pc'), reason: '${paper.columns}');
        expect(text, isNot(contains('2,120.00')));
        for (final line in lines) {
          expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
        }
      }
    });

    test(
      'the PDF carries the cartons under the figure, in every design',
      () async {
        for (final theme in BillTheme.values) {
          final text = String.fromCharCodes(
            await billPdf(
              bill(const [gala, cheeni, oil]),
              design: BillDesign(theme: theme),
              compress: false,
            ),
          );
          // The PDF sets each word on its own: "2", "ctn", "5", "pc".
          expect(text, contains('[(ctn)]TJ'), reason: '$theme');
          expect(text, contains('[(pc)]TJ'), reason: '$theme');
          expect(text, contains('[(53)]TJ'), reason: '$theme');
          // Packs only: a weighed row stays one row, with no "g" under it.
          expect(text, isNot(contains('[(g)]TJ')), reason: '$theme');
        }
      },
    );
  });
}
