import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// The sales tax charged to one party, and paid to them, over a period
/// (M35): the output and input sides of a registered shop's return, party by
/// party, with the registration numbers the return asks for.
final class PartyTax {
  const PartyTax({
    required this.name,
    required this.salesValue,
    required this.salesTax,
    required this.furtherTax,
    required this.returnsValue,
    required this.returnsTax,
    required this.purchasesValue,
    required this.inputTax,
    required this.purchaseReturnsValue,
    required this.purchaseReturnsTax,
    this.partyId,
    this.ntn,
    this.strn,
    this.servicesValue = Money.zero,
    this.provincialTax = Money.zero,
    this.returnsServicesValue = Money.zero,
    this.returnsProvincialTax = Money.zero,
  });

  /// Null for the walk-ins, who are one row.
  final String? partyId;
  final String name;
  final String? ntn;
  final String? strn;

  /// The value of supplies on the party's sale bills, before tax: goods and
  /// services alike. [servicesValue] is the part of it the province taxed.
  final Money salesValue;

  /// Sales tax charged on them.
  final Money salesTax;

  /// Further tax charged on them.
  final Money furtherTax;

  /// What the party's returns took back, before tax, and the sales and
  /// further tax given back with them.
  final Money returnsValue;
  final Money returnsTax;

  /// The party's deliveries to the shop, before tax, and the tax on their
  /// bills as the shop recorded it.
  final Money purchasesValue;
  final Money inputTax;
  final Money purchaseReturnsValue;
  final Money purchaseReturnsTax;

  /// The value of the service lines on the party's bills that carried the
  /// province's tax (M61), and that tax: owed to PRA, SRB, KPRA or BRA,
  /// never to FBR, and so never in [salesTax] or [outputTax].
  final Money servicesValue;
  final Money provincialTax;

  /// What returns of those services took back, and the provincial tax given
  /// back with them (M61).
  final Money returnsServicesValue;
  final Money returnsProvincialTax;

  /// Sales and further tax, less what returns gave back. FBR's alone.
  Money get outputTax => salesTax + furtherTax - returnsTax;

  /// The province's tax on services, less what returns gave back (M61).
  Money get netProvincialTax => provincialTax - returnsProvincialTax;

  /// Services taxed by the province, net of returns (M61).
  Money get netServicesValue => servicesValue - returnsServicesValue;

  /// What was sold that FBR's return counts: everything less returns, less
  /// the services the province taxed (M61).
  Money get netFbrSalesValue => salesValue - returnsValue - netServicesValue;

  /// Tax on purchases, less what went back.
  Money get netInputTax => inputTax - purchaseReturnsTax;
}

/// Sales tax over a period on one footing (M35): one tax at one rate, or the
/// lines that carried none, for the tax rate report.
final class RateTax {
  const RateTax({
    required this.kind,
    required this.rateBp,
    required this.isReturn,
    required this.lines,
    required this.value,
    required this.tax,
    this.code,
  });

  /// `sales_tax`, `further_tax`, `provincial_st` for the province's tax on
  /// a service (M61), or `none` for lines that carried no tax at all.
  final String kind;

  /// The tax code, `ST_STD_18`, `ST_3RD_18`, `FURTHER_4`, `PRA_STD`,
  /// `PRA_CARD` — a provincial tax given back on a return under the code it
  /// was charged under; or for a line with no tax, its item's tax rule,
  /// `exempt` or `zero_rated`, when it has one.
  final String? code;
  final int rateBp;

  /// Given back on a sale return rather than charged on a sale.
  final bool isReturn;
  final int lines;

  /// The value the tax was charged on: the value of supply.
  final Money value;
  final Money tax;
}

/// What was sold under one HS code over a period, net of returns (M35).
final class HsCodeSales {
  const HsCodeSales({
    required this.lines,
    required this.items,
    required this.value,
    required this.salesTax,
    required this.furtherTax,
    required this.returnsValue,
    required this.returnsSalesTax,
    required this.returnsFurtherTax,
    this.hsCode,
    this.example,
    this.provincialTax = Money.zero,
    this.returnsProvincialTax = Money.zero,
  });

  /// As the bill line or the item carries it; null for lines with none.
  final String? hsCode;

  /// One item sold under it, to say what the code is in the shop's words.
  final String? example;

  /// Lines on bills, and different items, under the code.
  final int lines;
  final int items;

