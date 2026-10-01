part of 'app_services.dart';

/// Which plan this phone is on, and the checks that hold paid features to
/// it (M21).
///
/// The plan belongs to the Google account that paid for it, not to the
/// books, so it is kept beside the books on this phone (in the draft store)
/// rather than in them: a backup restored on another phone, or a counter
/// that syncs, does not carry somebody else's subscription.
///
/// What is kept is the purchase exactly as Google Play signed it, and the
/// signature is checked again every time the app opens, against the public
/// key built into the app. Editing the stored purchase gains nothing. Play
/// is asked again whenever it can be reached; a plan it has not confirmed
/// for [planOfflineGrace] lapses to free. With no key in the build, nothing
/// verifies and every phone is free: it never falls open.
final class PlanServices {
  PlanServices._(this._app);

  final AppServices _app;

  static const _slot = 'plan.purchase';
  static const _testSlot = 'plan.test';

  /// The package name a purchase must be for.
  static const packageName = 'pk.bazaarledger';

  /// The licensing key purchases are checked against. Replaced in tests.
  String publicKey = AppConfig.playBillingPublicKey;

  /// Whether the plan can be picked by hand, for trying the app. Never in a
  /// release build.
  bool allowTestPlans = !kReleaseMode;

  Plan _verified = Plan.free;
  Plan? _test;
  Plan? _pinned;

  /// Fixes the plan for a suite that is not about plans; null lets the
  /// purchase decide again.
  void pinForTests(Plan? plan) => _pinned = plan;

  /// The plan in force.
  Plan get plan => _pinned ?? (allowTestPlans ? _test : null) ?? _verified;

  /// What Play has verified, whatever a test switch says.
  Plan get purchased => _verified;

  /// The plan picked by hand on a test build, if any.
  Plan? get testPlan => allowTestPlans ? _test : null;

  bool has(PlanFeature feature) => plan.covers(feature.plan);

  /// Throws [PlanRequired] unless the plan includes [feature].
  void require(PlanFeature feature) {
    if (has(feature)) return;
    throw PlanRequired(
      feature.plan,
      '${_label(feature)} needs the ${_planName(feature.plan)} plan. '
      'This shop is on ${_planName(plan)}.',
    );
  }

  /// Throws unless the plan allows one more firm than [existing].
  void requireFirmSlot(int existing) {
    final cap = plan.firms;
    if (cap == null || existing < cap) return;
    throw PlanRequired(
      _next(plan, (p) => p.firms == null || p.firms! > existing),
      'The ${_planName(plan)} plan keeps $cap '
      '${cap == 1 ? 'firm' : 'firms'} on a phone.',
    );
  }

  /// Throws unless the plan allows one more person than [existing].
  void requireUserSlot(int existing) {
    final cap = plan.users;
    if (cap == null || existing < cap) return;
    throw PlanRequired(
      _next(plan, (p) => p.users == null || p.users! > existing),
      cap == 1
          ? 'Staff with their own sign-in need the Gold plan.'
          : 'The ${_planName(plan)} plan has $cap people; more need '
                'Platinum.',
    );
  }

  static Plan _next(Plan from, bool Function(Plan) fits) =>
      Plan.values.where((p) => p.index > from.index && fits(p)).firstOrNull ??
      Plan.platinum;

  static String _planName(Plan p) =>
      '${p.name[0].toUpperCase()}${p.name.substring(1)}';

  static String _label(PlanFeature f) => switch (f) {
    PlanFeature.noWatermark => 'Bills without the "made with" line',
    PlanFeature.autoDriveBackup => 'The daily Google Drive backup',
    PlanFeature.cheques => 'Recording post-dated cheques',
    PlanFeature.priceLists => 'Wholesale and VIP prices',
    PlanFeature.accountingReports =>
      'Profit and loss, balance sheet and tax '
          'reports',
    PlanFeature.tracking => 'Batch, expiry and serial tracking',
    PlanFeature.scaleLabels => 'Weighing-scale labels',
    PlanFeature.godowns => 'Godowns and stock transfers',
    PlanFeature.lanSync => 'More than one counter on wi-fi',
    PlanFeature.fbr => 'Reporting bills to FBR',
    PlanFeature.manufacturing => 'Recipes and production runs',
    PlanFeature.vans => 'Van sales',
  };

  /// Reads the stored purchase and checks it again. Called when the books
  /// open, and when the app comes back to the front.
  Future<void> load() async {
    final test = await _app.drafts.read(_testSlot);
    _test = test == null ? null : Plan.parse(test);
    final held = await _app.drafts.read(_slot);
    _verified = _decide(held);
  }

  Plan _decide(String? held) {
    if (held == null) return Plan.free;
    final Object? stored;
    try {
      stored = jsonDecode(held);
    } on FormatException {
      return Plan.free;
    }
    if (stored is! Map<String, Object?>) return Plan.free;
    final json = stored['json'], sig = stored['signature'];
    final at = stored['confirmed'];
    if (json is! String || sig is! String || at is! int) return Plan.free;
    return planFor(
      purchase: readPlayPurchase(json),
      signatureValid: PlaySignature.verify(
        publicKeyBase64: publicKey,
        signedData: json,
        signatureBase64: sig,
      ),
      confirmedUtc: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      nowUtc: _app.clock.nowUtc(),
      packageName: packageName,
    );
  }

  /// What Play reported this phone holds, each purchase as Play signed it.
  /// The best plan that verifies is kept; an empty list, from a query that
  /// reached Play, means the subscription has ended. Returns the plan.
  Future<Plan> confirm(
    List<({String json, String signature})> purchases,
  ) async {
    final now = _app.clock.nowUtc().millisecondsSinceEpoch;
    var best = Plan.free;
    String? keep;
    for (final p in purchases) {
      final stored = jsonEncode({
        'json': p.json,
        'signature': p.signature,
        'confirmed': now,
      });
      final plan = _decide(stored);
      if (plan.index > best.index) {
        best = plan;
        keep = stored;
      }
    }
    if (keep == null) {
      await _app.drafts.clear(_slot);
    } else {
      await _app.drafts.write(_slot, keep);
    }
    final before = _verified;
    _verified = best;
    if (before != best && _app._identity != null) {
      await _app._runner.run(_app.actorNow(), (tx) async {
        tx.audit(
          action: 'PLAN_CHANGED',
          entityTable: 'firms',
          entityId: _app._identity!.firmId,
          summary: 'Plan ${before.name} to ${best.name}',
        );
      });
    }
    return best;
  }

  /// A purchase Play has just made: kept if it verifies, together with the
  /// one already held, so buying never loses a plan the phone had.
  Future<Plan> bought(String json, String signature) async {
    final plan = _decide(
      jsonEncode({
        'json': json,
        'signature': signature,
        'confirmed': _app.clock.nowUtc().millisecondsSinceEpoch,
      }),
    );
    if (plan.index <= _verified.index) return _verified;
    return confirm([(json: json, signature: signature)]);
  }

  /// Picks the plan by hand, on a test build only; null goes back to what
  /// was bought.
  Future<void> setTestPlan(Plan? plan) async {
    if (!allowTestPlans) {
      throw StateError('Plans cannot be picked by hand in a release build.');
    }
    _test = plan;
    if (plan == null) {
      await _app.drafts.clear(_testSlot);
    } else {
      await _app.drafts.write(_testSlot, plan.name);
    }
  }
}
