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

  @override
  String get stockSummaryValue => 'Stock at cost';

  @override
  String stockSummaryItems(Object count) {
    return '$count items';
  }

  @override
  String stockSummaryLow(Object count) {
    return '$count low';
  }

  @override
  String stockSummaryOut(Object count) {
    return '$count out';
  }

  @override
  String stockSummaryNegative(Object count) {
    return '$count below zero';
  }

  @override
  String get pictureAdd => 'Add a photo';

  @override
  String get pictureChange => 'Change photo';

  @override
  String get pictureRemove => 'Remove photo';

  @override
  String get pictureNotAnImage => 'That file is not a picture';

  @override
  String get scanTitle => 'Scan a barcode';

  @override
  String get scanHint => 'Hold the packet barcode in front of the camera';

  @override
  String get scanNoCamera => 'This phone has no camera';

  @override
  String get scanDenied => 'Camera permission was not granted';

  @override
  String get scanTorch => 'Light';

  @override
  String get scanNotFound => 'No item carries that barcode';

  @override
  String get scanAddNew => 'Add it as a new item';

  @override
  String get khataTitle => 'Khata';

  @override
  String get khataBalance => 'Owes';

  @override
  String get khataAdvance => 'In credit';

  @override
  String get khataOpenBills => 'Open bills';

  @override
  String get khataNoBills => 'Nothing outstanding';

  @override
  String get khataNoBillsHint => 'This customer is fully settled';

  @override
  String get khataReceive => 'Receive payment';

  @override
  String get khataDetails => 'Customer details';

  @override
  String get khataCreditLimitOver => 'Over the credit limit';

  @override
  String get wasooliTitle => 'Receive payment';

  @override
  String get wasooliAmount => 'Amount received';

  @override
  String get wasooliMode => 'How';

  @override
  String get wasooliReference => 'Reference (optional)';

  @override
  String get wasooliChequeNo => 'Cheque number';

  @override
  String get wasooliChequeBank => 'Bank name';

  @override
  String get wasooliSettles => 'This will settle';

  @override
  String get wasooliSettlesNone =>
      'No open bills — this will be held on account';

  @override
  String get wasooliOnAccount => 'On account';

  @override
  String get wasooliSave => 'Save receipt';

  @override
  String wasooliSaved(String amount) {
    return '$amount received';
  }

  @override
  String get wasooliAmountRequired => 'Enter an amount';

  @override
  String get wasooliChequeNoRequired => 'Enter the cheque number';

  @override
  String get tenderOverLimit => 'Over the credit limit';

  @override
  String tenderOverLimitDetail(String limit, String after) {
    return 'The limit is $limit. After this bill it would be $after.';
  }

  @override
  String get tenderOverLimitAllow => 'Give credit anyway';

  @override
  String get khataRemind => 'Send a reminder';

  @override
  String get khataRemindNoPhone => 'This customer has no phone number';

  @override
  String get khataRemindNothingOwed => 'Nothing is outstanding';

  @override
  String get chaseTitle => 'Collections';

  @override
  String get chaseEmpty => 'Nobody owes anything';

  @override
  String get chaseEmptyHint => 'Every account is settled';

  @override
  String get chaseTotal => 'Total outstanding';

  @override
  String get chaseOverdue => 'Overdue';

  @override
  String chaseSince(int days) {
    return '$days days';
  }

  @override
  String chaseBills(int count) {
    return '$count bills';
  }

  @override
  String get chaseAll => 'All';

  @override
  String get khataHistory => 'History';

  @override
  String get khataHistoryEmpty => 'Nothing has happened yet';

  @override
  String get homePurchases => 'Purchases';

  @override
  String get purchaseTitle => 'New purchase';

  @override
  String get purchaseSupplier => 'Choose a supplier';

  @override
  String get purchaseSupplierRequired => 'A supplier is required';

  @override
  String get purchaseAddItem => 'Add an item';

  @override
  String get purchaseNoLines => 'Nothing added yet';

  @override
  String get purchaseNoLinesHint => 'Add what arrived';

  @override
  String get purchaseCost => 'Cost price';

  @override
  String get purchaseFreight => 'Freight and labour';

  @override
  String get purchasePaid => 'Paid now';

  @override
  String get purchaseBillNo => 'Supplier\'s bill number';

  @override
  String get purchaseGoods => 'Goods';

  @override
  String get purchaseTotal => 'Total';

  @override
  String get purchaseOwing => 'Owing';

  @override
  String get purchaseSave => 'Save purchase';

  @override
  String purchaseSaved(String docNo) {
    return 'Purchase $docNo saved';
  }

  @override
  String purchaseNewAverage(String rate) {
    return 'New cost $rate';
  }

  @override
  String get purchasePaidTooMuch => 'Cannot pay more than the bill';

  @override
  String get purchasesTitle => 'Purchases';

  @override
  String get purchasesEmpty => 'No purchases yet';

  @override
  String get purchasesEmptyHint => 'Enter the bill for what arrives';

  @override
  String get voidTitle => 'Cancel this bill';

  @override
  String get voidAction => 'Cancel bill';

  @override
  String get voidReason => 'Reason';

  @override
  String get voidReasonRequired => 'A reason is required';

  @override
  String get voidConfirm => 'Yes, cancel it';

  @override
  String get voidExplain =>
      'The bill is not deleted. A reversing entry is written and the stock comes back.';

  @override
  String voidDone(String docNo) {
    return '$docNo cancelled';
  }

  @override
  String get returnTitle => 'Return goods';

  @override
  String get returnAction => 'Take back';

  @override
  String get returnNothingLeft =>
      'Everything on this bill has already come back';

  @override
  String get returnReason => 'Reason';

  @override
  String get returnReasonRequired => 'A reason is required';

  @override
  String get returnPickSomething => 'Choose at least one item';

  @override
  String get returnRefundNow => 'Refunded now';

  @override
  String returnLeft(String qty) {
    return '$qty left';
  }

  @override
  String get returnTotal => 'Return value';

  @override
  String get returnSave => 'Save return';

  @override
  String returnDone(String docNo) {
    return '$docNo saved';
  }

  @override
  String get returnOnAccount => 'Credited to the customer';

  @override
  String get homeExpenses => 'Expenses';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expensesEmpty => 'No expenses yet';

  @override
  String get expensesEmptyHint =>
      'Rent, bijli, wages — money that left the shop goes here';

  @override
  String get expenseNew => 'New expense';

  @override
  String get expenseHead => 'Under';

  @override
  String get expenseHeadRent => 'Rent';

  @override
  String get expenseHeadSalaries => 'Wages';

  @override
  String get expenseHeadUtilities => 'Bijli, gas, water';

  @override
  String get expenseHeadFreight => 'Freight';

  @override
  String get expenseHeadMisc => 'Other';

  @override
  String get expenseAmount => 'Amount';

  @override
  String get expenseNote => 'What it was for';

  @override
  String get expenseNoteRequired => 'Say what this expense was for';

  @override
  String get expensePaidNow => 'Paid now';

  @override
  String get expensePayLater => 'To pay later';

  @override
  String get expensePaidFrom => 'Paid from';

  @override
  String get expensePayee => 'Owed to';

  @override
  String get expensePayeeRequired => 'Say who this is owed to';

  @override
  String get expenseSave => 'Save expense';

  @override
  String expenseSaved(String docNo) {
    return 'Expense $docNo saved';
  }

  @override
  String expenseOwedTo(String name) {
    return 'Owed to $name';
  }

  @override
  String partyWeOwe(String amount) {
    return 'you owe $amount';
  }

  @override
  String get khataPayable => 'You owe them';

  @override
  String get khataPay => 'Pay';

  @override
  String get khataOpenPayables => 'Not yet paid for';

  @override
  String get khataNoPayables => 'Nothing owed to this supplier';

  @override
  String get payTitle => 'Pay supplier';

  @override
  String get payAmount => 'Amount paid';

  @override
  String get paySettles => 'This pays off';

  @override
  String payTooMuch(String amount) {
    return 'Only $amount is owed';
  }

  @override
  String get paySave => 'Save payment';

  @override
  String paySaved(String amount) {
    return '$amount paid';
  }

  @override
  String get backupTitle => 'Backup';

  @override
  String get backupExplain =>
      'Your whole book is sealed into one file that only opens with your password. Send it to yourself on WhatsApp, to Google Drive, or to another phone. If this phone is lost, this is how everything comes back.';

  @override
  String backupLast(String when) {
    return 'Last backup: $when';
  }

  @override
  String get backupNever => 'No backup made yet';

  @override
  String get backupPassphrase => 'Backup password';

  @override
  String get backupPassphraseAgain => 'Type the password again';

  @override
  String get backupPassphraseHint =>
      'At least 8 characters. If you forget it the backup can never be opened — write it down somewhere safe.';

  @override
  String get backupPassphraseShort =>
      'The password needs at least 8 characters';

  @override
  String get backupPassphraseMismatch => 'The two passwords do not match';

  @override
  String get backupMake => 'Make a backup';

  @override
  String get backupMade => 'Backup made — now send it somewhere safe';

  @override
  String get backupRestore => 'Restore from a backup';

  @override
  String get restoreTitle => 'Restore from a backup';

  @override
  String get restorePick => 'Choose the backup file';

  @override
  String restoreMadeOn(String when) {
    return 'This backup was made on $when';
  }

  @override
  String get restoreOpen => 'Open backup';

  @override
  String get restoreFound => 'In this backup';

  @override
  String restoreCounts(String bills, String parties, String items) {
    return '$bills bills · $parties customers/suppliers · $items items';
  }

  @override
  String restoreLastEntry(String date) {
    return 'Last entry: $date';
  }

  @override
  String get restoreWarning =>
      'This replaces the books on this phone now. They are not deleted — they are kept aside.';

  @override
  String get restoreConfirm => 'Yes, restore';

  @override
  String get restoreRestarting => 'Bringing your books back…';

  @override
  String get setupRestore => 'Already have books? Restore from a backup';

  @override
  String get partyArchive => 'Hide from the khata';

  @override
  String get partyArchiveConfirm =>
      'This name will no longer show in the khata list. Their history stays exactly as it was, and they can be brought back from \'Hidden\' in Settings.';

  @override
  String get partyArchived => 'Hidden from the khata';

  @override
  String get recycleTitle => 'Hidden';

  @override
  String get recycleItems => 'Items';

  @override
  String get recycleParties => 'Customers and suppliers';

  @override
  String get recycleEmpty => 'Nothing has been hidden';

  @override
  String get recycleRestore => 'Bring back';

  @override
  String recycleRestored(String name) {
    return '$name is back';
  }

  @override
  String get purchaseReturnTitle => 'Send goods back to the supplier';

  @override
  String get purchaseReturnRefund => 'Refunded by the supplier now';

  @override
  String get chequeDue => 'Can be banked on';

  @override
  String get chequeDueToday => 'Today';

  @override
  String chequeDueInDays(String days) {
    return 'In $days days';
  }

  @override
  String get chequeDuePick => 'Pick a date';

  @override
  String chequeDueOn(String date) {
    return 'Date: $date';
  }

  @override
  String get chequeNeedsCustomer =>
      'Take a cheque only from a named customer — if it bounces, who would you ask?';

  @override
  String get homeCheques => 'Cheques';

  @override
  String get chequesInHand => 'In hand';

  @override
  String get chequesBounced => 'Bounced';

  @override
  String get chequesEmpty => 'No cheques in hand';

  @override
  String get chequesEmptyHint =>
      'A cheque taken on a bill or a khata shows up here';

  @override
  String get chequeDueTodayChip => 'Bank today';

  @override
  String chequeDueInChip(String days) {
    return '$days days to go';
  }

  @override
  String chequeOverdueChip(String days) {
    return '$days days overdue';
  }

  @override
  String get chequeNoDate => 'No date';

  @override
  String get chequeAtBank => 'At the bank';

  @override
  String get chequeDeposit => 'Taken to the bank';

  @override
  String get chequeClear => 'Cleared';

  @override
  String get chequeBounce => 'Bounced';

  @override
  String get chequeClearInto => 'Into which account';

  @override
  String get chequeBounceReason => 'What the bank wrote (optional)';

  @override
  String chequeBounceWarning(String amount, String name) {
    return '$amount goes back onto $name\'s khata.';
  }

  @override
  String chequeNoticeBy(String date) {
    return 'Send the 489-F notice by $date';
  }

  @override
  String chequeBouncedOn(String date) {
    return 'Bounced $date';
  }

  @override
  String chequeNotYet(String date) {
    return 'The bank will not take it before $date';
  }

  @override
  String homeChequesDue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheques are due at the bank',
      one: '1 cheque is due at the bank',
    );
    return '$_temp0';
  }

  @override
  String get chequeNoticeTitle => '489-F notice';

  @override
  String get chequeNoticeHint =>
      'Drawn up from your books. Have your advocate check it before it is sent.';

  @override
  String get chequeNoticeShare => 'Share the notice PDF';

  @override
  String chequeNoticeLate(String date) {
    return 'The time to serve it ended on $date';
  }

  @override
  String get tenderChequeBounced => 'This customer has had a cheque bounce';

  @override
  String tenderChequeBouncedDetail(int count, String owed) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheques came back',
      one: '1 cheque came back',
    );
    return '$_temp0 and $owed is still owed. Take cash, or give credit knowingly.';
  }

  @override
  String get tenderChequeBouncedAllow => 'Give it anyway';

  @override
  String khataChequeBounced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bounced cheques',
      one: '1 bounced cheque',
    );
    return '$_temp0';
  }

  @override
  String get chequeBounceFee => 'Bank fee, if charged (optional)';

  @override
  String get chequeBounceFeeFrom => 'Which account it came out of';

  @override
  String chequeBounceFeeNote(String chequeNo, String name) {
    return 'Bank fee on bounced cheque $chequeNo ($name)';
  }

  @override
  String chequeBounceFeeFailed(String error) {
    return 'The bounce is saved, but the bank fee was not: $error';
  }

  @override
  String get payByCheque => 'Paid by cheque';

  @override
  String get payChequeDrawnOn => 'Drawn on which bank account';

  @override
  String get chequesIssued => 'Cheques we wrote';

  @override
  String get chequeIssuedPresentable => 'Can be presented';

  @override
  String get chequeIssuedPaid => 'Paid by the bank';

  @override
  String chequeIssuedBounceWarning(String amount, String name) {
    return '$amount will be owed to $name again.';
  }

  @override
  String homeChequesIssuedDue(String amount, String days) {
    return 'Rs $amount of our cheques can be presented within $days days — keep it in the bank';
  }

  @override
  String get partyPriceTier => 'Which price they pay';

  @override
  String get partyTierRetail => 'Retail';

  @override
  String get partyTierWholesale => 'Wholesale';

  @override
  String get partyDiscount => 'Discount on every item % (optional)';

  @override
  String get partyDiscountInvalid => 'Enter a number from 0 to 100';

  @override
  String get partyAddress => 'Address';

  @override
  String get partyCity => 'City';

  @override
  String get partyCnic => 'CNIC (optional)';

  @override
  String get homeQuotations => 'Quotations';

  @override
  String get quotationsTitle => 'Quotations';

  @override
  String get quotationsEmpty => 'No quotations yet';

  @override
  String get quotationsEmptyHint =>
      'Tap \"Make a quotation\" on a bill\'s payment sheet';

  @override
  String get quotationMake => 'Make a quotation';

  @override
  String quotationSaved(String docNo) {
    return 'Quotation $docNo saved';
  }

  @override
  String quotationBilledAs(String docNo) {
    return 'Billed as $docNo';
  }

  @override
  String get quotationExpired => 'Expired';

  @override
  String get quotationOpen => 'Open';

  @override
  String quotationValidUntil(String date) {
    return 'until $date';
  }

  @override
  String get quotationSharePdf => 'Send PDF';

  @override
  String get quotationBill => 'Make the bill from it';

  @override
  String get quotationCounterBusy =>
      'A bill is already on the counter. Finish or clear it first.';

  @override
  String get quotationItemGone =>
      'An item on this quotation is no longer in the list. Bring it back and try again.';

  @override
  String get homeChallans => 'Challan';

  @override
  String get challansTitle => 'Delivery challans';

  @override
  String get challansEmpty => 'No challans yet';

  @override
  String get challansEmptyHint =>
      'To send goods before the bill, tap \"Make challan\" on the payment sheet';

  @override
  String get challanMake => 'Make challan';

  @override
  String challanSaved(String docNo) {
    return 'Challan $docNo made, goods sent';
  }

  @override
  String get challanNeedsCustomer =>
      'A challan needs the customer\'s name. Pick the customer first.';

  @override
  String get challanUnbilled => 'Not billed yet';

  @override
  String get challanCancelled => 'Goods came back';

  @override
  String get challanCancel => 'Goods came back';

  @override
  String get challanCancelReason => 'Challan returned';

  @override
  String challanCancelConfirm(String docNo) {
    return 'All the goods on challan $docNo go back on the shelf. Sure?';
  }

  @override
  String get chargeTitle => 'Charge to khata';

  @override
  String get chargeAmount => 'Amount to charge';

  @override
  String get chargeNote => 'What it is for (required)';

  @override
  String get chargeSave => 'Add to khata';

  @override
  String chargeSaved(String amount) {
    return '$amount added to the khata';
  }

  @override
  String get chargeNeedsAmount => 'Enter an amount';

  @override
  String get chargeNeedsNote =>
      'Say what the charge is for, or the customer will not pay it';

  @override
  String chargeBounceFee(String name) {
    return 'Charge this fee to $name too';
  }

  @override
  String chargeBounceFeeNote(String chequeNo) {
    return 'Bank fee for bounced cheque $chequeNo';
  }

  @override
  String get homeReports => 'Reports';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportProfitAndLoss => 'Profit and loss';

  @override
  String get reportProfitAndLossHint =>
      'Sales, cost of goods, expenses and what was left';

  @override
  String get reportSalesByItem => 'Sales by item';

  @override
  String get reportSalesByItemHint => 'What sold, how much, and what it made';

  @override
  String get reportExpenses => 'Expenses';

  @override
  String get reportExpensesHint => 'Rent, bijli, wages: where the money went';

  @override
  String get reportCashBook => 'Cash book';

  @override
  String get reportCashBookHint =>
      'What came into the drawer, what left, what should be there';

  @override
  String get reportDayBook => 'Day book';

  @override
  String get reportDayBookHint => 'Every entry in the books, in order';

  @override
  String get reportStockValue => 'Stock value';

  @override
  String get reportStockValueHint => 'What the goods on the shelf cost';

  @override
  String get reportToday => 'Today';

  @override
  String get reportThisMonth => 'This month';

  @override
  String get reportLastMonth => 'Last month';

  @override
  String get reportThisYear => 'This year';

  @override
  String get reportAsOfNow => 'As of now';

  @override
  String get reportShareCsv => 'Send CSV';

  @override
  String get reportSalesByDay => 'Sales by day';

  @override
  String get reportSalesByDayHint => 'Each day\'s bills, sales and udhaar';

  @override
  String get reportReceivables => 'Udhaar by age';

  @override
  String get reportReceivablesHint => 'Who owes what, and for how long';

  @override
  String get reportSharePdf => 'Send PDF';

  @override
  String get reportPayables => 'Owed to suppliers';

  @override
  String get reportPayablesHint =>
      'What the shop owes each supplier, and for how long';

  @override
  String get chequeDone => 'Done';
}
