import 'dart:io';

import 'package:bazaar_ledger/app/app.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/harness.dart';

/// Forty reminders sent in an evening, each in the customer's own language
/// (M39).
///
/// Driven through the real chase list, the real round and the real
/// settings, against a real database. WhatsApp, the messages app and the
/// share sheet are other applications; each is stood in for at its platform
/// seam, so what is asserted is exactly what this app handed over — and
/// then what it wrote in the khata's log.
final _sheet = _FakeShareSheet();
final _phone = _MessagingOnThePhone();

void main() {
  setUpAll(() {
    SharePlatform.instance = _sheet;
    UrlLauncherPlatform.instance = _phone;
  });
  setUp(() {
    _sheet.reset();
    _phone.reset();
  });

  testWidgets('everyone late is ticked at once, and each reminder opens in '
      'WhatsApp in the customer\'s own language', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _late(app, 'Aslam Karyana', '0300 1111111');
    await _late(app, 'Bilal Store', '0300 2222222');
    final chaudhry = await _late(app, 'Chaudhry Mart', '0300 3333333');
    final dawood = await _late(app, 'Dawood Sons', '0300 4444444');
    await _owing(app, 'Ehsan Traders', '0300 5555555');
    await app.services.udhaar.setReminderPrefs(
      aslam,
      const ReminderPrefs(language: ReminderLanguage.urdu),
    );
    await app.services.udhaar.setReminderPrefs(
      chaudhry,
      const ReminderPrefs(language: ReminderLanguage.english),
    );
    await app.services.udhaar.setReminderPrefs(
      dawood,
      const ReminderPrefs(optedOut: true),
    );

    await _openChase(tester);
    await tester.tap(find.byTooltip('Yaad-dehani bhejein'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Sab der wale chunein');
    // Ehsan is not late; Dawood asked not to be messaged.
    await tapButton(tester, '3 ko yaad dilayein');

    for (final (name, words) in [
      ('Aslam Karyana', 'السلام علیکم Aslam Karyana'),
      ('Bilal Store', 'Assalam-o-Alaikum Bilal Store'),
      ('Chaudhry Mart', 'A gentle reminder from Chishti Kiryana Store'),
    ]) {
      await settleReal(tester, until: find.text('WhatsApp par kholein'));
      expect(find.text(name), findsWidgets);
      await tapButton(tester, 'WhatsApp par kholein');
      final opened = Uri.parse(_phone.opened.last);
      expect(opened.scheme, 'whatsapp');
      expect(opened.queryParameters['text'], contains(words));
      await tapButton(tester, 'Bhej diya');
    }
    await settleReal(
      tester,
      until: find.text('Sab ho gaye: 3 ko bheja, 0 chhore'),
    );
    await tapButton(tester, 'Khatam');

    final log = await app.rowsOf(
      'SELECT entity_id, after_json FROM audit_log '
      "WHERE action_code = 'REMINDER_SENT' ORDER BY at_utc, id",
    );
    expect(log, hasLength(3));
    expect(log.every((r) => '${r['after_json']}'.contains('whatsapp')), true);
    expect(log.map((r) => r['entity_id']), isNot(contains(dawood)));
    expect(find.text('Aaj yaad dilaya'), findsNWidgets(3));
  });

  testWidgets('a round left half way picks up at the next name after the '
      'app is killed', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    await _late(app, 'Aslam Karyana', '0300 1111111');
    await _late(app, 'Bilal Store', '0300 2222222');

    await _openChase(tester);
    await tester.tap(find.byTooltip('Yaad-dehani bhejein'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Sab der wale chunein');
    await tapButton(tester, '2 ko yaad dilayein');
    await settleReal(tester, until: find.text('WhatsApp par kholein'));
    await tapButton(tester, 'WhatsApp par kholein');
    await tapButton(tester, 'Bhej diya');
    await settleReal(tester, until: find.text('1 / 2'));

    // The phone's ROM kills the app while WhatsApp is open.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(app.services)],
        child: const BazaarLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await _openChase(tester);
    await settleReal(
      tester,
      until: find.text('Yaad-dehani adhoori hai: 1 baqi'),
    );
    await tapButton(tester, 'Jaari rakhein');
    await settleReal(tester, until: find.text('WhatsApp par kholein'));
    expect(find.text('1 / 2'), findsOneWidget);
    await tapButton(tester, 'WhatsApp par kholein');
    expect(_phone.opened.last, contains('923002222222'));
  });

  testWidgets('by SMS the phone\'s own messages app opens with the words '
      'typed, and the log says so', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    await _late(app, 'Bilal Store', '0300 2222222');

    await _openChase(tester);
    await tester.tap(find.byTooltip('Yaad-dehani bhejein'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Sab der wale chunein');
    await tapButton(tester, '1 ko yaad dilayein');
    await settleReal(tester, until: find.text('WhatsApp par kholein'));
    await tapText(tester, 'SMS');
    await tapButton(tester, 'SMS mein kholein');

    final opened = Uri.parse(_phone.opened.single);
    expect(opened.scheme, 'sms');
    expect(opened.path, '+923002222222');
    expect(opened.queryParameters['body'], contains('Bilal Store'));
    await tapButton(tester, 'Bhej diya');
    final log = await app.rowsOf(
      "SELECT after_json FROM audit_log WHERE action_code = 'REMINDER_SENT'",
    );
    expect('${log.single['after_json']}', contains('"channel":"sms"'));
  });

  testWidgets('the owner rewrites a reminder, the khata sends it, and the '
      'shop words come back', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    await _late(app, 'Bilal Store', '0300 2222222');

    await openSettings(tester);
    await tapText(tester, 'Yaad-dehani ke paighamat');
    await tester.enterText(
      find.widgetWithText(TextField, 'Paigham'),
      'Salaam {name}, Rs {amount} baqi. {shop}',
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Salaam Aslam Karyana, Rs 4,500.00 baqi. Chishti Kiryana Store',
      ),
      findsOneWidget,
    );
    await tapButton(tester, 'Save karein');
    await settleReal(tester, until: find.text('Paigham save ho gaya'));

    await _openKhata(tester, 'Bilal Store');
    await tester.tap(find.byTooltip('Yaad dilayein'));
    await settleReal(tester, until: find.textContaining('Aaj yaad dilaya'));
    expect(
      Uri.parse(_phone.opened.single).queryParameters['text'],
      'Salaam Bilal Store, Rs 1,000.00 baqi. Chishti Kiryana Store',
    );
    expect(
      find.text('Aaj yaad dilaya · Malik Sahib · WhatsApp'),
      findsOneWidget,
    );

    await _home(tester);
    await openSettings(tester);
    await tapText(tester, 'Yaad-dehani ke paighamat');
    await tapButton(tester, 'Dukaan ke asal alfaz wapas layein');
    await settleReal(tester, until: find.text('Asal alfaz wapas aa gaye'));
    expect(
      find.textContaining('Assalam-o-Alaikum Aslam Karyana'),
      findsOneWidget,
    );
    final ready = await app.services.udhaar.reminderFor(
      (await app.rowsOf('SELECT id FROM parties')).single['id']! as String,
    );
    expect(ready!.message, startsWith('Assalam-o-Alaikum Bilal Store'));
  });

  testWidgets('a customer who asks not to be messaged is not offered a '
      'reminder, and the language picked is kept', (tester) async {
    final app = await Harness.startWithShop(tester);
    final bilal = await _late(app, 'Bilal Store', '0300 2222222');

    await _openKhata(tester, 'Bilal Store');
    expect(find.byTooltip('Yaad dilayein'), findsOneWidget);
    await tester.tap(find.byTooltip('Gahak ki tafseel'));
    await tester.pumpAndSettle();
    await tapText(tester, 'اردو');
    await tapText(tester, 'Is gahak ko yaad-dehani na bhejein');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Yaad dilayein'), findsNothing);
    expect(find.text('Yaad-dehani band'), findsOneWidget);
    final prefs = await app.services.udhaar.reminderPrefs(bilal);
    expect(prefs.language, ReminderLanguage.urdu);
    expect(prefs.optedOut, isTrue);
  });

  testWidgets("the shop's payment details reach the message", (tester) async {
    final app = await Harness.startWithShop(tester);
    final bilal = await _late(app, 'Bilal Store', '0300 2222222');
    await app.services.updateFirm({
      'raast_alias': '03001234567',
      'bank_name': 'Meezan Bank',
      'bank_iban': _iban,
    });

    final ready = await app.services.udhaar.reminderFor(bilal);
    expect(ready!.message, contains('Adaygi: Raast 03001234567 · Meezan Bank'));
    expect(ready.message, contains(_iban));
    expect(ready.whatsappNumber, '923002222222');
  });

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('the round and the tick list fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final name = await _late(
        app,
        'Chaudhry Muhammad Aslam Karyana Store',
        '0300 1111111',
      );
      await app.services.udhaar.setReminderPrefs(
        name,
        const ReminderPrefs(language: ReminderLanguage.urdu),
      );
      await _openChase(tester);
      await tester.tap(find.byTooltip('Yaad-dehani bhejein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapButton(tester, 'Sab der wale chunein');
      await tapButton(tester, '1 ko yaad dilayein');
      await settleReal(tester, until: find.text('WhatsApp par kholein'));
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the reminder messages screen fits', (tester) async {
      _useASmallPhone(tester);
      await Harness.startWithShop(tester);
      await openSettings(tester);
      await tapText(tester, 'Yaad-dehani ke paighamat');
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'اردو');
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// A made-up IBAN, in the shape the bank prints.
const _iban = 'PK36MEZN0001234567890101';

/// A customer on no credit with a Rs 1,000 bill from ten days ago: late.
Future<String> _late(Harness app, String name, String phone) async {
  final id = await app.services.catalogue.addParty(
    app.services.actorNow(),
    PartyDraft(name: name, phone: phone, creditDays: 0),
  );
  await _bill(app, id, daysAgo: 10);
  return id;
}

/// A customer with a month's credit and a bill from two days ago: owes,
/// and is not late.
Future<String> _owing(Harness app, String name, String phone) async {
  final id = await app.services.catalogue.addParty(
    app.services.actorNow(),
    PartyDraft(name: name, phone: phone, creditDays: 30),
  );
  await _bill(app, id, daysAgo: 2);
  return id;
}

Future<void> _bill(Harness app, String partyId, {required int daysAgo}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final itemId = await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Item $partyId',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(1000),
      openingStock: Qty.units(10),
    ),
  );
  final day = BusinessDate.now(const SystemClock()).addDays(-daysAgo);
  await app.services.postSale(
    ActorContext(
      firmId: firm,
      userId: app.services.identity!.userId,
      deviceId: app.services.identity!.deviceId,
      startedAtUtc: DateTime.utc(day.year, day.month, day.day, 4),
    ),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Item',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(1000),
        ),
      ],
      tenders: const [],
    ),
  );
}

