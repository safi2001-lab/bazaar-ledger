part of 'app_services.dart';

/// Chasing udhaar: due dates and promises (M38), and reminders in each
/// customer's language with a log of who was sent what (M39).
///
/// Kept in its own part, reached as `services.udhaar`, so the khata's
/// chasing grows here without every milestone after it editing the same
/// lines of [AppServices].
///
/// Reading is open to whoever can open the khata, which is every role: a
/// counter boy asked "Aslam ne kab dene ka kaha tha?" should be able to
/// answer. Writing a promise takes the right to take payments, because a
/// promise is what is written down instead of a payment.
final class UdhaarServices {
  UdhaarServices._(this._app);

  final AppServices _app;

  /// Due dates, ageing by due date, the chase list and promises.
  ///
  /// A later reports milestone plugs the due-date ageing into its registry
  /// from here: [UdhaarQueries.dueAging] is the shop's figure, by bucket,
  /// and [UdhaarQueries.dueParties] the customers behind it.
  UdhaarQueries get queries => DriftUdhaarQueries(_app.database);

  UdhaarStore get _store => DriftUdhaarStore(() => _app._runner, _app.ids);

  /// The shop's business day, as the khata reads due dates against it.
  String get today => BusinessDate.now(_app.clock).value;

  /// Records what a customer said they would pay, and when.
  Future<String> recordPromise(PromiseDraft draft) {
    _app.require(Permission.takePayments);
    return _store.recordPromise(_app.actorNow(), draft);
  }

  /// Takes a promise off. It stays in the customer's history, marked.
  Future<void> withdrawPromise(String promiseId) {
    _app.require(Permission.takePayments);
    return _store.withdrawPromise(_app.actorNow(), promiseId);
  }

  // -------------------------------------------------------------------------
  // Reminders (M39)
  // -------------------------------------------------------------------------

  /// The words [language]'s reminders go out in: the owner's, or the
  /// shop's own until the owner writes theirs.
  Future<String> reminderTemplate(ReminderLanguage language) async {
    final firm = await _app.queries.currentFirm();
    final own = firm == null
        ? null
        : await queries.customReminderTemplate(firm.id, language);
    return own ?? defaultReminderTemplate(language);
  }

  /// Keeps the owner's words for [language]. The owner's call: it is what
  /// every customer reading that language is sent in the shop's name.
  Future<void> saveReminderTemplate(ReminderLanguage language, String text) {
    _app.require(Permission.settings);
    return _store.saveReminderTemplate(_app.actorNow(), language, text);
  }

  /// Puts the shop's own words back for [language].
  Future<void> resetReminderTemplate(ReminderLanguage language) =>
      saveReminderTemplate(language, '');

  /// One customer's reminder language and opt-out.
  Future<ReminderPrefs> reminderPrefs(String partyId) async {
    final firm = await _app.queries.currentFirm();
    if (firm == null) return ReminderPrefs.standard;
    return queries.reminderPrefs(firm.id, partyId);
  }

  /// Keeps one customer's reminder language and opt-out. Whoever keeps the
  /// khata may: a customer who says "Urdu mein bhejein" or "message na
  /// karein" says it at the counter.
  Future<void> setReminderPrefs(String partyId, ReminderPrefs prefs) {
    _app.require(Permission.takePayments);
    return _store.setReminderPrefs(_app.actorNow(), partyId, prefs);
  }

  /// [partyId]'s reminder, written: what they owe, since when and due when,
  /// in their language, from the shop's template, with the shop's payment
  /// details. Null when they owe nothing (or are not in the khata), because
  /// a reminder to somebody who paid last week is how a shop loses them.
  Future<ReminderReady?> reminderFor(String partyId) async {
    final firm = await _app.queries.currentFirm();
    if (firm == null) return null;
    final party = await _app.queries.partyById(firm.id, partyId);
    if (party == null || !party.balance.isPositive) return null;
    final prefs = await queries.reminderPrefs(firm.id, partyId);
    final bills = await queries.billsDue(
      firm.id,
      partyId,
      asOfDateLocal: today,
    );
    // Oldest first, so the first bill is the one they have sat on longest
    // and its due date the one that passed first.
    final oldest = bills.firstOrNull;
    final template = await reminderTemplate(prefs.language);
    final message = fillReminder(
      template,
      ReminderFacts(
        name: party.name,
        amount: party.balance,
        shop: firm.name,
        dueDateLocal: oldest?.dueDateLocal,
        oldestBillDateLocal: oldest?.billDateLocal,
        shopPhone: firm.phone,
        wallet: walletLine(
          raastAlias: firm.raastAlias,
          bankName: firm.bankName,
          accountTitle: firm.bankAccountTitle,
          iban: firm.bankIban,
        ),
      ),
      prefs.language,
    );
    return ReminderReady(
      party: party,
      message: message,
      prefs: prefs,
      whatsappNumber: whatsappNumber(party.phone),
    );
  }

  /// Writes a reminder into [partyId]'s log, as sent now by whoever is
  /// signed in.
  Future<void> recordReminderSent(
    String partyId, {
    required ReminderChannel channel,
    required ReminderLanguage language,
    required Money amount,
  }) {
    _app.require(Permission.takePayments);
    return _store.recordReminderSent(
      _app.actorNow(),
      partyId,
      channel: channel,
      language: language,
      amount: amount,
    );
  }

  /// The reminders sent to [partyId], newest first.
  Future<List<ReminderSent>> remindersSent(String partyId) async {
    final firm = await _app.queries.currentFirm();
    if (firm == null) return const [];
    return queries.remindersSent(firm.id, partyId);
  }
}
