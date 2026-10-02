import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The spelling key: how "cheeni" finds "Chini" and آٹا finds "Atta".
///
/// Two tables, and both matter equally. The first is spellings the shop
/// writes the same thing in, which must come out as one key. The second is
/// different things the shop sells side by side, which must NOT — a search
/// that folds tel (oil) into til (sesame) is not forgiving, it is wrong.
void main() {
  group('spelling key', () {
    // Each row is one thing, spelled the ways it is spelled.
    const same = <List<String>>[
      ['atta', 'aata', 'Atta', 'ATTA', 'آٹا'],
      ['cheeni', 'chini', 'Cheeni', 'چینی'],
      ['ghee', 'ghi', 'Ghee', 'گھی'],
      ['daal', 'dal', 'dhal', 'دال'],
      ['doodh', 'dudh', 'dood', 'دودھ'],
      ['zeera', 'jeera', 'jira', 'زیرہ'],
      ['qeema', 'keema', 'qima', 'قیمہ'],
      ['roti', 'rooti', 'ruti', 'روٹی'],
      ['gosht', 'gost', 'گوشت'],
      ['suji', 'sooji', 'سوجی'],
      ['aloo', 'alu', 'aaloo', 'آلو'],
      ['chai', 'chae', 'chay', 'chaye', 'چائے'],
      ['moong', 'mung', 'mong'],
      ['kheer', 'khir', 'keer'],
      ['biryani', 'biriyani'],
      ['Rehman', 'Rahman', 'Rehmaan'],
      ['Mehmood', 'Mahmood', 'Mahmud'],
      ['Yousuf', 'Yusuf'],
      ['Usman', 'Osman'],
      ['Riaz', 'Riyaz'],
      ['Javed', 'Jawed'],
      ['subah', 'suba'],
      ['shampoo', 'shampu', 'sampoo'],
      ['t.v.', 'tv', 'TV', 'T.V'],
      ['7up', '7 up', '7-Up', '7UP'],
      ['coca cola', 'koka kola', 'Coca-Cola'],
      ['achha', 'acha', 'accha'],
    ];
    for (final row in same) {
      test('${row.join(' = ')} are one key', () {
        final key = spellingKey(row.first);
        expect(key, isNotEmpty);
        for (final spelling in row.skip(1)) {
          expect(
            spellingKey(spelling),
            key,
            reason: '"$spelling" should find "${row.first}"',
          );
        }
      });
    }

    // Each pair is two different things a shop sells.
    const apart = <List<String>>[
      ['chini', 'chana'],
      ['cheeni', 'chana'],
      ['tel', 'til'],
      ['dal', 'dil'],
      ['chawal', 'chana'],
      ['ghee', 'gur'],
      ['namak', 'nimko'],
      ['mirch', 'murgh'],
      ['sabun', 'sabzi'],
      ['dahi', 'dal'],
      ['atta', 'anda'],
      ['chai', 'chana'],
      ['100g', '10g'],
      ['maida', 'mewa'],
    ];
    for (final pair in apart) {
      test('${pair.first} is not ${pair.last}', () {
        expect(spellingKey(pair.first), isNot(spellingKey(pair.last)));
      });
    }

    test('the documented examples come out as the comment says', () {
      expect(spellingKey('atta'), 'ata');
      expect(spellingKey('cheeni'), 'cini');
      expect(spellingKey('doodh'), 'dud');
      expect(spellingKey('zeera'), 'jira');
      expect(
        nameSearchColumn('Atta Chakki 10kg'),
        'atta chakki 10kg|atacaki10kg~TCK10KG',
      );
      expect(nameSearchColumn('آٹا'), 'آٹا|ata~T');
      expect(nameSearchColumn('T.V. Stand'), 't v stand|twstand~TWSTND');
    });

    test('a word typed in Urdu is read into Roman letters first', () {
      expect(urduToRoman('آٹا'), 'ata');
      expect(urduToRoman('چینی'), 'chini');
      expect(urduToRoman('چاول'), 'chawl');
      expect(urduToRoman('دودھ'), 'dodh');
      expect(urduToRoman('زیرہ'), 'zira');
      // Urdu digits are digits; Urdu punctuation ends a word.
      expect(urduToRoman('۵ کلو'), '5 klo');
      expect(urduToRoman('چائے، دودھ'), 'chaie  dodh');
      // Text with no Urdu in it comes back as it went in.
      expect(urduToRoman('Dalda 5L'), 'Dalda 5L');
    });

    test('diacritics and joiners change nothing', () {
      // زِیرَہ with a zer and a zabar, as a careful typist writes it.
      expect(spellingKey('زِیرَہ'), spellingKey('زیرہ'));
      expect(spellingKey('چا‌ول'), spellingKey('چاول'));
    });

    test('Urdu that cannot be spelled back is still found by its bones', () {
      // چاول is written with no vowel between w and l, so its key is "cawl"
      // and Roman chawal's is "cawal". The skeleton is the same.
      expect(spellingKey('چاول'), isNot(spellingKey('chawal')));
      expect(
        spellingSkeleton(spellingKey('چاول')),
        spellingSkeleton(spellingKey('chawal')),
      );
      // The same for the names in a khata, where the h is a real letter:
      // محمد keeps it (mhmd) as Muhammad does, رحمان as Rehman does.
      for (final (urdu, roman) in const [
        ('محمد', 'Muhammad'),
        ('محمد', 'Mohammed'),
        ('رحمان', 'Rehman'),
        ('احمد', 'Ahmed'),
      ]) {
        expect(
          spellingSkeleton(spellingKey(urdu)),
          spellingSkeleton(spellingKey(roman)),
          reason: '$urdu and $roman',
        );
      }
    });

    test('a skeleton is trusted only when it is long enough', () {
      // "cn" would find chini and chana alike, so a Roman word needs three
      // consonants left before its skeleton is used.
      final chini = SpellingQuery.of('chini').words.single;
      expect(chini.skeleton, isNull);
      final chawal = SpellingQuery.of('chawal').words.single;
      expect(chawal.skeleton, 'cwl');
      // A word typed in Urdu may have its short vowels missing at the
      // source, and then two consonants are enough: گڑ is "gr", and gur is
      // only found by its bones.
      final gur = SpellingQuery.of('گڑ').words.single;
      expect(gur.typedInUrdu, isTrue);
      expect(gur.skeleton, 'gr');
      // But چینی writes every vowel it has. Its bones would be "cn", which
      // is chana's too, so it is matched by its key alone.
      expect(SpellingQuery.of('چینی').words.single.skeleton, isNull);
    });

    test('a search is read word by word, five words at most', () {
      final q = SpellingQuery.of('  Oil   DALDA ');
      expect(q.raw, 'Oil   DALDA');
      expect(q.plain, 'oil dalda');
      expect([for (final w in q.words) w.key], ['uil', 'dalda']);
      expect(q.key, 'uildalda');
      expect(SpellingQuery.of('a b c d e f g').words, hasLength(5));
      expect(SpellingQuery.of('').isEmpty, isTrue);
      expect(SpellingQuery.of('#!').words, isEmpty);
    });

    test('a name in Urdu is a name, not an empty string', () {
      // It used to be: the old normalisation stripped every non-ASCII
      // letter, so an Urdu name was found by nothing and twinned nothing.
      expect(plainSearchText('آٹا چکی'), 'آٹا چکی');
      expect(
        ItemDraft(
          name: ' Atta-Chakki ',
          baseUnitId: '',
          saleRate: Rate.zero,
        ).searchKey,
        'atta chakki',
      );
      expect(const PartyDraft(name: 'محمد علی').searchKey, 'محمد علی');
    });
  });

  group('kilos and grams', () {
    test('a weight with grams in it reads as kilos and grams', () {
      expect(quantityWords(Qty.parse('1.5'), 'kg'), '1 kg 500 g');
      expect(quantityWords(Qty.parse('0.75'), 'kg'), '750 g');
      expect(quantityWords(Qty.parse('0.005'), 'kg'), '5 g');
      expect(quantityWords(Qty.parse('2'), 'kg'), '2 kg');
      expect(quantityWords(Qty.parse('-0.25'), 'kg'), '-250 g');
      expect(quantityWords(Qty.parse('-3.1'), 'kg'), '-3 kg 100 g');
    });

    test('anything that is not kilos reads as before', () {
      expect(quantityWords(Qty.parse('1.5'), 'l'), '1.5 l');
      expect(quantityWords(Qty.parse('2'), 'pcs'), '2 pcs');
      expect(quantityWords(Qty.parse('0.5'), 'maund'), '0.5 maund');
    });
  });
}
