part of 'app_services.dart';

/// How this shop reports to FBR (M19). Kept in settings, inside the
/// encrypted books, and carried to the shop's other phones by sync.
final class FbrSettings {
  const FbrSettings({
    this.enabled = false,
    this.sandbox = true,
    this.baseUrl = '',
    this.token = '',
    this.sinceUtcMillis,
    this.raw = const {},
  });

  /// Every `fbr.` row as it is stored, for what the queue keeps about
  /// itself (M59: when FBR went out of reach and came back).
  final Map<String, String> raw;

  final bool enabled;

  /// FBR's test gateway rather than the real one.
  final bool sandbox;

  /// A licensed integrator's or proxy's address; empty for FBR's own.
  final String baseUrl;
  final String token;

  /// When reporting began: bills made before it are never sent.
  final int? sinceUtcMillis;
}

/// A bill on its way to FBR, or already there.
final class FbrBill {
  const FbrBill({
    required this.documentId,
    required this.docNo,
    required this.madeAtUtc,
    required this.status,
    this.fbrInvoiceNo,
    this.error,
    this.connectionBackAtUtc,
  });

  final String documentId;
  final String docNo;
  final DateTime madeAtUtc;

  /// The first time FBR answered anything after this bill was made (M59):
  /// when, for Rule 150XC, the connection came back. Null while FBR has not
  /// been heard from since.
  final DateTime? connectionBackAtUtc;

  /// Made while FBR could not be reached, and not answered for yet: issued
  /// in offline mode, and printed so (Rule 150XC, M59).
  bool get isOffline => status == 'pending';

  /// Still unsent 24 hours after the connection came back (Rule 150XC, M59).
  bool isOfflineOverdue(DateTime nowUtc) => offlineOverdue(
    status: status,
    connectionBackAtUtc: connectionBackAtUtc,
    nowUtc: nowUtc,
  );

  /// `pending`, `posted` or `rejected`.
  final String status;
  final String? fbrInvoiceNo;
  final String? error;

  /// Past FBR's 72 hours and still not accepted.
  bool isLate(DateTime nowUtc) =>
      status != 'posted' &&
      nowUtc.difference(madeAtUtc) > const Duration(hours: 72);
}

/// What one pass over the queue did.
typedef FbrSendReport = ({int posted, int rejected, int waiting});

/// Bills issued in offline mode, and those past Rule 150XC's 24 hours
/// (M59): what the FBR screen and Home say about the queue.
final class FbrOfflineWatch {
  const FbrOfflineWatch({this.offline = 0, this.overdue = const []});

  static const none = FbrOfflineWatch();

  /// Bills FBR has not answered for yet.
  final int offline;

  /// Bills still unsent 24 hours after the connection came back, oldest
  /// first.
  final List<FbrBill> overdue;
}

/// Reporting bills to FBR's Digital Invoicing gateway.
///
/// Off until the owner turns it on, and only for a shop registered for
/// sales tax. A bill made while it is on is marked pending the moment it
/// is saved and sent when FBR can be reached; FBR's number and a QR of it
/// go on the receipt once it answers. Nothing is sent for a bill made
/// before it was turned on.
final class FbrServices {
  FbrServices._(this._app);

  final AppServices _app;

  /// How a gateway is made from the settings. Replaced in tests with a
  /// stand-in for FBR.
  FbrGateway Function(FbrSettings settings) gatewayFor = (s) =>
      FbrClient(token: s.token, sandbox: s.sandbox, baseUrl: s.baseUrl);

  static const _keys = (
    enabled: 'fbr.enabled',
    sandbox: 'fbr.sandbox',
    baseUrl: 'fbr.base_url',
    token: 'fbr.token',
    since: 'fbr.since',
    // M59: when FBR was first found out of reach, and when it was next
    // heard from -- the "restoration" Rule 150XC counts 24 hours from.
    // Written only when the state changes, never on every pass.
    offlineSince: 'fbr.offline_since',
    backAt: 'fbr.back_at',
  );