Future<void> _home(WidgetTester tester) async {
  final home = tester.element(find.byType(HomeScreen, skipOffstage: false));
  Navigator.of(home).popUntil((route) => route.isFirst);
  ProviderScope.containerOf(home).bumpRefresh();
  await tester.pumpAndSettle();
}

Future<void> _openKhata(WidgetTester tester, String name) async {
  await _home(tester);
  await tapText(tester, 'Gahak');
  await tapText(tester, name);
}

Future<void> _openChase(WidgetTester tester) async {
  await _home(tester);
  await tapText(tester, 'Gahak');
  await tester.tap(find.byTooltip('Udhaar wasooli'));
  await tester.pumpAndSettle();
}

void _useATallScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(800, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final texts = <String>[];

  void reset() => texts.clear();

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// Stands in for WhatsApp and the messages app being on the phone: answers
/// `whatsapp://` and `sms:` and records each it was asked to open.
final class _MessagingOnThePhone extends UrlLauncherPlatform {
  final opened = <String>[];

  void reset() => opened.clear();

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async =>
      url.startsWith('whatsapp://') || url.startsWith('sms:');

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

/// A 360dp-wide phone with the font at 200%.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Every rendered piece of text still inside the screen it was drawn on.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}

/// A real font, because the test font's square glyphs make every width
/// assertion pass.
Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
