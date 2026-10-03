import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/collections/sheet_paper.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// The recovery man's round on one sheet (M55), driven through the screens
/// against a real database.
///
/// Route 3's customers are picked from the chase list, numbered on a sheet
/// for Rafiq, sent out on paper; on his return each line is marked and the
/// whole round is written on every khata at once.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.clear);

  testWidgets('a route is put on a numbered sheet, and his return is written '
      'on every khata at once', (tester) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(app, 'Aslam Karyana', 5000, 'Route 3');
    final bilal = await _customer(app, 'Bilal Store', 3000, 'Route 3');
    final chaudhry = await _customer(app, 'Chaudhry Traders', 2000, 'Route 3');
    final dawood = await _customer(app, 'Dawood Mart', 1000, 'Route 5');

    await _openChase(tester);
    await tester.tap(find.byTooltip('Wasooli sheets'));
    await tester.pumpAndSettle();
    expect(find.text('Abhi koi wasooli sheet nahi'), findsOneWidget);
    await tester.tap(find.text('Nayi wasooli sheet'));
    await tester.pumpAndSettle();

    await typeInto(tester, 'Ya naam likhein', 'Rafiq');
    await tapText(tester, 'Route 3');
    await tapButton(tester, 'Sab chunein');
    expect(find.text('Dawood Mart'), findsNothing, reason: 'Route 5');
    await tapButton(tester, 'Sheet banayein · 3 gahak');
    await settleReal(tester, until: find.text('Recovery: Rafiq'));

    final sheetNo = (await app.services.collections.sheets()).single.sheetNo;
    expect(sheetNo, startsWith('WS-'));
    expect(find.text(sheetNo), findsOneWidget, reason: 'the title');
    expect(find.text('Bahar hai'), findsOneWidget);

    await tapButton(tester, 'Wapsi par likhein');
    await _tapIn(tester, 'Aslam Karyana', find.text('Pura diya'));
    await _tapIn(tester, 'Bilal Store', find.text('Kuch diya'));
    await tester.enterText(
      _in('Bilal Store', find.widgetWithText(TextFormField, 'Kitne mile')),
      '1000',
    );
    await tester.pumpAndSettle();
    await _tapIn(tester, 'Chaudhry Traders', find.text('Wada'));
    await _tapIn(tester, 'Chaudhry Traders', find.textContaining('Kal · '));
    await tapButton(tester, 'Sab khaton par likhein');
    await settleReal(
      tester,
      until: find.text('Wasooli likh li: Rs 6,000.00 aaye'),
    );

    // The khatas fell by exactly what came.
    expect(await _owed(app, aslam), Money.zero);
    expect(await _owed(app, bilal), const Money.rupees(2000));
    expect(await _owed(app, chaudhry), const Money.rupees(2000));
    expect(await _owed(app, dawood), const Money.rupees(1000));
    final notes = await app.rowsOf(
      "SELECT notes, amount_paisa FROM payments WHERE direction = 'in' "
      'ORDER BY amount_paisa DESC',
    );
    expect([for (final r in notes) r['amount_paisa']], [500000, 100000]);
    expect(
      [for (final r in notes) r['notes']],
      ['Wasooli $sheetNo · Rafiq', 'Wasooli $sheetNo · Rafiq'],
    );
    // Chaudhry's promise, on his khata as M38 keeps one.
    final promises = await app.services.udhaar.queries.promisesOf(
      app.services.identity!.firmId,
      chaudhry,
    );
    expect(promises.single.note, contains('Rafiq'));
    // The sheet says what he should hand over, and is closed.
    expect(find.text('Wapsi likh li'), findsOneWidget);
    expect(find.text('Cash hawale karna hai'), findsOneWidget);
    expect(
      find.text('Diye: 2 · Wade: 1 · Nahi diye: 0 · Nahi gaye: 0'),
      findsOneWidget,
    );
    expect(find.text('Wapsi par likhein'), findsNothing, reason: 'once');
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  testWidgets('the sheet goes out as a PDF and as a WhatsApp message', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(app, 'Aslam Karyana', 5000, 'Route 3');
    final sheet = await app.services.collections.makeSheet(
      SheetDraft(partyIds: [aslam], collector: 'Rafiq'),
    );

    await _openChase(tester);
    await tester.tap(find.byTooltip('Wasooli sheets'));
    await tester.pumpAndSettle();
    await tapText(tester, '${sheet.sheetNo} · Rafiq');

    await tester.tap(find.byTooltip('WhatsApp'));
    await settleReal(tester, done: () => _sheet.texts.isNotEmpty);
    final message = _sheet.texts.single;
    expect(message, contains('Wasooli sheet ${sheet.sheetNo}'));
    expect(message, contains('Recovery: Rafiq'));
    expect(message, contains('1. Aslam Karyana'));
    expect(message, contains('Purana baqaya'));
    expect(message, contains('Mila:'));

    await tester.tap(find.byTooltip('PDF bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);
    final pdf = String.fromCharCodes(
      File(_sheet.paths.single).readAsBytesSync(),
    );
    expect(pdf, contains('Wasooli sheet ${sheet.sheetNo}'));
  });

  testWidgets('the sheet fits a 58mm and an 80mm receipt roll', (tester) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(
      app,
      'Aslam Karyana General Store and Sons',
      5000,
      'Route 3 (Anarkali)',
    );
    final sheet = await app.services.collections.makeSheet(
      SheetDraft(partyIds: [aslam], collector: 'Rafiq'),
    );
    final s = AppStrings.of(tester.element(find.byType(HomeScreen)));

    for (final width in [32, 48]) {
      final slip = sheetSlip(s, sheet, width: width, shopName: 'Chishti');
      expect(
        slip.every((l) => l.text.length <= width),
        isTrue,
        reason: 'nothing runs off a $width-column roll',
      );
      expect(slip.map((l) => l.text), contains(startsWith('1. Aslam')));
      expect(
        slip.map((l) => l.text),
        contains(endsWith(const Money.rupees(5000).amountOnly)),
      );
      expect(slip.map((l) => l.text.trim()), contains(startsWith('Mila:')));
    }
  });

  testWidgets('at 200% on a small phone a sheet being marked fits', (
    tester,
  ) async {
    // Real IO: a widget test's clock is fake, and the font is read from disk.
    await tester.runAsync(_loadRealFont);
    tester.view
      ..physicalSize = const Size(720, 1600)
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(app, 'Aslam Karyana', 5000, 'Route 3');
    await app.services.collections.makeSheet(
      SheetDraft(partyIds: [aslam], collector: 'Rafiq'),
    );

    await _openChase(tester);
    await tester.tap(find.byTooltip('Wasooli sheets'));
    await tester.pumpAndSettle();
    await _tapContaining(tester, 'Rafiq');
    await tapButton(tester, 'Wapsi par likhein');
    await _tapIn(tester, 'Aslam Karyana', find.text('Wada'));
    _expectNothingOffScreen(tester);
  });
}