  ActorContext _actor() {
    final id = _app._identity;
    if (id == null) throw StateError('No shop yet.');
    return ActorContext(
      firmId: id.firmId,
      userId: id.userId,
      deviceId: id.deviceId,
      startedAtUtc: _app.clock.nowUtc(),
    );
  }

  Future<FbrSettings> settings() async {
    final id = _app._identity;
    if (id == null) return const FbrSettings();
    final rows = await _app.database
        .customSelect(
          'SELECT setting_key, setting_value FROM settings WHERE firm_id = ? '
          "AND setting_key LIKE 'fbr.%' AND deleted_at_utc IS NULL",
          variables: [Variable<String>(id.firmId)],
        )
        .get();
    final v = {
      for (final r in rows)
        r.read<String>('setting_key'): r.read<String>('setting_value'),
    };
    return FbrSettings(
      enabled: v[_keys.enabled] == '1',
      sandbox: v[_keys.sandbox] != '0',
      baseUrl: v[_keys.baseUrl] ?? '',
      token: v[_keys.token] ?? '',
      sinceUtcMillis: int.tryParse(v[_keys.since] ?? ''),
      raw: v,
    );
  }

  /// Saves how the shop reports. Owner or manager; only a registered shop
  /// can turn it on, and it needs a token to.
  Future<void> save(FbrSettings settings) async {
    _app.require(Permission.settings);
    final firm = await _app.queries.currentFirm();
    if (settings.enabled) {
      _app.plans.require(PlanFeature.fbr);
      if (firm == null || !firm.isSalesTaxRegistered) {
        throw const PermissionDenied(
          Permission.settings,
          'Only a shop registered for sales tax reports to FBR. Turn that on '
          'in Tax first.',
        );
      }
      if (settings.token.trim().isEmpty) {
        throw const PermissionDenied(
          Permission.settings,
          'FBR needs the token PRAL issued for this shop.',
        );
      }
    }
    final before = await this.settings();
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      Future<void> put(String key, String value) async {
        final held = await tx.selectOne(
          'SELECT id, setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          [actor.firmId, key],
        );
        if (held == null) {
          await tx.insert('settings', {
            'setting_key': key,
            'setting_value': value,
          });
        } else if (held.read<String>('setting_value') != value) {
          await tx.update('settings', held.read<String>('id'), {
            'setting_value': value,
          });
        }
      }

      await put(_keys.enabled, settings.enabled ? '1' : '0');
      await put(_keys.sandbox, settings.sandbox ? '1' : '0');
      await put(_keys.baseUrl, settings.baseUrl.trim());
      await put(_keys.token, settings.token.trim());
      if (settings.enabled && before.sinceUtcMillis == null) {
        await put(_keys.since, '${actor.epochMillis}');
      }
      tx.audit(
        action: 'FBR_SETTINGS',
        entityTable: 'firms',
        entityId: actor.firmId,
        summary: settings.enabled
            ? 'Reporting to FBR (${settings.sandbox ? 'sandbox' : 'live'})'
            : 'Not reporting to FBR',
      );
    });
  }

  /// Whether a bill made now would go to FBR: the shop reports, on a plan
  /// that reports.
  ///
  /// The counter asks this before it offers a loose line (M37): FBR wants
  /// every line's HS code, and a line with no item has none.
  Future<bool> reportsSales() async =>
      (await settings()).enabled && _app.plans.has(PlanFeature.fbr);

  /// Marks a bill just saved as waiting for FBR, when the shop reports.
  /// The receipt then says so until FBR has answered.
  Future<void> afterSale(String documentId) async {
    final s = await settings();
    if (!s.enabled || !_app.plans.has(PlanFeature.fbr)) return;
    await _app._runner.run(_actor(), (tx) async {
      await tx.update('documents', documentId, {'fbr_status': 'pending'});
    });
  }

  /// Marks goods a customer brought back as a credit note waiting for FBR
  /// (M28), when the bill they came off was reported. A return against a
  /// bill made before reporting began is not FBR's to hear about.
  Future<void> afterReturn(String returnDocumentId) async {
    final s = await settings();
    if (!s.enabled || !_app.plans.has(PlanFeature.fbr)) return;
    final original = await _app.database
        .customSelect(
          'SELECT d.fbr_status FROM doc_links l '
          'JOIN documents d ON d.id = l.from_document_id '
          "WHERE l.to_document_id = ? AND l.link_type = 'returns' "
          'AND l.deleted_at_utc IS NULL',
          variables: [Variable<String>(returnDocumentId)],
        )
        .getSingleOrNull();
    if (original?.readNullable<String>('fbr_status') == null) return;
    await _app._runner.run(_actor(), (tx) async {
      await tx.update('documents', returnDocumentId, {'fbr_status': 'pending'});
    });
  }

  /// Every bill (and credit note) made since reporting began, newest first;
  /// with [waitingOnly], only those FBR has not answered for (M59).
  Future<List<FbrBill>> bills({
    int limit = 100,
    bool waitingOnly = false,
  }) async {
    final id = _app._identity;
    final s = await settings();
    if (id == null || s.sinceUtcMillis == null) return const [];
    final rows = await _app.database
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.created_at_utc, d.fbr_status,
                 d.fbr_invoice_no, d.fbr_error,
                 -- M59: for a bill still waiting, the first bill FBR
                 -- numbered after it was made: FBR was reachable then,
                 -- whatever this bill says. Asked only of the waiting, and
                 -- through the FBR index, so the list stays quick.
                 CASE WHEN COALESCE(d.fbr_status, 'pending') = 'pending'
                   THEN (SELECT MIN(o.fbr_posted_at_utc) FROM documents o
                          WHERE o.firm_id = d.firm_id
                            AND o.fbr_status = 'posted'
                            AND o.fbr_posted_at_utc >= d.created_at_utc)
                 END AS answered_after
          FROM documents d
          WHERE d.firm_id = ?
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND (d.doc_type = 'sale_invoice' OR d.fbr_status IS NOT NULL)
            AND d.deleted_at_utc IS NULL AND d.created_at_utc >= ?
            ${waitingOnly ? "AND d.fbr_status = 'pending'" : ''}
          -- Newest first; within one moment a credit note after its bill.
          ORDER BY d.created_at_utc DESC,
                   CASE d.doc_type WHEN 'sale_return' THEN 0 ELSE 1 END
          LIMIT ?
          ''',
          variables: [
            Variable<String>(id.firmId),
            Variable<int>(s.sinceUtcMillis!),
            Variable<int>(limit),
          ],
        )
        .get();
    final backAt = _utcOrNull(s.raw[_keys.backAt]);
    return [for (final r in rows) _billFrom(r, backAt)];
  }

  static FbrBill _billFrom(QueryRow r, DateTime? backAt) {
    final made = DateTime.fromMillisecondsSinceEpoch(
      r.read<int>('created_at_utc'),
      isUtc: true,
    );
    return FbrBill(
      documentId: r.read<String>('id'),
      docNo: r.read<String>('doc_no'),
      madeAtUtc: made,
      status: r.readNullable<String>('fbr_status') ?? 'pending',
      fbrInvoiceNo: r.readNullable<String>('fbr_invoice_no'),
      error: r.readNullable<String>('fbr_error'),
      connectionBackAtUtc: connectionBackFor(
        madeAtUtc: made,
        answeredAtUtc: [
          _utcOrNull('${r.readNullable<int>('answered_after') ?? ''}'),
          backAt,
        ],
      ),
    );
  }

  /// Bills issued in offline mode, and those past Rule 150XC's 24 hours
  /// (M59). Nothing for a shop that does not report.
  Future<FbrOfflineWatch> offlineWatch() async {
    if (_app._identity == null || !(await settings()).enabled) {
      return FbrOfflineWatch.none;
    }
    final now = _app.clock.nowUtc();
    // Read on Home after every bill, so only the waiting bills, through
    // the partial index on fbr_status: a shop with fifty thousand numbered
    // bills reads the handful still waiting.
    final waiting = await bills(limit: 1000, waitingOnly: true);
    return FbrOfflineWatch(
      offline: waiting.length,
      overdue: [
        for (final b in waiting.reversed)
          if (b.isOfflineOverdue(now)) b,
      ],
    );
  }

  static DateTime? _utcOrNull(String? millis) =>
      switch (int.tryParse(millis ?? '')) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        null => null,
      };

  /// FBR answered (M59). If it had been out of reach, the connection is
  /// back from now, and Rule 150XC's 24 hours start.
  Future<void> _heardFromFbr() async {
    final held = (await settings()).raw;
    if ((held[_keys.offlineSince] ?? '').isEmpty) return;
    await _putSettings({
      _keys.backAt: '${_app.clock.nowUtc().millisecondsSinceEpoch}',
      _keys.offlineSince: '',
    });
  }

  /// FBR could not be reached (M59): noted once, when it first happens.
  Future<void> _outOfReach() async {
    final held = (await settings()).raw;
    if ((held[_keys.offlineSince] ?? '').isNotEmpty) return;
    await _putSettings({
      _keys.offlineSince: '${_app.clock.nowUtc().millisecondsSinceEpoch}',
    });
  }

  /// Writes the queue's own rows (M59). Each has an id worked out from the
  /// shop's and the key, as the shelf rule's has (M53): two counters that
  /// both find FBR out of reach while apart write one row twice, and the
  /// merge keeps the later, where two fresh ids would clash on the key.
  Future<void> _putSettings(Map<String, String> values) =>
      _app._runner.run(_actor(), (tx) async {
        for (final MapEntry(:key, :value) in values.entries) {
          final held = await tx.selectOne(
            'SELECT id, setting_value FROM settings WHERE firm_id = ? '
            'AND setting_key = ? AND deleted_at_utc IS NULL',
            [tx.actor.firmId, key],
          );
          if (held == null) {
            await tx.insert('settings', {
              'setting_key': key,
              'setting_value': value,
            }, id: '$key-${tx.actor.firmId}');
          } else if (held.read<String>('setting_value') != value) {
            await tx.update('settings', held.read<String>('id'), {
              'setting_value': value,
            });
          }
        }
      });

  /// Sends every bill still waiting. Never throws: FBR being out of reach
  /// is the normal state of a shop's connection, not an error.
  Future<FbrSendReport> sendPending() async {
    final s = await settings();
    if (!s.enabled ||
        _app._identity == null ||
        !_app.plans.has(PlanFeature.fbr)) {
      return (posted: 0, rejected: 0, waiting: 0);
    }
    final gateway = gatewayFor(s);
    var posted = 0;
    var rejected = 0;
    var waiting = 0;
    // M59: whether FBR has answered anything in this pass yet.
    var heard = false;
    // Oldest first, so a bill reaches FBR before the credit note that
    // takes goods back off it.
    for (final bill in (await bills(limit: 500)).reversed) {
      if (bill.status != 'pending') continue;
      final sale = await _saleFor(bill.documentId);
      if (sale != null &&
          sale.isCreditNote &&
          (sale.referenceFbrNo ?? '').isEmpty) {
        // The bill it credits has not been numbered by FBR yet; it waits.
        waiting++;
        continue;
      }
      final problems = sale == null ? ['The bill is gone.'] : fbrProblems(sale);
      // M59: a bill refused here never reached FBR, so says nothing about
      // whether FBR can be reached.
      final askedFbr = problems.isEmpty;
      final FbrOutcome outcome = problems.isNotEmpty
          ? FbrRejected(problems.first.split(':').first, problems.join('\n'))
          : await gateway.post(fbrPayload(sale!));
      if (askedFbr && outcome is! FbrTryLater && !heard) {
        heard = true;
        await _heardFromFbr();
      }
      switch (outcome) {
        case FbrPosted(:final fbrInvoiceNo):
          posted++;
          await _record(bill.documentId, {
            'fbr_status': 'posted',
            'fbr_invoice_no': fbrInvoiceNo,
            'fbr_error': null,
            'fbr_posted_at_utc': _app.clock.nowUtc().millisecondsSinceEpoch,
          });
        case FbrRejected(:final code, :final message):
          rejected++;
          final advice = fbrAdvice(code);
          await _record(bill.documentId, {
            'fbr_status': 'rejected',
            'fbr_error': advice.isEmpty ? message : '$message\n$advice',
          });
        case FbrTryLater(:final reason):
          waiting++;
          await _record(bill.documentId, {
            'fbr_status': 'pending',
            'fbr_error': reason,
          });
          await _outOfReach();
          // FBR is out of reach; the rest would only wait the same way.
          return (posted: posted, rejected: rejected, waiting: waiting);
      }
    }
    return (posted: posted, rejected: rejected, waiting: waiting);
  }

  /// Puts a refused bill back in the queue, once whatever FBR refused it
  /// for has been put right.
  Future<void> retry(String documentId) async {
    _app.require(Permission.settings);
    await _record(documentId, {'fbr_status': 'pending', 'fbr_error': null});
  }

  Future<void> _record(String documentId, Map<String, Object?> values) =>
      _app._runner.run(_actor(), (tx) async {
        await tx.update('documents', documentId, values);
      });

  /// A bill as FBR wants it, from the books.
  Future<FbrSale?> _saleFor(String documentId) async {
    final id = _app._identity!;
    final doc = await _app.database
        .customSelect(
          '''
          SELECT d.doc_no, d.doc_date_utc, d.doc_type, f.ntn AS seller_ntn,
                 f.strn AS seller_strn, d.party_ntn_snapshot,
                 -- M59: the name the bill was made out to, which for a
                 -- walk-in over Rs 100,000 is the one the counter asked
                 -- for; a customer in the khata as they were named then.
                 COALESCE(NULLIF(TRIM(d.party_name_snapshot), ''), p.name)
                   AS buyer,
                 p.ntn AS party_ntn, p.buyer_registration_type,
                 (SELECT o.fbr_invoice_no FROM doc_links l
                  JOIN documents o ON o.id = l.from_document_id
                  WHERE l.to_document_id = d.id AND l.link_type = 'returns'
                    AND l.deleted_at_utc IS NULL) AS credits_fbr_no
          FROM documents d
          JOIN firms f ON f.id = d.firm_id
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.id = ? AND d.firm_id = ?
          ''',
          variables: [
            Variable<String>(documentId),
            Variable<String>(id.firmId),
          ],
        )
        .getSingleOrNull();
    if (doc == null) return null;
    final lines = await _app.database
        .customSelect(
          '''
          SELECT l.id, l.item_name_snapshot, l.item_code_snapshot,
                 COALESCE(l.hs_code_snapshot,
                          (SELECT i.hs_code FROM items i WHERE i.id = l.item_id))
                   AS hs_code_snapshot,
                 l.qty_thousandths, l.unit_code_snapshot,
                 l.rate_milli_paisa, l.taxable_paisa, l.discount_paisa,
                 l.line_total_paisa,
                 COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id AND t.tax_kind = 'sales_tax'
                     AND t.deleted_at_utc IS NULL), 0) AS st,
                 COALESCE((SELECT MAX(t.rate_bp) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id AND t.tax_kind = 'sales_tax'
                     AND t.deleted_at_utc IS NULL), 0) AS st_bp,
                 COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id AND t.tax_kind = 'further_tax'
                     AND t.deleted_at_utc IS NULL), 0) AS ft,
                 COALESCE((SELECT MAX(t.rate_bp) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id AND t.tax_kind = 'further_tax'
                     AND t.deleted_at_utc IS NULL), 0) AS ft_bp
          FROM document_lines l
          WHERE l.document_id = ? AND l.deleted_at_utc IS NULL
          ORDER BY l.line_no
          ''',
          variables: [Variable<String>(documentId)],
        )
        .get();
    final registered =
        doc.readNullable<String>('buyer_registration_type') == 'registered';
    final isReturn = doc.read<String>('doc_type') == 'sale_return';
    return FbrSale(
      invoiceType: isReturn ? 'Credit Note' : 'Sale Invoice',
      referenceFbrNo: isReturn
          ? doc.readNullable<String>('credits_fbr_no') ?? ''
          : null,
      invoiceRef: doc.read<String>('doc_no'),
      dateUtc: DateTime.fromMillisecondsSinceEpoch(
        doc.read<int>('doc_date_utc'),
        isUtc: true,
      ),
      sellerNtn: doc.readNullable<String>('seller_ntn'),
      sellerStrn: doc.readNullable<String>('seller_strn'),
      buyerNtn:
          doc.readNullable<String>('party_ntn_snapshot') ??
          doc.readNullable<String>('party_ntn'),
      buyerName: doc.readNullable<String>('buyer'),
      buyerRegistered: registered,
      lines: [
        for (final l in lines)
          FbrLine(
            itemCode: l.readNullable<String>('item_code_snapshot'),
            description: l.read<String>('item_name_snapshot'),
            hsCode: l.readNullable<String>('hs_code_snapshot'),
            qty: Qty.raw(l.read<int>('qty_thousandths')),
            unit: l.read<String>('unit_code_snapshot'),
            unitPrice: Money.paisa(
              (l.read<int>('rate_milli_paisa') + 500) ~/ 1000,
            ),
            value: Money.paisa(l.read<int>('taxable_paisa')),
            salesTaxBp: l.read<int>('st_bp'),
            salesTax: Money.paisa(l.read<int>('st')),
            furtherTaxBp: l.read<int>('ft_bp'),
            furtherTax: Money.paisa(l.read<int>('ft')),
            discount: Money.paisa(l.read<int>('discount_paisa')),
            total: Money.paisa(l.read<int>('line_total_paisa')),
          ),
      ],
    );
  }
}

/// Why a bill cannot be made while the shop reports to FBR, in words.
final class FbrRefusedLine implements Exception {
  const FbrRefusedLine(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Sales on a shop that reports to FBR: a loose line is refused (M37).
///
/// FBR's Digital Invoicing wants an HS code on every line, and a line with
/// no item behind it has none. Sent anyway, the bill is refused by the
/// gateway hours later, after the customer has left with the paper, and the
/// shop is left holding a reported sale it cannot report. A default HS code
/// stamped on every loose line was the other way out, and it was not taken:
/// it would tell FBR that a kilo of onions and a bicycle repair were the
/// same goods at the same rate, and that is a misdeclaration with the
/// shop's NTN on it. So the counter says so before the bill is made, and
/// this says it again for anything that gets past the counter — a bill
/// half-rung before reporting was turned on, and restored after.
///
/// A shop that does not report, or whose plan has lapsed (its bills are not
/// sent either), sells loose lines as any shop does.
final class _FbrSales implements SaleWriter {
  _FbrSales(this._inner, this._app);

  final SaleWriter _inner;
  final AppServices _app;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(actor, (w) => body(_FbrSaleContext(w, _app)));
}

final class _FbrSaleContext implements SaleWriteContext {
  _FbrSaleContext(this._inner, this._app);

  final SaleWriteContext _inner;
  final AppServices _app;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      _inner.taxContextFor(partyId);

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) =>
      _inner.averageCostFor(itemIds);

  @override
  Future<Map<String, String>> ledgerAccountsFor(
    Iterable<String> paymentAccountIds,
  ) => _inner.ledgerAccountsFor(paymentAccountIds);

  @override
  Future<ChallanGoods?> deliveredOn(String documentId) =>
      _inner.deliveredOn(documentId);

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    if (posting.lines.any((l) => l.itemId == null) &&
        await _app.fbr.reportsSales()) {
      throw const FbrRefusedLine(
        'This shop reports its bills to FBR, and FBR needs the HS code of '
        'every line. A loose line has none: make it an item with its HS '
        'code, or take it off the bill.',
      );
    }
    return _inner.apply(posting);
  }
}
