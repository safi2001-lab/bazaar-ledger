class AppConstants {
  static const String appName = 'Pakistan SME Billing';
  static const String defaultCurrency = 'PKR';
  static const String currencySymbol = 'Rs.';
  static const int currencyNumericCode = 586; // SBP ISO 4217 for PKR
  static const String countryCode = 'PK';

  // Standard Pakistan Tax Rates
  static const double standardFbrSalesTaxRate = 18.0;
  static const double furtherTaxSection3_1ARate = 3.0;
  static const double tajirDostTurnoverTaxRate = 1.0;
  static const double tajirDostMinAnnualTax = 25000.0;
  static const double section73BankingLimit = 50000.0; // Invoices > Rs. 50,000 need banking channel

  // Thermal Printing Constants @ 203 DPI
  static const int printWidth58mmDots = 384;
  static const int printWidth80mmDots = 576;
  static const int printerChunkSizeBytes = 512;
  static const int printerChunkDelayMs = 35;
}