/// A customer owing [rupees] from before, filed on [group].
Future<String> _customer(Harness app, String name, int rupees, String group) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: name,
        openingBalance: Money.rupees(rupees),
        group: group,
      ),
    );

Future<Money> _owed(Harness app, String partyId) async =>
    (await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    ))!.balance;

/// [finder] inside the sheet line for [name].
Finder _in(String name, Finder finder) => find.descendant(
  of: find
      .ancestor(of: find.textContaining(name), matching: find.byType(BlCard))
      .first,
  matching: finder,
);

Future<void> _tapIn(WidgetTester tester, String name, Finder finder) async {
  final target = _in(name, finder).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openChase(WidgetTester tester) async {
  final home = tester.element(find.byType(HomeScreen, skipOffstage: false));
  Navigator.of(home).popUntil((route) => route.isFirst);
  ProviderScope.containerOf(home).bumpRefresh();
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tester.tap(find.byTooltip('Udhaar wasooli'));
  await tester.pumpAndSettle();
}

Future<void> _tapContaining(WidgetTester tester, String text) async {
  final target = find.textContaining(text).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Every Text still inside the 360dp screen it was drawn on (as
/// large_text_test checks it).
void _expectNothingOffScreen(WidgetTester tester) {
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
      reason: '"${(element.widget as Text).data}" runs off the screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5));
  }
}

Future<void> _loadRealFont() async {
  for (final path in [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];
  final texts = <String>[];

  void clear() {
    paths.clear();
    texts.clear();
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
