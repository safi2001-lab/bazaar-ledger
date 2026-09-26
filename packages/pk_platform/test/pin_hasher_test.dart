import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

void main() {
  const hasher = PinHasher.forTestsOnly();

  group('pin', () {
    test('the right PIN is accepted and a wrong one is not', () async {
      final stored = await hasher.hash('4821');
      expect(
        await hasher.verify('4821', hash: stored.hash, salt: stored.salt),
        isTrue,
      );
      expect(
        await hasher.verify('4820', hash: stored.hash, salt: stored.salt),
        isFalse,
      );
    });

    test('the digits are never what is stored', () async {
      final a = await hasher.hash('4821');
      final b = await hasher.hash('4821');
      expect(a.hash, isNot(contains('4821')));
      expect(a.hash, isNot(b.hash), reason: 'each PIN gets its own salt');
    });

    test('a PIN is four to six digits', () async {
      expect(PinHasher.isValidPin('482'), isFalse);
      expect(PinHasher.isValidPin('4821'), isTrue);
      expect(PinHasher.isValidPin('482193'), isTrue);
      expect(PinHasher.isValidPin('48a1'), isFalse);
      await expectLater(hasher.hash('12'), throwsArgumentError);
    });
  });
}
