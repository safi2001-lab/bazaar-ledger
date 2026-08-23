// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_strings.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppStringsEn extends AppStrings {
  AppStringsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Bazaar Ledger';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionBack => 'Back';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionShare => 'Share';

  @override
  String get actionPrint => 'Print';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionDone => 'Done';

  @override
  String get actionOk => 'OK';

  @override
  String get commonLoading => 'Opening...';

  @override
  String get commonSomethingWentWrong => 'Something went wrong';

  @override
  String get commonNothingSaved => 'Nothing was saved';

  @override
  String get commonRequired => 'This is required';

  @override
  String get commonOffline =>
      'No internet - that\'s fine, everything runs on this phone';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get setupTitle => 'Set up your shop';

  @override
  String get setupSubtitle =>
      'Three things. Everything else can be changed later.';

  @override
  String get setupShopName => 'Shop name';

  @override
  String get setupShopNameHint => 'Chishti Kiryana Store';

  @override
  String get setupOwnerName => 'Your name';

  @override
  String get setupOwnerNameHint => 'Malik Sahib';

  @override
  String get setupCity => 'City';

  @override
  String get setupCityHint => 'Lahore';

  @override
  String get setupProvince => 'Province';

  @override
  String get setupBusinessKind => 'Kind of shop';

  @override
  String get setupCounterName => 'Name this counter';

  @override
  String get setupCounterHint => 'Counter 1';

  @override
  String get setupFinish => 'Open the shop';

  @override
  String get setupPrivacyNote =>
      'Your books stay on this phone. No account, no server.';

  @override
  String get businessKindGeneral => 'General store';

  @override
  String get businessKindKiryana => 'Kiryana';

  @override
  String get businessKindPharmacy => 'Pharmacy';

  @override
  String get businessKindGarments => 'Garments';

  @override
  String get businessKindCloth => 'Cloth';

  @override
  String get businessKindHardware => 'Hardware';

  @override
  String get businessKindElectronics => 'Electronics';

  @override
  String get businessKindRestaurant => 'Restaurant';

  @override
  String get businessKindServices => 'Services';

  @override
  String get businessKindWholesale => 'Wholesale';

  @override
  String get provincePunjab => 'Punjab';

  @override
  String get provinceSindh => 'Sindh';

  @override
  String get provinceKpk => 'Khyber Pakhtunkhwa';

  @override
  String get provinceBalochistan => 'Balochistan';

  @override
  String get provinceIct => 'Islamabad';

  @override
  String get provinceGb => 'Gilgit-Baltistan';

  @override
  String get provinceAjk => 'Azad Kashmir';

  @override
  String get homeTitle => 'Today';

  @override
  String get homeTodaySales => 'Today\'s sales';

  @override
  String homeBillCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills',
      one: '1 bill',
      zero: 'No bills',
    );
    return '$_temp0';
  }

  @override
  String get homeReceived => 'Received';

  @override
  String get homeOnUdhaar => 'On credit';

  @override
  String get homeNewBill => 'New Bill';

  @override
  String get homeItems => 'Items';

  @override
  String get homeSales => 'Sales';

  @override
  String get homeCustomers => 'Customers';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeNoSalesToday => 'No bills yet today';

  @override
  String get posTitle => 'New Bill';

  @override
  String get posSearchHint => 'Item name or barcode';

  @override
  String get posCartEmpty => 'The bill is empty';

  @override
  String get posCartEmptyHint => 'Search above and add something to the bill';

  @override
  String get posSubtotal => 'Subtotal';

  @override
  String get posDiscount => 'Discount';

  @override
  String get posTax => 'Sales tax';

  @override
  String get posRoundOff => 'Round off';

  @override
  String get posTotal => 'Total';

  @override
  String get posCharge => 'Take payment';

  @override
  String posItemsInCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get posRemoveLine => 'Remove line';

  @override
  String get posClearCart => 'Clear the bill';

  @override
  String get posClearCartConfirm => 'Clear the whole bill?';

  @override
  String get posWalkInCustomer => 'Walk-in customer';

  @override
  String get posChooseCustomer => 'Choose a customer';

  @override
  String get posQty => 'Qty';

  @override
  String get posRate => 'Rate';

  @override
  String get posAmount => 'Amount';

  @override
  String get posLineDiscount => 'Discount on this line';

  @override
  String get posNoStock => 'Out of stock';

  @override
  String posStockLeft(String qty, String unit) {
    return 'Stock: $qty $unit';
  }

  @override
  String get tenderTitle => 'Take payment';

  @override
  String get tenderDue => 'Due';

  @override
  String get tenderTendered => 'Given';

  @override
  String get tenderChange => 'Change';

  @override
  String get tenderExact => 'Exact';

  @override
  String get tenderRemaining => 'Remaining';

  @override
  String get tenderOnUdhaar => 'Put on credit';

  @override
  String get tenderModeCash => 'Cash';

  @override
  String get tenderModeBank => 'Bank';

  @override
  String get tenderModeJazzCash => 'JazzCash';

  @override
  String get tenderModeEasypaisa => 'EasyPaisa';

  @override
  String get tenderModeRaast => 'Raast';

  @override
  String get tenderModeCard => 'Card';

  @override
  String get tenderModeCheque => 'Cheque';

  @override
  String get tenderReference => 'Reference (optional)';

  @override
  String get tenderManualNote =>
      'However the customer pays, you just note it here. The app never handles money itself.';

  @override
  String get tenderSaveAndPrint => 'Save and Print';

  @override
  String get tenderSave => 'Save only';

  @override
  String get tenderUdhaarNeedsCustomer =>
      'Choose a customer before putting this on credit';

  @override
  String get tenderCashThresholdWarning =>
      'A single bill over Rs 200,000 settled in cash can have 50% of the expenditure disallowed under s.21(s). A bank or digital channel is safer.';

  @override
  String billSaved(String docNo) {
    return 'Bill $docNo saved';
  }

  @override
  String get billSaveFailed =>
      'The bill was not saved. Nothing at all was written.';

  @override
  String get itemsTitle => 'Items';

  @override
  String get itemsEmpty => 'No items yet';

  @override
  String get itemsEmptyHint => 'Add the first item, then start billing';

  @override
  String get itemsAdd => 'New item';

  @override
  String get itemsEdit => 'Edit item';

  @override
  String get itemName => 'Name';

  @override
  String get itemNameHint => 'Cooking Oil 5L';

  @override
  String get itemCode => 'Code (optional)';

  @override
  String get itemBarcode => 'Barcode (optional)';

  @override
  String get itemCategory => 'Category (optional)';

  @override
  String get itemUnit => 'Unit';

  @override
  String get itemSalePrice => 'Sale price';

  @override
  String get itemPurchasePrice => 'Purchase price';

  @override
  String get itemOpeningStock => 'Stock on hand';

  @override
  String get itemMinStock => 'Low stock alert at';

  @override
  String get itemArchive => 'Hide from the counter';

  @override
  String get itemArchived => 'Item hidden';

  @override
  String get itemSaved => 'Item saved';

  @override
  String itemInStock(String qty, String unit) {
    return '$qty $unit in stock';
  }

  @override
  String get itemLowStock => 'Running low';

  @override
  String get partiesTitle => 'Customers';

  @override
  String get partiesEmpty => 'No customers yet';

  @override
  String get partiesEmptyHint => 'Add a customer to keep an udhaar khata';

  @override
  String get partiesAdd => 'New customer';

  @override
  String get partyName => 'Name';

  @override
  String get partyPhone => 'Phone';

  @override
  String get partyOpeningBalance => 'Balance carried over';

  @override
  String get partyCreditLimit => 'Credit limit';

  @override
  String partyOwes(String amount) {
    return 'owes $amount';
  }

  @override
  String get partySettled => 'Settled up';

  @override
  String get salesTitle => 'Sales';

  @override
  String get salesEmpty => 'No bills yet';

  @override
  String get salesEmptyHint => 'Make the first bill and it will show up here';

  @override
  String get salesPaid => 'Paid';

  @override
  String salesUdhaar(String amount) {
    return '$amount owing';
  }

  @override
  String get salesVoided => 'Voided';

  @override
  String receiptTitle(String docNo) {
    return 'Bill $docNo';
  }

  @override
  String get receiptSharePdf => 'Share PDF';

  @override
  String get receiptPrint => 'Send to printer';

  @override
  String get receiptPreview => 'How it will print';

  @override
  String get receiptPaper80 => '80mm';

  @override
  String get receiptPaper58 => '58mm';

  @override
  String get receiptReprint => 'Reprint';

  @override
  String get receiptNoPrinter =>
      'No printer set up yet. You can still see the preview and share the PDF.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageRomanUrdu => 'Roman Urdu';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeSystem => 'Match the phone';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsShop => 'Shop details';

  @override
  String get settingsPayment => 'How customers pay you';

  @override
  String get settingsRaastAlias => 'Raast alias (mobile number)';

  @override
  String get settingsBankName => 'Bank name';

  @override
  String get settingsAccountTitle => 'Account title';

  @override
  String get settingsIban => 'IBAN';

  @override
  String get settingsPaymentNote =>
      'This is printed on the bill so the customer can pay you directly. The app neither takes nor sends money, so there is no bank account to connect.';

  @override
  String get settingsQrNote =>
      'We never generate a payment QR. Under State Bank rules only licensed banks and payment companies may issue one. If your bank gave you a QR, add a photo of it here.';

  @override
  String get settingsDataHealth => 'Data health';

  @override
  String get settingsDataHealthOk => 'Everything checks out';

  @override
  String settingsDataHealthProblem(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems found',
      one: '1 problem found',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataHealthCheck => 'Check now';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutBody =>
      'Everything is on this phone. No server, no account, no internet needed.';

  @override
  String get emptyNoResults => 'Nothing found';

  @override
  String get emptyNoResultsHint => 'Try a different word';

  @override
  String get errorTitle => 'Stopped';

  @override
  String get errorNothingWasSaved =>
      'Nothing was saved, so nothing is out of place.';

  @override
  String a11yRupees(String amount) {
    return 'Rupees $amount';
  }

  @override
  String a11yOwing(String amount) {
    return '$amount owing';
  }

  @override
  String get a11yLoading => 'Loading';

  @override
  String get errorStartupTitle => 'The books could not be opened';

  @override
  String get errorStartupBody =>
      'Nothing has been lost. Close the app and open it again. If this keeps happening, restore from your last backup.';

  @override
  String get permissionDeniedTitle => 'Permission not granted';

  @override
  String get permissionDeniedBody =>
      'This needs permission from your phone\'s settings before it can work.';

  @override
  String get permissionOpenSettings => 'Open phone settings';

  @override
  String get tenderNoAccount =>
      'There is no account left to put the money in. Turn the cash account back on in Settings.';

  @override
  String get itemArchiveConfirm =>
      'This item will not show at the counter any more. Old bills stay exactly as they were.';

  @override
  String get settingsAddress => 'Address';

  @override
  String get settingsTaxRegistered => 'I am registered for sales tax';

  @override
  String get settingsTaxRegisteredNote =>
      'Most kiryana shops are not registered - sales tax is collected through the electricity bill instead. Only turn this on if you hold an STRN.';

  @override
  String get errorStartupRecover => 'Restore from a backup';

  @override
  String get errorStartupNotReady =>
      'Restoring from a backup arrives in M5. For now, close the app and open it again.';

  @override
  String healthWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
    );
    return '$_temp0 found in your data. Check Settings.';
  }

  @override
  String get stockAdjustTitle => 'Correct stock';

  @override
  String get stockAdjustCounted => 'Counted on the shelf';

  @override
  String get stockAdjustCurrent => 'The ledger says';

  @override
  String get stockAdjustReason => 'Reason';

  @override
  String get stockAdjustReasonHint => 'Monthly count, broken, stolen';

  @override
  String get stockAdjustSave => 'Correct it';

  @override
  String get stockAdjustDone => 'Stock corrected';

  @override
  String get stockAdjustNeedsReason => 'A reason is required';

  @override
  String get stockAdjustWriteOff => 'Wastage';

  @override
  String get stockAdjustRecount => 'Stock take';

  @override
  String get stockLowTitle => 'Low stock';

  @override
  String get stockLowNone => 'Nothing is running low';

  @override
  String get stockLowSubtitle => 'These are about to run out';

  @override
  String stockLowFloor(String floor) {
    return 'Floor: $floor';
  }

  @override
  String get itemWholesalePrice => 'Wholesale price';

  @override
  String get itemMrp => 'MRP (printed price)';

  @override
  String get itemHsCode => 'HS code';

  @override
  String get itemDescription => 'Description';

  @override
  String get itemTracksStock => 'Keep stock for this';

  @override
  String get itemTracksStockOff => 'A service or charge — no stock';

  @override
  String get itemMoreFields => 'More detail';

  @override
  String get settingsPrinter => 'Printer';

  @override
  String get printerTitle => 'Set up the printer';

  @override
  String get printerNone => 'No printer chosen yet.';

  @override
  String get printerHowItConnects => 'How the printer connects';

  @override
  String get printerViaLan => 'Over Wi-Fi (LAN)';

  @override
  String get printerViaBluetooth => 'Bluetooth';

  @override
  String get printerViaUsb => 'USB cable';

  @override
  String get printerNotOnThisPhone => 'Not available on this phone';

  @override
  String get printerLooking => 'Looking for printers...';

  @override
  String get printerNoneFound =>
      'No printers found. Is it switched on, and on the same Wi-Fi or paired?';

  @override
  String get printerSearchAgain => 'Look again';

  @override
  String get printerAddress => 'Printer address';

  @override
  String get printerAddressHint => '192.168.1.50:9100';

  @override
  String get printerAddressNeeded => 'An address is needed.';

  @override
  String get printerWidth => 'Paper width';

  @override
  String get printerWidthHelp =>
      'Run a test print and look at it. The width whose ruler fits on one line is the right one.';

  @override
  String get printerColumns32 => '32 (58mm)';

  @override
  String get printerColumns42 => '42 (80mm)';

  @override
  String get printerColumns48 => '48 (80mm)';

  @override
  String get printerTestPrint => 'Run a test print';

  @override
  String get printerTestSent => 'Test print sent. Have a look at the paper.';

  @override
  String get printerCopies => 'Copies';

  @override
  String get printerDrawer => 'Open the drawer on a cash sale';

  @override
  String get printerSave => 'Save this printer';

  @override
  String get printerForget => 'Forget this printer';

  @override
  String get printerSaved => 'Printer saved.';

  @override
  String get printerPrinting => 'Printing...';

  @override
  String get printerDone => 'Printed.';

  @override
  String get printerNotSent => 'Nothing came out. You can try again.';

  @override
  String get printerPartial =>
      'It stopped part way through. Look at the paper and decide.';

  @override
  String get printerUnknownAsk =>
      'Nobody can tell whether this bill printed before. Have a look at the paper.';

  @override
  String get printerPrintAgain => 'Print it anyway';

  @override
  String get printerAlreadyPrinted => 'This bill has already been printed.';

  @override
  String get labelTitle => 'Print shelf labels';

  @override
  String get labelCopies => 'How many';

  @override
  String get labelPrint => 'Print labels';

  @override
  String get labelNoCode =>
      'This item has no code. Add a barcode or a code first.';

  @override
  String get labelNoPrinter => 'Set up a printer first.';

  @override
  String get labelSent => 'Labels sent to the printer.';

  @override
  String get labelPreview => 'What goes on the sticker';

  @override
  String get historyTitle => 'Stock history';

  @override
  String get historyNone => 'Nothing has moved yet';

  @override
  String get historyOpening => 'Opening stock';

  @override
  String get historySale => 'Sold';

  @override
  String get historySaleReturn => 'Returned';

  @override
  String get historyPurchase => 'Bought';

  @override
  String get historyAdjustment => 'Correction';

  @override
  String get historyWastage => 'Wastage';

  @override
  String get historyOther => 'Other';

  @override
  String historyBalance(Object qty) {
    return 'Left: $qty';
  }
}
