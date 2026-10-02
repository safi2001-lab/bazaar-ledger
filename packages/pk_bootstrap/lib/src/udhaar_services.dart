part of 'app_services.dart';

/// Chasing udhaar: due dates and promises (M38).
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
}
