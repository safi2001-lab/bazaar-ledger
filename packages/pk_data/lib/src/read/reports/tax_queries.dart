part of '../drift_report_source.dart';

/// The reads behind the tax reports (M35). Every figure is what the bill
/// recorded when it was made: the tax rows of `document_line_taxes` for a
/// sale or a return, the bill's own columns for a purchase, never anything
/// worked out again at today's rates.
mixin _TaxQueries implements TaxReportSource {
  AppDatabase get _db;

  /// Each line's sales tax and further tax over the period's sales and
  /// returns, one row per line: the tax rows of `document_line_taxes`
  /// summed by kind, with the sales tax's rate and code. Reads `?1` to
  /// `?3` as the firm and the period.
  ///
  /// And the province's tax on a service line (M61), `pt`, with one of its
  /// codes, `pt_code`, to say whose it is: summed apart and never into `st`,
  /// because it is owed to PRA or SRB and not to FBR.
  static const _lineTaxes = '''
    SELECT t.document_line_id,
           SUM(CASE WHEN t.tax_kind = 'sales_tax'
                    THEN t.amount_paisa ELSE 0 END) AS st,
           SUM(CASE WHEN t.tax_kind = 'further_tax'
                    THEN t.amount_paisa ELSE 0 END) AS ft,
           SUM(CASE WHEN t.tax_kind = 'provincial_st'
                    THEN t.amount_paisa ELSE 0 END) AS pt,
           MAX(CASE WHEN t.tax_kind = 'provincial_st' THEN t.tax_code END)
             AS pt_code,
           MAX(CASE WHEN t.tax_kind = 'sales_tax' THEN t.rate_bp END)
             AS st_bp,
           MAX(CASE WHEN t.tax_kind = 'sales_tax' THEN t.tax_code END)
             AS st_code,
           MAX(CASE WHEN t.tax_kind = 'sales_tax' THEN t.base_paisa END)
             AS st_base
    FROM document_line_taxes t
    JOIN documents td ON td.id = t.document_id
    WHERE td.firm_id = ?1
      AND td.doc_type IN ('sale_invoice', 'sale_return')
      AND td.status = 'posted'
      AND td.deleted_at_utc IS NULL
      AND td.doc_date_local BETWEEN ?2 AND ?3
      AND t.deleted_at_utc IS NULL
    GROUP BY t.document_line_id
  ''';

  /// For a tax row of a return line `dl` of return `d`, the same tax on
  /// the line it returns: the return writer records what it gives back as
  /// `ST_RETURN` or `FURTHER_RETURN` at no rate, so the rate and the footing
  /// are read from the sale. [column] is `tax_code` or `rate_bp`; [kind]
  /// the SQL for the tax kind wanted.
  static String _returned(String column, String kind) =>
      '''
    (SELECT ot.$column FROM doc_links rl
      JOIN document_lines ol ON ol.document_id = rl.from_document_id
      JOIN document_line_taxes ot ON ot.document_line_id = ol.id
     WHERE rl.to_document_id = d.id
       AND rl.link_type = 'returns'
       AND rl.deleted_at_utc IS NULL
       AND ol.deleted_at_utc IS NULL
       AND ot.deleted_at_utc IS NULL
       AND ol.item_id = dl.item_id
       AND ot.tax_kind = $kind
     LIMIT 1)''';

  /// The item's tax rule as one of `exempt` or `zero_rated`, from the rule
  /// row it points at or the id itself; null for any other. Reads `i` as
  /// the item and `tr` as its rule.
  static const _untaxedRule = '''
    CASE
      WHEN LOWER(COALESCE(tr.code, i.tax_rule_id, '')) LIKE '%exempt%'
        THEN 'exempt'
      WHEN LOWER(COALESCE(tr.code, i.tax_rule_id, '')) LIKE '%zero%'
        THEN 'zero_rated'
    END
  ''';

  @override
  Future<List<PartyTax>> partyTax(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // A sale's tax from its own tax rows, exactly as the Sales tax report
    // reads it, so the two agree to the paisa; a purchase's from the
    // bill's columns, which is where the purchase writer keeps it.
    final q = _Params(firmId, period);
    final where = _documentWhere(filters, q);
    String taxOf(String kind) =>
        '''
        COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
          WHERE t.document_id = d.id AND t.tax_kind = '$kind'
            AND t.deleted_at_utc IS NULL), 0)''';
    // M61: the value of the bill's service lines the province taxed, which
    // is in the bill's taxable value and is not a supply FBR counts.
    const servicesOf = '''
        COALESCE((SELECT SUM(l.taxable_paisa) FROM document_lines l
          WHERE l.document_id = d.id AND l.deleted_at_utc IS NULL
            AND EXISTS (SELECT 1 FROM document_line_taxes t
                         WHERE t.document_line_id = l.id
                           AND t.tax_kind = 'provincial_st'
                           AND t.deleted_at_utc IS NULL)), 0)''';
    final rows = await _db
        .customSelect(
          '''
          SELECT d.party_id,
                 COALESCE(p.name, MAX(d.party_name_snapshot), '') AS name,
                 COALESCE(MAX(d.party_ntn_snapshot), p.ntn) AS ntn,
                 COALESCE(MAX(d.party_strn_snapshot), p.strn) AS strn,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN d.taxable_paisa ELSE 0 END) AS sales,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN ${taxOf('sales_tax')} ELSE 0 END) AS st,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN ${taxOf('further_tax')} ELSE 0 END) AS ft,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN d.taxable_paisa ELSE 0 END) AS returns,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN ${taxOf('sales_tax')} + ${taxOf('further_tax')}
                          ELSE 0 END) AS returns_tax,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN $servicesOf ELSE 0 END) AS services,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN ${taxOf('provincial_st')} ELSE 0 END) AS pt,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN $servicesOf ELSE 0 END) AS returns_services,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN ${taxOf('provincial_st')} ELSE 0 END)
                   AS returns_pt,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN d.taxable_paisa ELSE 0 END) AS purchases,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN d.tax_paisa + d.further_tax_paisa ELSE 0 END)
                   AS input,
                 SUM(CASE WHEN d.doc_type = 'purchase_return'
                          THEN d.taxable_paisa ELSE 0 END) AS sent_back,
                 SUM(CASE WHEN d.doc_type = 'purchase_return'
                          THEN d.tax_paisa + d.further_tax_paisa ELSE 0 END)
                   AS sent_back_tax
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return',
                               'purchase_bill', 'purchase_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $where
          GROUP BY d.party_id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.documentLineTaxes,
            _db.paymentAllocations,
            _db.payments,
            _db.documentLines,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        PartyTax(
          partyId: r.readNullable<String>('party_id'),
          name: r.readNullable<String>('party_id') == null
              ? _walkIns
              : r.read<String>('name'),
          ntn: _blank(r.readNullable<String>('ntn')),
          strn: _blank(r.readNullable<String>('strn')),
          salesValue: Money.paisa(r.read<int>('sales')),
          salesTax: Money.paisa(r.read<int>('st')),
          furtherTax: Money.paisa(r.read<int>('ft')),
          returnsValue: Money.paisa(r.read<int>('returns')),
          returnsTax: Money.paisa(r.read<int>('returns_tax')),
          purchasesValue: Money.paisa(r.read<int>('purchases')),
          inputTax: Money.paisa(r.read<int>('input')),
          purchaseReturnsValue: Money.paisa(r.read<int>('sent_back')),
          purchaseReturnsTax: Money.paisa(r.read<int>('sent_back_tax')),
          servicesValue: Money.paisa(r.read<int>('services')),
          provincialTax: Money.paisa(r.read<int>('pt')),
          returnsServicesValue: Money.paisa(r.read<int>('returns_services')),
          returnsProvincialTax: Money.paisa(r.read<int>('returns_pt')),
        ),
    ];
  }

  @override
  Future<List<RateTax>> rateTax(String firmId, ReportPeriod period) async {
    final variables = _Params(firmId, period).variables;
    // The tax rows themselves, by kind, code and rate...
    // A return's rows are put on the footing of the sale they return.
    //
    // M61: the province's tax on a service too, as its own kind. A return
    // gives it back under the code it was charged under with _RETURN after
    // it, at the rate it was charged, so its footing is on the row itself:
    // a split-tender line's two rows come back as two, and looking them up
    // on the sale (which has two rows for the one item) could only guess.
    final taxed = await _db
        .customSelect(
          '''
          SELECT t.tax_kind,
                 CASE WHEN t.tax_kind = 'provincial_st'
                      THEN REPLACE(t.tax_code, '_RETURN', '')
                      WHEN d.doc_type = 'sale_return'
                      THEN COALESCE(${_returned('tax_code', 't.tax_kind')},
                                    t.tax_code)
                      ELSE t.tax_code END AS code,
                 CASE WHEN t.tax_kind = 'provincial_st'
                      THEN t.rate_bp
                      WHEN d.doc_type = 'sale_return'
                      THEN COALESCE(${_returned('rate_bp', 't.tax_kind')},
                                    t.rate_bp)
                      ELSE t.rate_bp END AS rate,
                 d.doc_type = 'sale_return' AS is_return,
                 COUNT(DISTINCT t.document_line_id) AS lines,
                 SUM(t.base_paisa) AS base, SUM(t.amount_paisa) AS amount
          FROM document_line_taxes t
          JOIN documents d ON d.id = t.document_id
          JOIN document_lines dl ON dl.id = t.document_line_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND t.deleted_at_utc IS NULL
            AND t.tax_kind IN ('sales_tax', 'further_tax', 'provincial_st')
          GROUP BY t.tax_kind, code, rate, is_return
          ''',
          variables: variables,
          readsFrom: {
            _db.documentLineTaxes,
            _db.documents,
            _db.documentLines,
            _db.docLinks,
          },
        )
        .get();
    // ...and the lines that carried no sales tax at all, by their item's
    // rule: exempt, zero-rated, or neither. A service the province taxed
    // is taxed, by the province, and is under its own rows (M61); it used
    // to be counted here as a supply on which no tax was charged.
    final untaxed = await _db
        .customSelect(
          '''
          SELECT $_untaxedRule AS rule,
                 d.doc_type = 'sale_return' AS is_return,
                 COUNT(*) AS lines, SUM(dl.taxable_paisa) AS base
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN tax_rules tr ON tr.id = i.tax_rule_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND dl.deleted_at_utc IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM document_line_taxes t
              WHERE t.document_line_id = dl.id
                AND t.tax_kind IN ('sales_tax', 'provincial_st')
                AND t.deleted_at_utc IS NULL
            )
          GROUP BY rule, is_return
          ''',
          variables: variables,
          readsFrom: {
            _db.documentLines,
            _db.documents,
            _db.items,
            _db.taxRules,
            _db.documentLineTaxes,
          },
        )
        .get();
    return [
      for (final r in taxed)
        RateTax(
          kind: r.read<String>('tax_kind'),
          code: r.read<String>('code'),
          rateBp: r.read<int>('rate'),
          isReturn: r.read<int>('is_return') == 1,
          lines: r.read<int>('lines'),
          value: Money.paisa(r.read<int>('base')),
          tax: Money.paisa(r.read<int>('amount')),
        ),
      for (final r in untaxed)
        RateTax(
          kind: 'none',
          code: r.readNullable<String>('rule'),
          rateBp: 0,
          isReturn: r.read<int>('is_return') == 1,
          lines: r.read<int>('lines'),
          value: Money.paisa(r.read<int>('base')),
          tax: Money.zero,
        ),
    ];
  }

  @override
  Future<List<HsCodeSales>> hsCodeSales(
    String firmId,
    ReportPeriod period,
  ) async {
    // The code the line was sold under, else the item's as it stands: the
    // same choice the FBR reporting made when the bill was sent (M19).
    final rows = await _db
        .customSelect(
          '''
          WITH lt AS ($_lineTaxes)
          SELECT COALESCE(NULLIF(TRIM(dl.hs_code_snapshot), ''),
                          NULLIF(TRIM(i.hs_code), '')) AS hs,
                 MIN(dl.item_name_snapshot) AS example,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice' THEN 1 ELSE 0 END)
                   AS lines,
                 COUNT(DISTINCT COALESCE(dl.item_id, dl.item_name_snapshot))
                   AS items,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.taxable_paisa ELSE 0 END) AS value,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN COALESCE(lt.st, 0) ELSE 0 END) AS st,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN COALESCE(lt.ft, 0) ELSE 0 END) AS ft,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.taxable_paisa ELSE 0 END) AS returned,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN COALESCE(lt.st, 0) ELSE 0 END) AS returned_st,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN COALESCE(lt.ft, 0) ELSE 0 END) AS returned_ft,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN COALESCE(lt.pt, 0) ELSE 0 END) AS pt,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN COALESCE(lt.pt, 0) ELSE 0 END) AS returned_pt
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN lt ON lt.document_line_id = dl.id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND dl.deleted_at_utc IS NULL
          GROUP BY hs
          ''',
          variables: _Params(firmId, period).variables,
          readsFrom: {
            _db.documentLines,
            _db.documents,
            _db.items,
            _db.documentLineTaxes,
          },
        )
        .get();
    return [
      for (final r in rows)
        HsCodeSales(
          hsCode: r.readNullable<String>('hs'),
          example: r.readNullable<String>('example'),
          lines: r.read<int>('lines'),
          items: r.read<int>('items'),
          value: Money.paisa(r.read<int>('value')),
          salesTax: Money.paisa(r.read<int>('st')),
          furtherTax: Money.paisa(r.read<int>('ft')),
          returnsValue: Money.paisa(r.read<int>('returned')),
          returnsSalesTax: Money.paisa(r.read<int>('returned_st')),
          returnsFurtherTax: Money.paisa(r.read<int>('returned_ft')),
          provincialTax: Money.paisa(r.read<int>('pt')),
          returnsProvincialTax: Money.paisa(r.read<int>('returned_pt')),
        ),
    ];
  }

  @override
  Future<List<AnnexLine>> annexLines(
    String firmId,
    ReportPeriod period, {
    required bool purchases,
  }) async {
    // One row per bill line, with the party as the bill named them (the
    // snapshot) and as their khata has them now (the CNIC and province,
    // which the bill does not keep), the tax rows of the line, and for a
    // return the bill it returns: by FBR's number where FBR gave one, else
    // the shop's own, or for a purchase the supplier's.
    final types = purchases
        ? "('purchase_bill', 'purchase_return')"
        : "('sale_invoice', 'sale_return')";
    final rows = await _db
        .customSelect(
          '''
          WITH lt AS ($_lineTaxes)
          SELECT d.id, d.doc_type, d.doc_no, d.doc_date_local,
                 d.supplier_bill_no, d.notes,
                 COALESCE(d.party_name_snapshot, p.name) AS party,
                 COALESCE(d.party_ntn_snapshot, p.ntn) AS ntn,
                 COALESCE(d.party_strn_snapshot, p.strn) AS strn,
                 p.cnic, p.buyer_registration_type, p.province AS province,
                 f.province AS shop_province,
                 COALESCE(NULLIF(TRIM(dl.hs_code_snapshot), ''),
                          NULLIF(TRIM(i.hs_code), '')) AS hs,
                 dl.item_name_snapshot, dl.qty_thousandths,
                 dl.unit_code_snapshot,
                 -- A purchase line keeps what the delivery came to in its
                 -- line total and nothing in taxable: purchases carry no
                 -- tax of their own yet, so the two are the same figure.
                 CASE WHEN dl.taxable_paisa = 0 THEN dl.line_total_paisa
                      ELSE dl.taxable_paisa END AS taxable_paisa,
                 COALESCE(lt.st, 0) AS st, COALESCE(lt.ft, 0) AS ft,
                 COALESCE(lt.pt, 0) AS pt, lt.pt_code,
                 CASE WHEN d.doc_type = 'sale_return'
                      THEN COALESCE(${_returned('rate_bp', "'sales_tax'")},
                                    lt.st_bp)
                      ELSE lt.st_bp END AS st_bp,
                 CASE WHEN d.doc_type = 'sale_return'
                      THEN COALESCE(${_returned('tax_code', "'sales_tax'")},
                                    lt.st_code)
                      ELSE lt.st_code END AS st_code,
                 $_untaxedRule AS rule,
                 (SELECT COALESCE(o.fbr_invoice_no, o.supplier_bill_no,
                                  o.doc_no)
                    FROM doc_links l
                    JOIN documents o ON o.id = l.from_document_id
                   WHERE l.to_document_id = d.id
                     AND l.link_type = 'returns'
                     AND l.deleted_at_utc IS NULL
                   LIMIT 1) AS returns_bill
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          JOIN firms f ON f.id = d.firm_id
          LEFT JOIN parties p ON p.id = d.party_id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN tax_rules tr ON tr.id = i.tax_rule_id
          LEFT JOIN lt ON lt.document_line_id = dl.id
          WHERE d.firm_id = ?1
            AND d.doc_type IN $types
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND dl.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local, d.doc_seq, d.id, dl.line_no
          ''',
          variables: _Params(firmId, period).variables,
          readsFrom: {
            _db.documentLines,
            _db.documents,
            _db.firms,
            _db.parties,
            _db.items,
            _db.taxRules,
            _db.documentLineTaxes,
            _db.docLinks,
          },
        )
        .get();
    return [
      for (final r in rows)
        AnnexLine(
          documentId: r.read<String>('id'),
          docType: r.read<String>('doc_type'),
          // A purchase is filed under the supplier's own invoice number,
          // which is the one FBR matches against what they filed.
          docNo: purchases
              ? _blank(r.readNullable<String>('supplier_bill_no')) ??
                    r.read<String>('doc_no')
              : r.read<String>('doc_no'),
          date: BusinessDate(r.read<String>('doc_date_local')),
          partyName: _blank(r.readNullable<String>('party')),
          ntn: _blank(r.readNullable<String>('ntn')),
          strn: _blank(r.readNullable<String>('strn')),
          cnic: _blank(r.readNullable<String>('cnic')),
          isRegistered:
              r.readNullable<String>('buyer_registration_type') == 'registered',
          partyProvince: _blank(r.readNullable<String>('province')),
          shopProvince: r.readNullable<String>('shop_province'),
          hsCode: r.readNullable<String>('hs'),
          itemName: r.read<String>('item_name_snapshot'),
          qty: Qty.raw(r.read<int>('qty_thousandths')),
          unitCode: r.read<String>('unit_code_snapshot'),
          value: Money.paisa(r.read<int>('taxable_paisa')),
          salesTax: Money.paisa(r.read<int>('st')),
          furtherTax: Money.paisa(r.read<int>('ft')),
          salesTaxRateBp: r.readNullable<int>('st_bp'),
          taxCode: r.readNullable<String>('st_code'),
          exemptRule: r.readNullable<String>('rule'),
          reference: _blank(r.readNullable<String>('returns_bill')),
          reason: r.read<String>('doc_type').endsWith('return')
              ? _blank(r.readNullable<String>('notes'))
              : null,
          // M61: a service the province taxed, which Annex-C leaves out.
          provincialTax: Money.paisa(r.read<int>('pt')),
          provincialCode: r.readNullable<String>('pt_code'),
        ),
    ];
  }
}
