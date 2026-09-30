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
  });

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
  });

  final String documentId;
  final String docNo;
  final DateTime madeAtUtc;

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
    );
  }

  /// Saves how the shop reports. Owner or manager; only a registered shop
  /// can turn it on, and it needs a token to.
  Future<void> save(FbrSettings settings) async {
    _app.require(Permission.settings);
    final firm = await _app.queries.currentFirm();
    if (settings.enabled) {
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

  /// Marks a bill just saved as waiting for FBR, when the shop reports.
  /// The receipt then says so until FBR has answered.
  Future<void> afterSale(String documentId) async {
    final s = await settings();
    if (!s.enabled) return;
    await _app._runner.run(_actor(), (tx) async {
      await tx.update('documents', documentId, {'fbr_status': 'pending'});
    });
  }

  /// Every bill made since reporting began, newest first.
  Future<List<FbrBill>> bills({int limit = 100}) async {
    final id = _app._identity;
    final s = await settings();
    if (id == null || s.sinceUtcMillis == null) return const [];
    final rows = await _app.database
        .customSelect(
          '''
          SELECT id, doc_no, created_at_utc, fbr_status, fbr_invoice_no,
                 fbr_error
          FROM documents
          WHERE firm_id = ? AND doc_type = 'sale_invoice' AND status = 'posted'
            AND deleted_at_utc IS NULL AND created_at_utc >= ?
          ORDER BY created_at_utc DESC
          LIMIT ?
          ''',
          variables: [
            Variable<String>(id.firmId),
            Variable<int>(s.sinceUtcMillis!),
            Variable<int>(limit),
          ],
        )
        .get();
    return [
      for (final r in rows)
        FbrBill(
          documentId: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          madeAtUtc: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('created_at_utc'),
            isUtc: true,
          ),
          status: r.readNullable<String>('fbr_status') ?? 'pending',
          fbrInvoiceNo: r.readNullable<String>('fbr_invoice_no'),
          error: r.readNullable<String>('fbr_error'),
        ),
    ];
  }

  /// Sends every bill still waiting. Never throws: FBR being out of reach
  /// is the normal state of a shop's connection, not an error.
  Future<FbrSendReport> sendPending() async {
    final s = await settings();
    if (!s.enabled || _app._identity == null) {
      return (posted: 0, rejected: 0, waiting: 0);
    }
    final gateway = gatewayFor(s);
    var posted = 0;
    var rejected = 0;
    var waiting = 0;
    for (final bill in await bills(limit: 500)) {
      if (bill.status != 'pending') continue;
      final sale = await _saleFor(bill.documentId);
      final problems = sale == null ? ['The bill is gone.'] : fbrProblems(sale);
      final FbrOutcome outcome = problems.isNotEmpty
          ? FbrRejected(problems.first.split(':').first, problems.join('\n'))
          : await gateway.post(fbrPayload(sale!));
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
          SELECT d.doc_no, d.doc_date_utc, f.ntn AS seller_ntn,
                 f.strn AS seller_strn, d.party_ntn_snapshot, p.name AS buyer,
                 p.ntn AS party_ntn, p.buyer_registration_type
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
                 l.hs_code_snapshot, l.qty_thousandths, l.unit_code_snapshot,
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
    return FbrSale(
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
