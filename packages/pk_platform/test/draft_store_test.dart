import 'dart:io';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Where a half-finished bill waits out a process kill.
///
/// Transsion — Infinix, Tecno, itel — is about 44% of the Pakistani market at
/// the bottom end, and its ROMs ship Phone Master with a Boost button that
/// force-stops backgrounded apps. A cashier with fifteen lines on a bill who
/// switches to WhatsApp to check a price and comes back to an empty cart
/// re-scans the lot with the customer standing there.
///
/// Flutter's own state restoration does not cover it: it rides on Android's
/// `savedInstanceState`, which is tied to the task record, and a force-stop
/// takes the task record with it — as does swiping the app off Recents, and as
/// does a reboot. It survives a low-memory reclaim and nothing else, which is
/// the case a shopkeeper is least likely to notice.
void main() {
  group('the draft on disk', () {
    late Directory dir;
    late FileDraftStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('bl_draft');
      store = FileDraftStore(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('comes back exactly as it went in', () async {
      await store.write(cartDraftSlot, 'the bill');
      expect(await store.read(cartDraftSlot), 'the bill');
    });

    test('an empty slot is not an error', () async {
      expect(await store.read(cartDraftSlot), isNull);
      await store.clear(cartDraftSlot);
      expect(await store.read(cartDraftSlot), isNull);
    });

    test('the last write wins, and only one file is left behind', () async {
      // Four quick taps on the quantity stepper. The store coalesces: a write
      // in flight holds the slot and the newest pending contents replace any
      // older pending contents, so this costs one or two writes rather than
      // four, and the one that lands is the last thing the cashier did.
      await Future.wait([
        store.write(cartDraftSlot, 'one'),
        store.write(cartDraftSlot, 'two'),
        store.write(cartDraftSlot, 'three'),
        store.write(cartDraftSlot, 'four'),
      ]);

      expect(await store.read(cartDraftSlot), 'four');
      expect(
        dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last),
        ['draft_cart.json'],
        reason: 'a .tmp left behind is a rename that did not happen',
      );
    });

    test('a half-written file is never what a reader sees', () async {
      // The store writes beside the target and renames over it, so a kill
      // landing mid-write leaves the previous draft intact rather than a
      // truncated one. Half a cart is worse than none: the cashier cannot tell
      // it apart from a whole one by looking, and the stock that is not on it
      // walks out of the shop.
      await store.write(cartDraftSlot, '{"v":1,"lines":[{"itemId":"a"}]}');

      final temp = File(
        '${dir.path}${Platform.pathSeparator}draft_cart.json.tmp',
      )..writeAsStringSync('{"v":1,"lines":[{"itemId":"a","na');

      expect(
        await store.read(cartDraftSlot),
        '{"v":1,"lines":[{"itemId":"a"}]}',
        reason: 'a reader must never be handed the file being written',
      );
      temp.deleteSync();
    });

    test('a slot name that is not a slot name is refused', () async {
      // Nothing builds one from user input today. This is here so it stays
      // true when hold-bill arrives and slots start carrying a counter name.
      expect(
        () => store.write('../../etc/passwd', 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
