/// Which side of the ledger an account normally sits on.
enum NormalSide { debit, credit }

/// The five roots of double entry.
enum AccountType { asset, liability, equity, income, expense }

/// One account in the chart, as shipped on first run.
final class AccountSpec {
  const AccountSpec({
    required this.code,
    required this.nameEn,
    required this.nameUr,
    required this.type,
    required this.normalSide,
    this.systemKey,
    this.parentCode,
    this.isDirect = false,
  });

  final String code;
  final String nameEn;

  /// Roman Urdu, in Latin script. Every Pakistani khata competitor ships
  /// English only and then writes Roman Urdu in their own marketing copy,
  /// because that is what shopkeepers actually read.
  final String nameUr;

  final AccountType type;
  final NormalSide normalSide;

  /// The stable handle posting rules look the account up by.
  ///
  /// Renaming "Cash in Hand" to "Golak" must not break the sale posting, so no
  /// rule ever looks an account up by name or by code.
  final String? systemKey;

  final String? parentCode;

  /// Direct costs sit above the gross-profit line in the P&L.
  final bool isDirect;
}

/// The chart of accounts every new firm starts with.
///
/// Seeded on first run and posted to from that moment. There is no "enable
/// accounting" switch and no nightly job: a shopkeeper who never opens the
/// Trial Balance still has one that is correct, because every document has
/// been double-entered since the first sale.
const List<AccountSpec> defaultChartOfAccounts = [
  // ---- Assets -----------------------------------------------------------
  AccountSpec(
    code: '1000',
    nameEn: 'Assets',
    nameUr: 'Assets',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
  ),
  AccountSpec(
    code: '1010',
    nameEn: 'Cash in Hand',
    nameUr: 'Golak',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'cash_in_hand',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1020',
    nameEn: 'Bank Accounts',
    nameUr: 'Bank Account',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'bank',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1030',
    nameEn: 'Mobile Wallets',
    nameUr: 'Mobile Wallet',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'wallet',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1100',
    nameEn: 'Receivables (Udhaar)',
    nameUr: 'Udhaar Lena Hai',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'accounts_receivable',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1150',
    nameEn: 'Cheques in Hand',
    nameUr: 'Cheque Mojood',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'cheques_in_hand',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1200',
    nameEn: 'Inventory',
    nameUr: 'Maal',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'inventory',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1300',
    nameEn: 'Input Sales Tax',
    nameUr: 'Input Sales Tax',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'input_tax',
    parentCode: '1000',
  ),
  AccountSpec(
    code: '1400',
    nameEn: 'Fixed Assets',
    nameUr: 'Fixed Assets',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    systemKey: 'fixed_assets',
    parentCode: '1000',
  ),

  // ---- Liabilities ------------------------------------------------------
  AccountSpec(
    code: '2000',
    nameEn: 'Liabilities',
    nameUr: 'Wajibat',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
  ),
  AccountSpec(
    code: '2100',
    nameEn: 'Payables',
    nameUr: 'Udhaar Dena Hai',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'accounts_payable',
    parentCode: '2000',
  ),
  // Cheques the shop has written and the bank has not yet paid. The payable
  // is settled the day the cheque is handed over, but the money is still in
  // the bank until the supplier presents it; this is where the difference
  // sits, so the bank balance in the books is what the bank would say.
  AccountSpec(
    code: '2150',
    nameEn: 'Cheques Issued',
    nameUr: 'Diye hue Cheque',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'cheques_issued',
    parentCode: '2000',
  ),
  AccountSpec(
    code: '2200',
    nameEn: 'Output Sales Tax',
    nameUr: 'Output Sales Tax',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'output_tax',
    parentCode: '2000',
  ),
  // Further tax is 4% under s.3(1A) STA since the Finance Act 2023, and it is
  // triggered by the buyer being off the Active Taxpayer List. It is tracked
  // separately from output tax because the return reports it separately.
  AccountSpec(
    code: '2210',
    nameEn: 'Further Tax Payable',
    nameUr: 'Further Tax',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'further_tax_payable',
    parentCode: '2000',
  ),
  AccountSpec(
    code: '2300',
    nameEn: 'Withholding Tax Payable',
    nameUr: 'Withholding Tax',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'withholding_payable',
    parentCode: '2000',
  ),
  AccountSpec(
    code: '2400',
    nameEn: 'Customer Advances',
    nameUr: 'Customer Peshgi',
    type: AccountType.liability,
    normalSide: NormalSide.credit,
    systemKey: 'customer_advances',
    parentCode: '2000',
  ),

  // ---- Equity -----------------------------------------------------------
  AccountSpec(
    code: '3000',
    nameEn: 'Equity',
    nameUr: 'Sarmaya',
    type: AccountType.equity,
    normalSide: NormalSide.credit,
  ),
  AccountSpec(
    code: '3100',
    nameEn: "Owner's Capital",
    nameUr: 'Malik ka Sarmaya',
    type: AccountType.equity,
    normalSide: NormalSide.credit,
    systemKey: 'owner_capital',
    parentCode: '3000',
  ),
  AccountSpec(
    code: '3200',
    nameEn: "Owner's Drawings",
    nameUr: 'Malik ki Nikasi',
    type: AccountType.equity,
    normalSide: NormalSide.debit,
    systemKey: 'owner_drawings',
    parentCode: '3000',
  ),
  AccountSpec(
    code: '3900',
    nameEn: 'Retained Earnings',
    nameUr: 'Jama Shuda Munafa',
    type: AccountType.equity,
    normalSide: NormalSide.credit,
    systemKey: 'retained_earnings',
    parentCode: '3000',
  ),

  // ---- Income -----------------------------------------------------------
  AccountSpec(
    code: '4000',
    nameEn: 'Income',
    nameUr: 'Aamdani',
    type: AccountType.income,
    normalSide: NormalSide.credit,
  ),
  AccountSpec(
    code: '4100',
    nameEn: 'Sales',
    nameUr: 'Farokht',
    type: AccountType.income,
    normalSide: NormalSide.credit,
    systemKey: 'sales',
    parentCode: '4000',
  ),
  AccountSpec(
    code: '4200',
    nameEn: 'Sales Returns',
    nameUr: 'Wapsi',
    type: AccountType.income,
    normalSide: NormalSide.debit,
    systemKey: 'sales_returns',
    parentCode: '4000',
  ),
  AccountSpec(
    code: '4300',
    nameEn: 'Discount Given',
    nameUr: 'Riayat Di',
    type: AccountType.income,
    normalSide: NormalSide.debit,
    systemKey: 'discount_given',
    parentCode: '4000',
  ),
  // Invoice rounding is posted, never absorbed. A shop that rounds two hundred
  // bills a day to the rupee moves real money, and it must be visible.
  AccountSpec(
    code: '4400',
    nameEn: 'Round Off',
    nameUr: 'Round Off',
    type: AccountType.income,
    normalSide: NormalSide.credit,
    systemKey: 'round_off',
    parentCode: '4000',
  ),
  AccountSpec(
    code: '4900',
    nameEn: 'Other Income',
    nameUr: 'Deegar Aamdani',
    type: AccountType.income,
    normalSide: NormalSide.credit,
    systemKey: 'other_income',
    parentCode: '4000',
  ),

  // ---- Expenses ---------------------------------------------------------
  AccountSpec(
    code: '5000',
    nameEn: 'Direct Expenses',
    nameUr: 'Barah-e-Rast Kharchay',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    isDirect: true,
  ),
  AccountSpec(
    code: '5100',
    nameEn: 'Cost of Goods Sold',
    nameUr: 'Maal ki Lagat',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'cogs',
    parentCode: '5000',
    isDirect: true,
  ),
  AccountSpec(
    code: '5200',
    nameEn: 'Purchase Returns',
    nameUr: 'Khareed Wapsi',
    type: AccountType.expense,
    normalSide: NormalSide.credit,
    systemKey: 'purchase_returns',
    parentCode: '5000',
    isDirect: true,
  ),
  AccountSpec(
    code: '5300',
    nameEn: 'Discount Received',
    nameUr: 'Riayat Mili',
    type: AccountType.expense,
    normalSide: NormalSide.credit,
    systemKey: 'discount_received',
    parentCode: '5000',
    isDirect: true,
  ),
  AccountSpec(
    code: '5400',
    nameEn: 'Freight and Cartage',
    nameUr: 'Kiraya Baar',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'freight',
    parentCode: '5000',
    isDirect: true,
  ),
  AccountSpec(
    code: '5500',
    nameEn: 'Stock Wastage',
    nameUr: 'Maal ka Zaya',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'stock_wastage',
    parentCode: '5000',
    isDirect: true,
  ),
  AccountSpec(
    code: '6000',
    nameEn: 'Indirect Expenses',
    nameUr: 'Deegar Kharchay',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
  ),
  AccountSpec(
    code: '6100',
    nameEn: 'Rent',
    nameUr: 'Kiraya',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'rent',
    parentCode: '6000',
  ),
  AccountSpec(
    code: '6200',
    nameEn: 'Salaries and Wages',
    nameUr: 'Tankhwah',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'salaries',
    parentCode: '6000',
  ),
  AccountSpec(
    code: '6300',
    nameEn: 'Utilities',
    nameUr: 'Bijli Gas Pani',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'utilities',
    parentCode: '6000',
  ),
  AccountSpec(
    code: '6400',
    nameEn: 'Bad Debts',
    nameUr: 'Doobi Hui Raqam',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'bad_debts',
    parentCode: '6000',
  ),
  AccountSpec(
    code: '6900',
    nameEn: 'Miscellaneous',
    nameUr: 'Mutafarriq',
    type: AccountType.expense,
    normalSide: NormalSide.debit,
    systemKey: 'misc',
    parentCode: '6000',
  ),
];