  /// The value of supply, before tax.
  final Money value;
  final Money salesTax;
  final Money furtherTax;

  /// What returns took back under the code, and each tax given back.
  final Money returnsValue;
  final Money returnsSalesTax;
  final Money returnsFurtherTax;

  /// The province's tax on the services sold under the code, and what
  /// returns gave back of it (M61). Owed to the province, not FBR.
  final Money provincialTax;
  final Money returnsProvincialTax;

  Money get netValue => value - returnsValue;
  Money get netSalesTax => salesTax - returnsSalesTax;
  Money get netFurtherTax => furtherTax - returnsFurtherTax;

  /// FBR's tax under the code: sales and further, never the province's.
  Money get netTax => netSalesTax + netFurtherTax;
  Money get netProvincialTax => provincialTax - returnsProvincialTax;
}

/// One line of one bill, as the sales tax return's annexure asks for it
/// (M35): Annex-C for sales and credit notes, Annex-A for purchases.
final class AnnexLine {
  const AnnexLine({
    required this.documentId,
    required this.docType,
    required this.docNo,
    required this.date,
    required this.itemName,
    required this.qty,
    required this.unitCode,
    required this.value,
    required this.salesTax,
    required this.furtherTax,
    required this.salesTaxRateBp,
    this.partyName,
    this.ntn,
    this.strn,
    this.cnic,
    this.isRegistered = false,
    this.partyProvince,
    this.shopProvince,
    this.hsCode,
    this.taxCode,
    this.exemptRule,
    this.reference,
    this.reason,
    this.provincialTax = Money.zero,
    this.provincialCode,
  });

  final String documentId;

  /// `sale_invoice`, `sale_return`, `purchase_bill` or `purchase_return`.
  final String docType;
  final String docNo;
  final BusinessDate date;

  /// The buyer or supplier on the bill, or null for a walk-in.
  final String? partyName;
  final String? ntn;
  final String? strn;
  final String? cnic;

  /// Whether the party is registered for sales tax.
  final bool isRegistered;

  /// The party's province as their khata has it, and the shop's.
  final String? partyProvince;
  final String? shopProvince;

  final String? hsCode;
  final String itemName;

  /// As typed on the bill, in [unitCode].
  final Qty qty;
  final String unitCode;

  /// The value of supply: before tax, after every discount.
  final Money value;
  final Money salesTax;
  final Money furtherTax;

  /// The sales tax rate on the line, or null when it carried none.
  final int? salesTaxRateBp;

  /// The sales tax code, `ST_STD_18` or `ST_3RD_18`, when it carried one.
  final String? taxCode;

  /// The item's tax rule when it is untaxed by rule: `exempt` or
  /// `zero_rated`.
  final String? exemptRule;

  /// For a return: the bill it returns, by FBR's number when FBR gave it
  /// one, else by the shop's.
  final String? reference;

  /// For a return: why, as typed.
  final String? reason;

  /// The province's tax on a service line, and the code it was charged (or
  /// given back) under, `PRA_CARD` (M61). A line that carries it is a
  /// service the province taxes, and FBR's sales register leaves it out.
  final Money provincialTax;
  final String? provincialCode;

  /// Whether the line is a service the province taxed (M61).
  bool get isProvincialService => !provincialTax.isZero;

  bool get isThirdSchedule => taxCode == 'ST_3RD_18';
  bool get isReturn => docType == 'sale_return' || docType == 'purchase_return';
}

/// Where the tax reports read from (M35). Everything is read from what each
/// bill recorded when it was made; nothing is worked out again at today's
/// rates.
abstract interface class TaxReportSource {
  /// Each party with a sale, purchase or return in [period], and the
  /// walk-ins as one, narrowed by [filters].
  Future<List<PartyTax>> partyTax(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// The tax on [period]'s sales and returns by kind, code and rate, and
  /// the lines that carried no sales tax by their item's rule.
  Future<List<RateTax>> rateTax(String firmId, ReportPeriod period);

  /// [period]'s sales and returns by HS code.
  Future<List<HsCodeSales>> hsCodeSales(String firmId, ReportPeriod period);

  /// Every line of [period]'s posted sale bills and returns, or with
  /// [purchases] its purchase bills and returns, in date order.
  Future<List<AnnexLine>> annexLines(
    String firmId,
    ReportPeriod period, {
    required bool purchases,
  });
}
