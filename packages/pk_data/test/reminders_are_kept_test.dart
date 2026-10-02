import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Reminder templates, a customer's language and opt-out, and the log of
/// what was sent (M39) — against a real database.
///
/// Templates and preferences are rows in the shop's settings; the log is
/// the audit trail. These prove each goes through the one write path and
/// reads back as it was written, and that the chase list carries both.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftUdhaarQueries udhaar;
  late DriftUdhaarStore store;
  late DriftCatalogueWriter catalogue;
  late ActorContext actor;
  late String aslam;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 1, 4));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    udhaar = DriftUdhaarQueries(db);
    store = DriftUdhaarStore(() => runner, ids);
    catalogue = DriftCatalogueWriter(runner);
    aslam = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Aslam Karyana', creditDays: 7),
    );
    final pcs =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    final rice = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Chawal',
        baseUnitId: pcs,
        saleRate: Rate.rupees(100),
        openingStock: Qty.units(50),
      ),
    );
    await PostSaleUseCase(writer: DriftSaleWriter(runner: runner))(
      firm.actorAt(DateTime.utc(2026, 8, 1, 4)),
      SaleDraft(
        partyId: aslam,
        lines: [
          SaleLineDraft(
            itemId: rice,
            itemName: 'Chawal',
            qty: Qty.units(30),
            baseQty: Qty.units(30),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(100),
          ),
        ],
      ),
    );
  });

  tearDown(() async => db.close());

  group('reminders', () {
    test('a template the owner writes is kept, and the shop words come back '
        'on reset', () async {
      expect(
        await udhaar.customReminderTemplate(firm.firmId, ReminderLanguage.urdu),
        isNull,
      );
      await store.saveReminderTemplate(
        actor,
        ReminderLanguage.urdu,
        '{name} صاحب، {amount} روپے۔',
      );
      expect(
        await udhaar.customReminderTemplate(firm.firmId, ReminderLanguage.urdu),
        '{name} صاحب، {amount} روپے۔',
      );
      // The other languages are untouched.
      expect(
        await udhaar.customReminderTemplate(
          firm.firmId,
          ReminderLanguage.english,
        ),
        isNull,
      );

      await store.saveReminderTemplate(actor, ReminderLanguage.urdu, '');
      expect(
        await udhaar.customReminderTemplate(firm.firmId, ReminderLanguage.urdu),
        isNull,
      );
      // Saving the shop's own words is the same as putting them back.
      await store.saveReminderTemplate(
        actor,
        ReminderLanguage.english,
        defaultReminderTemplate(ReminderLanguage.english),
      );
      expect(
        await udhaar.customReminderTemplate(
          firm.firmId,
          ReminderLanguage.english,
        ),
        isNull,
      );
      final audit = await db
          .customSelect(
            'SELECT action_code FROM audit_log WHERE action_code LIKE '
            "'REMINDER_TEMPLATE_%' ORDER BY at_utc, id",
          )
          .get();
      expect(
        [for (final r in audit) r.read<String>('action_code')],
        [
          'REMINDER_TEMPLATE_SAVED',
          'REMINDER_TEMPLATE_RESET',
          'REMINDER_TEMPLATE_RESET',
        ],
      );
    });

    test('a customer keeps a language and an opt-out, and the chase list '
        'carries them', () async {
      expect(
        await udhaar.reminderPrefs(firm.firmId, aslam),
        ReminderPrefs.standard,
      );
      const urdu = ReminderPrefs(language: ReminderLanguage.urdu);
      await store.setReminderPrefs(actor, aslam, urdu);
      expect(await udhaar.reminderPrefs(firm.firmId, aslam), urdu);

      const off = ReminderPrefs(
        language: ReminderLanguage.urdu,
        optedOut: true,
      );
      await store.setReminderPrefs(actor, aslam, off);
      final list = await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-09-01',
      );
      expect(list.single.prefs, off);
    });

    test('each reminder sent is logged with who, when and how, newest '
        'first, and the chase list knows the last', () async {
      await store.recordReminderSent(
        firm.actorAt(DateTime.utc(2026, 8, 20, 10)),
        aslam,
        channel: ReminderChannel.whatsapp,
        language: ReminderLanguage.romanUrdu,
        amount: const Money.rupees(3000),
      );
      await store.recordReminderSent(
        firm.actorAt(DateTime.utc(2026, 8, 29, 10)),
        aslam,
        channel: ReminderChannel.sms,
        language: ReminderLanguage.urdu,
        amount: const Money.rupees(3000),
      );

      final log = await udhaar.remindersSent(firm.firmId, aslam);
      expect(log, hasLength(2));
      expect(log.first.channel, ReminderChannel.sms);
      expect(log.first.language, ReminderLanguage.urdu);
      expect(log.first.byName, 'Malik Sahib');
      expect(log.first.daysAgo('2026-09-01'), 3);
      expect(log.last.channel, ReminderChannel.whatsapp);

      final list = await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-09-01',
      );
      expect(list.single.lastRemindedAt, DateTime.utc(2026, 8, 29, 10));
      final audit = await db
          .customSelect(
            'SELECT amount_paisa FROM audit_log WHERE action_code = '
            "'REMINDER_SENT'",
          )
          .get();
      expect(audit.first.read<int>('amount_paisa'), 300000);
    });

    test(
      'a reminder for somebody not in the khata is refused in words',
      () async {
        await expectLater(
          store.recordReminderSent(
            actor,
            'nobody',
            channel: ReminderChannel.whatsapp,
            language: ReminderLanguage.english,
            amount: const Money.rupees(1),
          ),
          throwsA(isA<UdhaarRefused>()),
        );
      },
    );
  });
}
