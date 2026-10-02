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
  String get usersTitle => 'Staff and PINs';

  @override
  String get usersMyPin => 'Set my PIN';

  @override
  String get usersAdd => 'Add staff';

  @override
  String get usersName => 'Name';

  @override
  String get usersPin => 'PIN (4 to 6 digits)';

  @override
  String get usersPinAgain => 'PIN again';

  @override
  String get usersPinMismatch => 'The two PINs do not match';

  @override
  String get usersPinInvalid => 'A PIN is 4 to 6 digits';

  @override
  String get usersPinSaved => 'PIN saved';

  @override
  String get usersNoPin => 'No PIN';

  @override
  String get usersInactive => 'Not on staff';

  @override
  String get usersRemove => 'Remove from staff';

  @override
  String get usersLetBack => 'Let back in';

  @override
  String get usersNewPin => 'New PIN';

  @override
  String get usersRole => 'Role';

  @override
  String get usersOwnerPinFirst =>
      'Set your own PIN first, so staff cannot open your screens.';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleAccountant => 'Accountant';

  @override
  String get roleCashier => 'Cashier';

  @override
  String get signInTitle => 'Who is it?';

  @override
  String get signInPin => 'PIN';

  @override
  String get signInOpen => 'Open';

  @override
  String get signInWrong => 'Wrong PIN';

  @override
  String get homeLock => 'Lock';

  @override
  String homeSignedInAs(String name, String role) {
    return '$name ($role)';
  }

  @override
  String get homeDayClose => 'Close day';

  @override
  String get dayCloseTitle => 'Close the day';

  @override
  String get dayCloseExpected => 'In the drawer, by the books';

  @override
  String get dayCloseCounted => 'Counted in the drawer';

  @override
  String get dayCloseNote => 'Why it differs (optional)';

  @override
  String get dayCloseSave => 'Close the day';

  @override
  String get dayCloseMatches => 'The drawer matches the books';

  @override
  String dayCloseShort(String amount) {
    return '$amount short';
  }

  @override
  String dayCloseOver(String amount) {
    return '$amount over';
  }

  @override
  String get dayCloseDone => 'Day closed';

  @override
  String dayCloseLast(String when, String name) {
    return 'Last closed: $when, by $name';
  }

  @override
  String get auditTitle => 'Activity';

  @override
  String get auditEveryone => 'Everyone';

  @override
  String get auditEmpty => 'Nothing has happened yet';

  @override
  String get reportTrialBalance => 'Trial balance';

  @override
  String get reportTrialBalanceHint =>
      'Every account on its side, and the two sides agreeing';

  @override
  String get reportBalanceSheet => 'Balance sheet';

  @override
  String get reportBalanceSheetHint =>
      'What the shop has, what it owes, and what is the owner\'s';

  @override
  String get homeAccounts => 'Accounts';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get accountsWriteVoucher => 'Write a voucher';

  @override
  String get accountTypeAsset => 'What the shop has';

  @override
  String get accountTypeLiability => 'What it owes';

  @override
  String get accountTypeEquity => 'The owner\'s';

  @override
  String get accountTypeIncome => 'Income';

  @override
  String get accountTypeExpense => 'Expenses';

  @override
  String get accountLedgerEmpty => 'Nothing posted to this account yet';

  @override
  String get journalTitle => 'Journal voucher';

  @override
  String get journalNarration => 'What it is for (required)';

  @override
  String get journalDebit => 'Debit';

  @override
  String get journalCredit => 'Credit';

  @override
  String get journalAddLine => 'Another line';

  @override
  String get journalSave => 'Save voucher';

  @override
  String journalSaved(String entryNo) {
    return 'Voucher $entryNo saved';
  }

  @override
  String journalDifference(String amount) {
    return 'Difference: $amount';
  }

  @override
  String get journalBalanced => 'Both sides agree';

  @override
  String get journalPickAccount => 'Pick an account';

  @override
  String get firmsTitle => 'Shops and firms';

  @override
  String get firmsAdd => 'New firm';

  @override
  String get firmsName => 'Firm name';

  @override
  String get firmsOwner => 'Owner\'s name';

  @override
  String get firmsCity => 'City';

  @override
  String get firmsOpen => 'Open';

  @override
  String get firmsCurrent => 'Open now';

  @override
  String firmsAdded(String name) {
    return '$name added';
  }

  @override
  String firmsSwitched(String name) {
    return '$name is open now';
  }

  @override
  String posScannedExpired(String batch, String date) {
    return 'Batch $batch expired on $date. Do not sell it.';
  }

  @override
  String posSerialAlreadyOnBill(String serial) {
    return '$serial is already on the bill';
  }

  @override
  String get posScanTheSerial =>
      'This item is sold by serial / IMEI. Scan or type its number.';

  @override
  String get reportExpiry => 'Expiry';

  @override
  String get reportExpiryHint =>
      'Batches past their date, and those coming up to it';

  @override
  String get itemTracksBatch => 'By batch and expiry';

  @override
  String get itemTracksSerial => 'By serial / IMEI';

  @override
  String get purchaseBatch => 'Batch no.';

  @override
  String get purchaseExpiry => 'Expiry';

  @override
  String get purchaseSerials => 'Serial / IMEI (one per line)';

  @override
  String purchaseSerialCount(int count) {
    return '$count numbers';
  }

  @override
  String get purchaseSerialsNeeded => 'Enter each piece\'s serial / IMEI';

  @override
  String get purchaseBatchNeeded =>
      'Enter the batch no., and the expiry as YYYY-MM-DD';

  @override
  String get placesTitle => 'Where it is';

  @override
  String get placesMain => 'Shop floor';

  @override
  String get placesBatches => 'Batches';

  @override
  String get placesSerials => 'Serial / IMEI';

  @override
  String get placesMove => 'Move goods';

  @override
  String get placesTo => 'To (e.g. GODOWN)';

  @override
  String get placesMoveButton => 'Move';

  @override
  String get placesMoved => 'Goods moved';

  @override
  String get partyTaxRegistered => 'Registered for sales tax';

  @override
  String get partyOnAtl => 'On the Active Taxpayers List';

  @override
  String get taxTitle => 'Tax';

  @override
  String get taxNeverSent =>
      'Everything is worked out on this phone and sent nowhere. File the return yourself, or through your accountant, on IRIS.';

  @override
  String get taxRegistered => 'The shop is registered for sales tax';

  @override
  String get taxRegisteredHint =>
      'A registered shop charges 18% sales tax on its bills; an unregistered one charges none';

  @override
  String get taxPricesInclude => 'Prices include tax';

  @override
  String get taxTajirDost => 'Tajir Dost 1%';

  @override
  String get taxTurnoverThisMonth => 'This month\'s sales';

  @override
  String get taxFixedAtOnePercent => '1% fixed tax';

  @override
  String get taxUtilityWht => 'Tax already taken on the electricity bill';

  @override
  String get taxToPay => 'To pay';

  @override
  String get reportSalesTax => 'Sales tax';

  @override
  String get reportSalesTaxHint =>
      'The sales tax and further tax owed for the period';

  @override
  String get reportTajirDost => 'Tajir Dost 1%';

  @override
  String get reportTajirDostHint => 'One per cent of each month\'s sales';

  @override
  String get paySection73 =>
      'Section 73: paying more than Rs 50,000 in cash loses the input tax on these goods. Pay through the bank or by cheque.';

  @override
  String get syncTitle => 'Counters on wi-fi';

  @override
  String get syncStaysInShop =>
      'Counters sync over the shop\'s own wi-fi. Nothing goes to the internet.';

  @override
  String get syncHostSwitch => 'Let counters sync with this phone';

  @override
  String get syncHostHint =>
      'This phone is the master. Keep it open on the shop\'s wi-fi.';

  @override
  String get syncAddress => 'Address for counters';

  @override
  String get syncNoAddress => 'This phone is not on a wi-fi network';

  @override
  String get syncLetJoin => 'Let a counter join';

  @override
  String get syncJoinCode => 'Type this code on the counter';

  @override
  String get syncDevices => 'Phones of this shop';

  @override
  String get syncMasterRole => 'Master';

  @override
  String syncCounterRole(String prefix) {
    return 'Counter · bills $prefix';
  }

  @override
  String get syncThisPhone => 'This phone';

  @override
  String syncLastSynced(String when) {
    return 'Last synced $when';
  }

  @override
  String get syncNever => 'Not synced yet';

  @override
  String get syncNow => 'Sync now';

  @override
  String syncDone(String sent, String received) {
    return 'Sent $sent, received $received';
  }

  @override
  String syncConflicts(String count) {
    return '$count clashes kept under a marked name';
  }

  @override
  String syncCounterOf(String host) {
    return 'This phone is a counter of the master at $host. It syncs by itself every half minute.';
  }

  @override
  String get syncJoinTitle => 'Join a shop\'s master phone';

  @override
  String get syncJoinHint =>
      'On the master: Settings, Counters on wi-fi, Let a counter join. Both phones on the same wi-fi.';

  @override
  String get syncMasterAddress => 'Master\'s address';

  @override
  String get syncCode => 'Code shown on the master';

  @override
  String get syncCounterName => 'Name of this counter';

  @override
  String get syncCounterNameHint => 'e.g. Counter 2';

  @override
  String get syncJoin => 'Join';

  @override
  String get importTitle => 'Import from Excel';

  @override
  String get importHint =>
      'Choose your old list as .xlsx, .xls or .csv. The first row should name the columns, e.g. Name, Sale price, Stock.';

  @override
  String get importItems => 'Items';

  @override
  String get importParties => 'Khata';

  @override
  String get importPick => 'Choose file';

  @override
  String importReady(String count) {
    return '$count rows ready';
  }

  @override
  String importProblems(String count) {
    return '$count rows cannot come in';
  }

  @override
  String importRun(String count) {
    return 'Bring in $count';
  }

  @override
  String importDone(String added, String skipped) {
    return '$added brought in, $skipped left out';
  }

  @override
  String importColumns(String columns) {
    return 'Columns: $columns';
  }

  @override
  String get settingsBooksEncrypted => 'The books on this phone are encrypted';

  @override
  String get settingsBooksPlain =>
      'The books on this phone are not encrypted: its keystore could not keep a key';

  @override
  String settingsCrashes(String count) {
    return 'The app hit $count errors on this phone';
  }

  @override
  String get settingsCrashesClear => 'Clear';

  @override
  String get itemVipPrice => 'VIP price';

  @override
  String get partyTierVip => 'VIP';

  @override
  String posScaleUnknown(String plu) {
    return 'No item has the code $plu from this scale label';
  }

  @override
  String posScaleNoPrice(String name) {
    return '$name has no price, so the weight cannot be worked out from the label\'s price';
  }

  @override
  String get scaleTitle => 'Weighing-scale labels';

  @override
  String get scaleHint =>
      'A scale\'s label carries the item\'s PLU and its weight or price. Give each item the same code as its PLU on the scale.';

  @override
  String get scaleWeightPrefixes =>
      'Prefixes that carry a weight (e.g. 21, 22)';

  @override
  String get scalePricePrefixes => 'Prefixes that carry a price (e.g. 23, 24)';

  @override
  String get scalePluDigits => 'Digits of PLU';

  @override
  String get scalePriceInPaisa => 'Prices are printed in paisa';

  @override
  String get scaleSave => 'Save';

  @override
  String get scaleSaved => 'Scale labels saved';

  @override
  String get recipesTitle => 'Making (recipes)';

  @override
  String get recipesNew => 'New recipe';

  @override
  String get recipesEmpty =>
      'No recipes yet. Write one for anything the shop makes itself.';

  @override
  String recipesMakes(String qty, String unit, String name) {
    return 'One batch: $qty $unit of $name';
  }

  @override
  String get recipesMake => 'Make';

  @override
  String get recipesRuns => 'How many batches';

  @override
  String recipesMade(String no, String qty, String name) {
    return '$no: $qty of $name made';
  }

  @override
  String get recipesName => 'Recipe name';

  @override
  String get recipesOutput => 'What it makes';

  @override
  String get recipesPickItem => 'Choose an item';

  @override
  String get recipesBatchMakes => 'How much one batch makes';

  @override
  String get recipesOverhead => 'Work and packing (Rs)';

  @override
  String get recipesComponents => 'What goes in (per batch)';

  @override
  String get recipesPerBatch => 'Per batch';

  @override
  String get recipesAddComponent => 'Add a component';

  @override
  String get recipesSave => 'Save';

  @override
  String get vansTitle => 'Vans';

  @override
  String get vansNew => 'New van';

  @override
  String get vansName => 'Van name';

  @override
  String get vansAdd => 'Add';

  @override
  String get vansEmpty => 'No vans yet';

  @override
  String get vansThisPhone => 'This phone sells from';

  @override
  String get vansShopFloor => 'The shop';

  @override
  String vansToday(String count) {
    return 'Today $count bills, cash:';
  }

  @override
  String vansSettled(String amount) {
    return 'Settled: $amount handed in';
  }

  @override
  String get vansLoad => 'Load';

  @override
  String get vansSettle => 'Settle';

  @override
  String get vansOnBoard => 'On the van';

  @override
  String get vansQty => 'Quantity';

  @override
  String get vansExpected => 'The rider should have';

  @override
  String get vansCounted => 'The rider handed in (Rs)';

  @override
  String get vansReturnUnsold => 'Unsold stock back to the shop';

  @override
  String get vansSettledEven => 'Settled, even';

  @override
  String vansSettledShort(String amount) {
    return 'Settled, $amount short';
  }

  @override
  String vansSettledOver(String amount) {
    return 'Settled, $amount over';
  }

  @override
  String get fbrTitle => 'FBR digital invoicing';

  @override
  String get fbrWhatIsSent =>
      'When on, each bill (items, prices, tax, the buyer\'s NTN) is sent to FBR. When off, nothing is sent.';

  @override
  String get fbrReport => 'Report every bill to FBR';

  @override
  String get fbrSandbox => 'FBR\'s test gateway (sandbox)';

  @override
  String get fbrToken => 'Token from PRAL';

  @override
  String get fbrBaseUrl => 'Integrator address (empty = FBR)';

  @override
  String get fbrSave => 'Save';

  @override
  String get fbrSaved => 'FBR settings saved';

  @override
  String get fbrBills => 'Bills for FBR';

  @override
  String get fbrSendNow => 'Send now';

  @override
  String fbrSent(String posted, String rejected, String waiting) {
    return '$posted accepted, $rejected refused, $waiting waiting';
  }

  @override
  String get fbrPosted => 'Accepted';

  @override
  String get fbrRejected => 'Refused';

  @override
  String get fbrPending => 'Waiting';

  @override
  String get fbrLate => 'Past 72 hours; issue a credit note';

  @override
  String get fbrRetry => 'Send again';

  @override
  String get driveTitle => 'Daily backup to Google Drive';

  @override
  String get driveExplain =>
      'Every day, when the app opens, the books are sealed with the passphrase above and sent to the app folder on your own Google Drive. The newest 7 are kept. A new phone needs the same Google account and this passphrase.';

  @override
  String get driveTurnOn => 'Turn on Drive backup';

  @override
  String get driveTurnOff => 'Turn off Drive backup';

  @override
  String get driveOn => 'Drive backup is on';

  @override
  String driveLast(String when) {
    return 'Last Drive backup: $when';
  }

  @override
  String driveFailed(String reason) {
    return 'Did not reach Drive: $reason';
  }

  @override
  String get driveNow => 'Back up to Drive now';

  @override
  String get driveRestore => 'Restore from Google Drive';

  @override
  String get driveNone => 'No backups found on Drive';

  @override
  String get drivePick => 'Which backup to restore?';

  @override
  String get planTitle => 'Plan';

  @override
  String planCurrent(String plan) {
    return 'Your plan: $plan';
  }

  @override
  String planPerYear(String price) {
    return '$price a year';
  }

  @override
  String get planBuy => 'Get this plan';

  @override
  String get planIsYours => 'This is your plan';

  @override
  String get planRestore => 'Bought already? Restore';

  @override
  String get planNoBilling =>
      'Plans cannot be bought in this build. Buy from the Play Store app.';

  @override
  String planNeeded(String plan) {
    return 'This needs the $plan plan';
  }

  @override
  String get planTestTitle => 'Testing only: pick a plan';

  @override
  String get planTestNote =>
      'Only in test builds, never in the released app. Nothing is charged.';

  @override
  String get planTestReal => 'As bought';

  @override
  String planTestActive(String plan) {
    return 'Test plan in use: $plan';
  }

  @override
  String get planFreeIncludes =>
      'Always free: bills, khata, stock, cash book, printing, WhatsApp and backup by hand.';

  @override
  String get planFeatNoWatermark => 'No \'Bazaar Ledger\' line on bills';

  @override
  String get planFeatAutoDriveBackup => 'Daily Google Drive backup';

  @override
  String get planFeatCheques => 'Post-dated cheques';

  @override
  String get planFeatPriceLists => 'Wholesale and VIP prices';

  @override
  String get planFeatAccountingReports =>
      'Profit and loss, balance sheet and tax reports';

  @override
  String get planFeatTracking => 'Batch, expiry and serial/IMEI';

  @override
  String get planFeatScaleLabels => 'Weighing-scale labels';

  @override
  String get planFeatGodowns => 'Godowns and stock transfers';

  @override
  String get planFeatLanSync => 'Several counters on wi-fi';

  @override
  String get planFeatFbr => 'Live FBR invoicing';

  @override
  String get planFeatManufacturing => 'Recipes and production';

  @override
  String get planFeatVans => 'Van sales';

  @override
  String planFirms(int count) {
    return 'Up to $count firms';
  }

  @override
  String get planFirmsUnlimited => 'Unlimited firms';

  @override
  String planUsers(int count) {
    return 'Up to $count people with their own PIN';
  }

  @override
  String get planUsersUnlimited => 'Unlimited people';

  @override
  String get syncFind => 'Find the master on wi-fi';

  @override
  String get syncFindNone =>
      'No master found. Put both phones on the same wi-fi, or type its address.';

  @override
  String get reportPurchaseRegister => 'Purchase register';

  @override
  String get reportPurchaseRegisterHint =>
      'Every purchase bill, with the supplier\'s NTN and tax';

  @override
  String get statementShare => 'Statement of account (PDF)';

  @override
  String get statementThisMonth => 'This month';

  @override
  String get statementLastMonth => 'Last month';

  @override
  String get statementThisYear => 'This year';

  @override
  String get statementAll => 'From the start';

  @override
  String get chargeCancel => 'Cancel this charge';

  @override
  String chargeCancelConfirm(String no) {
    return 'Cancel $no? It comes off the khata.';
  }

  @override
  String get chargeCancelReason => 'Charge cancelled';

  @override
  String get chargeCancelled => 'Charge cancelled';

  @override
  String challanBillAll(int count) {
    return 'Bill with this customer\'s $count other challans';
  }

  @override
  String get accountsAdd => 'New account';

  @override
  String get accountsAddName => 'Account name';

  @override
  String get accountsTypeAsset => 'Asset';

  @override
  String get accountsTypeLiability => 'Liability';

  @override
  String get accountsTypeEquity => 'Equity';

  @override
  String get accountsTypeIncome => 'Income';

  @override
  String get accountsTypeExpense => 'Expense';

  @override
  String get accountsCloseYear => 'Close the year';

  @override
  String accountsCloseYearConfirm(String year) {
    return 'The profit of $year moves into retained earnings. Close it?';
  }

  @override
  String accountsYearClosed(String no) {
    return 'Year closed ($no)';
  }

  @override
  String get vansSettleYesterday => 'Settle yesterday, not today';

  @override
  String get syncClashHint =>
      'Two counters made two things with the same code or barcode. Both are kept; the second carries a ~ mark. Put it right, then tap Done.';

  @override
  String get syncClashDone => 'Done';

  @override
  String get chequeDone => 'Done';

  @override
  String quickAddCustomer(String name) {
    return 'Add \'$name\' as a new customer';
  }

  @override
  String quickAddSupplier(String name) {
    return 'Add \'$name\' as a new supplier';
  }

  @override
  String quickAddItem(String name) {
    return 'Add \'$name\' as a new item';
  }

  @override
  String quickAddBarcode(String code) {
    return 'Make a new item with barcode $code';
  }

  @override
  String quickAddCode(String code) {
    return 'Make a new item with code $code';
  }

  @override
  String get quickAddScaleHint =>
      'Once it has a code, every label the scale prints for it rings up by itself.';

  @override
  String get quickBackToBill => 'Back to the bill';

  @override
  String get quickSupplierTitle => 'New supplier';

  @override
  String get quickPartyMobile => 'Mobile (optional)';

  @override
  String get quickPartyMobileHint => '0300 1234567';

  @override
  String get quickPartyMobileInvalid =>
      'Enter a mobile number, like 0300 1234567';

  @override
  String get quickPartyCreditLimit => 'Credit limit (optional)';

  @override
  String get quickPartyTwins => 'Already in the khata';

  @override
  String get quickPartyTwinsHint =>
      'If it is them, tap their name. If it is somebody else, add a new one.';

  @override
  String get quickAddAnyway => 'No, add a new one';

  @override
  String get quickItemTwins => 'Already an item';

  @override
  String get quickItemTwinsHint =>
      'If it is this, tap it. If it is something else, add a new one.';

  @override
  String get quickItemBuyingAt => 'Buying price, per unit';

  @override
  String get quickItemNoCost =>
      'What it cost and how many are on the shelf are for the owner to add later, from Items.';

  @override
  String entryReceiptTitle(String no) {
    return 'Receipt $no';
  }

  @override
  String entryPaymentTitle(String no) {
    return 'Payment $no';
  }

  @override
  String get entryDate => 'Date';

  @override
  String get entryHow => 'How';

  @override
  String get entryAccount => 'Account';

  @override
  String get entryFrom => 'Received from';

  @override
  String get entryTo => 'Paid to';

  @override
  String get entryReference => 'Reference or note';

  @override
  String get entryEnteredBy => 'Entered by';

  @override
  String get entrySettled => 'Bills it went against';

  @override
  String get entryShare => 'Send the receipt (PDF)';

  @override
  String get entryCancel => 'Cancel it';

  @override
  String get entryCancelTitle => 'Cancel this entry';

  @override
  String get entryCancelExplain =>
      'Nothing is deleted. A reversing entry is written today, the original stays in the books marked cancelled, and any bills it paid are owed again.';

  @override
  String get entryCancelled => 'Cancelled';

  @override
  String entryCancelledWhy(String reason) {
    return 'Cancelled: $reason';
  }

  @override
  String entryReplaces(String no) {
    return 'Entered in place of $no';
  }

  @override
  String entryReplacedBy(String no) {
    return 'Replaced by $no';
  }

  @override
  String entryTakenWithBill(String no) {
    return 'This money was taken at the counter with bill $no, and goes with it. Open the bill to return or cancel it.';
  }

  @override
  String get entryChequeAtBank =>
      'The cheque is at the bank. Wait for it to clear or bounce, and mark it on the Cheques screen.';

  @override
  String get entryChequeCleared =>
      'The cheque has cleared and the money is in the bank, so it cannot be cancelled.';

  @override
  String get entryChequeBounced =>
      'The cheque bounced. What it paid is already back on the khata.';

  @override
  String get entryNotAllowed =>
      'Only the owner, a manager or the accountant can change or cancel this.';

  @override
  String get entryOpenBill => 'Open the bill';

  @override
  String entryEditTitle(String no) {
    return 'Correct $no';
  }

  @override
  String get entryEditExplain =>
      'The old entry is cancelled and the corrected one written, dated today. Both stay in the books.';

  @override
  String get entryEditReason => 'What was wrong (optional)';

  @override
  String get entryEditReasonDefault => 'Entered wrong';

  @override
  String get entryEditSave => 'Save the correction';

  @override
  String entryEditSaved(String no, String newNo) {
    return '$no corrected, now $newNo';
  }

  @override
  String entryPaidBy(String nos) {
    return '$nos has been paid against this. Open that payment and cancel it first.';
  }

  @override
  String chargeEntryHint(String amount) {
    return 'A charge of $amount. Correct it if the amount or reason is wrong; take it back if it should not be there.';
  }

  @override
  String get openingTitle => 'Correct the opening balance';

  @override
  String get openingNow => 'Entered now';

  @override
  String get openingNew => 'The right opening balance';

  @override
  String get openingExplain =>
      'The old opening entry is reversed and the right figure posted. The khata starts from the new figure.';

  @override
  String get openingCorrect => 'Correct it';

  @override
  String get openingSaved => 'Opening balance corrected';

  @override
  String get reasonPick => 'Pick a reason';

  @override
  String get reasonWrongEntry => 'Wrong entry';

  @override
  String get reasonDuplicate => 'Duplicate entry';

  @override
  String get reasonWrongAmount => 'Wrong amount';

  @override
  String get reasonDispute => 'Customer dispute';

  @override
  String get reasonOther => 'Other';

  @override
  String get reasonDetail => 'Details (optional)';

  @override
  String entryCancelledBy(String name, String when) {
    return 'Cancelled by $name, $when';
  }

  @override
  String get salesSearch => 'Find a bill';

  @override
  String get salesSearchHint => 'Bill number, name, phone or amount';

  @override
  String get salesClearSearch => 'Clear the search';

  @override
  String get salesPeriodAll => 'Any day';

  @override
  String get salesPeriodToday => 'Today';

  @override
  String get salesPeriodWeek => 'This week';

  @override
  String get salesPeriodMonth => 'This month';

  @override
  String get salesPeriodLastMonth => 'Last month';

  @override
  String get salesPeriodPick => 'Pick dates';

  @override
  String salesPeriodRange(String from, String to) {
    return '$from to $to';
  }

  @override
  String get salesStandingAll => 'Every bill';

  @override
  String get salesStandingPaid => 'Paid up';

  @override
  String get salesStandingUdhaar => 'Still owed';

  @override
  String get salesStandingCancelled => 'Cancelled ones';

  @override
  String get salesNoneFound => 'No bill matches';

  @override
  String get salesNoneFoundHint => 'Try another name, number or date';

  @override
  String get salesClearFilters => 'Show every bill';

  @override
  String get sendAction => 'Send';

  @override
  String sendTitle(String docNo) {
    return 'Send $docNo';
  }

  @override
  String get sendWalkIn => 'Walk-in customer, no number';

  @override
  String get sendWhatsApp => 'Send on WhatsApp';

  @override
  String get sendWhatsAppShort => 'WhatsApp';

  @override
  String sendWhatsAppTo(String name) {
    return 'Opens the chat with $name, the bill written out';
  }

  @override
  String get sendWhatsAppNoNumber =>
      'No number, so the PDF goes through the share sheet';

  @override
  String get sendNoNumber =>
      'No WhatsApp number for this customer, so the PDF went to the share sheet';

  @override
  String get sendNoWhatsApp =>
      'WhatsApp is not on this phone, so the PDF went to the share sheet';

  @override
  String get sendPdfHint => 'The file, with the bill written out beside it';

  @override
  String get sendPicture => 'Send a picture';

  @override
  String get sendPictureShort => 'Picture';

  @override
  String get sendPictureHint =>
      'A picture of the bill, opens right in the chat';

  @override
  String get sendPrintHint => 'On the printer at this counter';

  @override
  String get documentView => 'Open it';

  @override
  String get purchaseSendBack => 'Send goods back';

  @override
  String get reportGroupTransaction => 'Transaction';

  @override
  String get reportGroupParty => 'Party reports';

  @override
  String get reportGroupItemStock => 'Item and stock';

  @override
  String get reportGroupBusiness => 'Business status';

  @override
  String get reportGroupTaxes => 'Taxes';

  @override
  String get reportGroupExpense => 'Expense';

  @override
  String get reportGroupOrders => 'Sale and purchase orders';

  @override
  String get reportGroupLoans => 'Loan accounts';

  @override
  String get reportFavourites => 'Favourites';

  @override
  String get reportRecent => 'Recently opened';

  @override
  String get reportSearchHint => 'Type a report\'s name';

  @override
  String get reportSearchNone => 'No report by that name';

  @override
  String get reportStar => 'Add to favourites';

  @override
  String get reportUnstar => 'Remove from favourites';

  @override
  String get reportSale => 'Sale report';

  @override
  String get reportSaleHint =>
      'Every bill: total, received, balance, how it was paid';

  @override
  String get reportPurchase => 'Purchase report';

  @override
  String get reportPurchaseHint => 'Every purchase bill: total, paid, unpaid';

  @override
  String get reportAllTransactions => 'All transactions';

  @override
  String get reportAllTransactionsHint =>
      'Every bill, return, expense and payment in one place';

  @override
  String get reportBillWiseProfit => 'Bill-wise profit';

  @override
  String get reportBillWiseProfitHint =>
      'What each bill made over what its goods cost';

  @override
  String get reportCashflow => 'Cash flow';

  @override
  String get reportCashflowHint =>
      'Where the money in the drawer and the bank came from and went';

  @override
  String get reportPartyStatement => 'Party statement';

  @override
  String get reportPartyStatementHint =>
      'One party\'s whole account, with the balance after each entry';

  @override
  String get reportPartyProfit => 'Party-wise profit and loss';

  @override
  String get reportPartyProfitHint => 'The profit made on each customer';

  @override
  String get reportAllParties => 'All parties';

  @override
  String get reportAllPartiesHint =>
      'Every party: to receive, to pay, credit limit';

  @override
  String get reportPartyItems => 'Party report by items';

  @override
  String get reportPartyItemsHint =>
      'What a party bought and sold, item by item';

  @override
  String get reportSalePurchaseByParty => 'Sale and purchase by party';

  @override
  String get reportSalePurchaseByPartyHint =>
      'What was sold to and bought from each party';

  @override
  String get reportSalePurchaseByGroup => 'Sale and purchase by party group';

  @override
  String get reportSalePurchaseByGroupHint =>
      'Sales and purchases of each party group';

  @override
  String get reportYesterday => 'Yesterday';

  @override
  String get reportThisWeek => 'This week';

  @override
  String get reportThisQuarter => 'This quarter';

  @override
  String get reportLastYear => 'Last year';

  @override
  String get reportCustom => 'Pick dates';

  @override
  String get reportFilterParty => 'Party';

  @override
  String get reportFilterItem => 'Item';

  @override
  String get reportFilterCategory => 'Item category';

  @override
  String get reportFilterGroup => 'Party group';

  @override
  String get reportFilterType => 'Transaction type';

  @override
  String get reportFilterMode => 'Paid by';

  @override
  String get reportFilterUser => 'Entered by';

  @override
  String get reportFilterStatus => 'Payment';

  @override
  String get reportFilterWithBalance => 'Only with a balance';

  @override
  String get reportFilterClear => 'Clear';

  @override
  String get reportFilterNothing => 'Nothing found';

  @override
  String get reportFilterUngrouped => 'Ungrouped';

  @override
  String get reportStatusPaid => 'Paid';

  @override
  String get reportStatusPartial => 'Partly paid';

  @override
  String get reportStatusUnpaid => 'Unpaid';

  @override
  String get reportTypeSale => 'Sale';

  @override
  String get reportTypeSaleReturn => 'Sale return';

  @override
  String get reportTypePurchase => 'Purchase';

  @override
  String get reportTypePurchaseReturn => 'Purchase return';

  @override
  String get reportTypeExpense => 'Expense';

  @override
  String get reportTypeCharge => 'Charge';

  @override
  String get reportTypeQuotation => 'Quotation';

  @override
  String get reportTypeChallan => 'Challan';

  @override
  String get reportTypeSaleOrder => 'Sale order';

  @override
  String get reportTypePurchaseOrder => 'Purchase order';

  @override
  String get reportTypeProforma => 'Proforma';

  @override
  String get reportTypePaymentIn => 'Payment in';

  @override
  String get reportTypePaymentOut => 'Payment out';

  @override
  String get reportShareExcel => 'Send Excel';

  @override
  String reportShowMore(int shown, int total) {
    return 'Show more ($shown of $total)';
  }

  @override
  String get reportChooseParty => 'Choose a party to see the statement';

  @override
  String reportVsPrevious(String change) {
    return '$change vs the period before';
  }

  @override
  String reportSortedBy(String column) {
    return 'Sort by $column';
  }

  @override
  String get reportExcel => 'Excel';

  @override
  String get reportCsv => 'CSV';

  @override
  String get reportPrint => 'Print';

  @override
  String get reportPrintTitle => 'Print on the receipt printer';

  @override
  String get loansTitle => 'Loans';

  @override
  String get loansNew => 'New loan';

  @override
  String get loansEmpty => 'No loans';

  @override
  String get loansEmptyHint =>
      'Write down a loan from a bank, a committee, a relative or a supplier here. Every instalment is split into what comes off the loan and the interest.';

  @override
  String get loansTotalOwed => 'Owed on all loans';

  @override
  String get loanOwed => 'Outstanding';

  @override
  String loanOf(String amount) {
    return 'of $amount';
  }

  @override
  String loanTakenOn(String date) {
    return 'Taken $date';
  }

  @override
  String get loanCancelled => 'Cancelled';

  @override
  String get loanLender => 'Lent by (bank, committee, relative)';

  @override
  String get loanAmount => 'Amount of the loan';

  @override
  String get loanInto => 'Received into';

  @override
  String loanDate(String date) {
    return 'Date: $date';
  }

  @override
  String get loanPickDate => 'Change the date';

  @override
  String get loanRate => 'Interest (markup), % a year (optional)';

  @override
  String get loanTerm => 'Months to repay (optional)';

  @override
  String get loanInstalment => 'Monthly instalment (optional)';

  @override
  String get loanFee => 'Processing fee (optional)';

  @override
  String loanReceivedAfterFee(String amount) {
    return 'Received after the fee: $amount';
  }

  @override
  String get loanNotes => 'Notes (optional)';

  @override
  String get loanSave => 'Save the loan';

  @override
  String get loanSaved => 'Loan saved';

  @override
  String get loanRepay => 'Pay back';

  @override
  String get loanPaid => 'Amount paid';

  @override
  String get loanInterest => 'Of which interest (markup)';

  @override
  String get loanCharges => 'Charges or penalty (optional)';

  @override
  String get loanFrom => 'Paid from';

  @override
  String get loanPrincipalLine => 'Off the loan';

  @override
  String get loanAfterLine => 'Still owed after it';

  @override
  String get loanRepaySave => 'Save the payment';

  @override
  String loanRepaid(String entryNo) {
    return 'Payment $entryNo saved';
  }

  @override
  String loanInterestSuggested(String rate) {
    return 'Interest worked out at $rate a year. Correct it from the bank\'s slip.';
  }

  @override
  String get loanSharePdf => 'Statement (PDF)';

  @override
  String get loanShareCsv => 'Statement (Excel, CSV)';

  @override
  String get loanOpening => 'Owed at the start';

  @override
  String get loanClosing => 'Owed at the end';

  @override
  String get loanKindReceived => 'Loan received';

  @override
  String get loanKindRepaid => 'Paid back';

  @override
  String get loanKindCancelled => 'Cancelled';

  @override
  String get loanColBorrowed => 'Received';

  @override
  String get loanColPrincipal => 'Principal';

  @override
  String get loanColInterest => 'Interest';

  @override
  String get loanColCharges => 'Fee, charges';

  @override
  String get loanCancelEntry => 'Wrong, cancel it';

  @override
  String get loanCancelReason => 'Why it is being cancelled (required)';

  @override
  String loanCancelDone(String entryNo) {
    return 'Cancelled ($entryNo)';
  }

  @override
  String loanRateShown(String rate) {
    return '$rate a year';
  }

  @override
  String loanInstalmentShown(String amount) {
    return 'Instalment $amount';
  }

  @override
  String get loanAmountInvalid => 'Enter an amount, like 25000 or 2500.50';

  @override
  String get posBillTo => 'Who the bill is for';

  @override
  String posCartEmptyFor(String name) {
    return '$name\'s bill is empty so far';
  }

  @override
  String get looseTitle => 'Loose item';

  @override
  String get looseHint =>
      'Sell it without making an item. Nothing is saved to your items and no stock moves.';

  @override
  String get looseName => 'What it is (optional)';

  @override
  String get looseNameHint => 'e.g. onions';

  @override
  String get looseRate => 'Price (each, or the whole amount)';

  @override
  String looseAmount(String amount) {
    return 'Amount: $amount';
  }

  @override
  String get looseAdd => 'Put on the bill';

  @override
  String get looseNoCost =>
      'Its cost is not known, so profit counts all of it as profit.';

  @override
  String get looseNeedsPrice => 'Type a quantity and a price';

  @override
  String get looseFbrRefused =>
      'This shop reports its bills to FBR, and FBR needs every line\'s HS code. Make it an item instead of selling it loose.';

  @override
  String get looseNotKept =>
      'A loose item cannot go on a quotation or a challan. Make it an item, or bill it now.';

  @override
  String looseOffer(String name) {
    return 'Sell \'$name\' loose (no item is made)';
  }

  @override
  String get looseBadge => 'Loose item · no stock';

  @override
  String get dealsSoldTitle => 'Sold to this customer before';

  @override
  String get dealsBoughtTitle => 'Bought from this supplier before';

  @override
  String get dealsTapHint => 'Tap one to put that price on this line.';

  @override
  String dealLastTime(String price, String date) {
    return 'Last time $price · $date';
  }

  @override
  String dealOtherUnit(String unit) {
    return 'That price is per $unit. Switch the line to $unit first.';
  }

  @override
  String dealUse(String price) {
    return 'Use this price: $price';
  }

  @override
  String dealLastBought(String price, String supplier, String date) {
    return 'Last bought at $price · $supplier · $date';
  }

  @override
  String posBillFor(String name) {
    return 'Bill for $name';
  }

  @override
  String get partyGroup => 'Group (optional)';

  @override
  String get partyGroupHint => 'Area, route or kind';

  @override
  String get partyRemarks => 'Note for the counter';

  @override
  String get partyRemarksHint => 'e.g. Cash only — a cheque bounced';

  @override
  String get groupsTitle => 'Groups';

  @override
  String get groupsEmpty => 'No groups yet';

  @override
  String get groupsEmptyHint =>
      'Type a group on a customer\'s form — area, route or kind — or pick several in the list and set their group at once';

  @override
  String get groupAll => 'All';

  @override
  String get groupNone => 'No group';

  @override
  String groupMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get groupReceivable => 'To receive';

  @override
  String get groupPayable => 'To pay';

  @override
  String get groupRename => 'Rename';

  @override
  String get groupNewName => 'New name';

  @override
  String groupRenameMerges(String name) {
    return '\'$name\' already exists — the two groups will become one';
  }

  @override
  String get groupMerge => 'Merge into another group';

  @override
  String get groupMergeInto => 'Merge into which group?';

  @override
  String groupMergeConfirm(String from, String to) {
    return 'Everyone in \'$from\' moves to \'$to\', and \'$from\' is gone.';
  }

  @override
  String get groupNoOther => 'There is no other group to merge into';

  @override
  String groupMoved(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moved to \'$name\'',
      one: '1 moved to \'$name\'',
    );
    return '$_temp0';
  }

  @override
  String groupCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count taken out of their group',
      one: '1 taken out of their group',
    );
    return '$_temp0';
  }

  @override
  String get groupSet => 'Set group';

  @override
  String groupSetFor(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Group for $count customers',
      one: 'Group for 1 customer',
    );
    return '$_temp0';
  }

  @override
  String get groupClear => 'Take out of group';

  @override
  String get groupMembersTitle => 'People in this group';

  @override
  String get groupNobody => 'Nobody in this group';

  @override
  String get partiesSelect => 'Select several';

  @override
  String partiesSelected(int count) {
    return '$count selected';
  }

  @override
  String get partiesSort => 'Sort';

  @override
  String get partiesSortName => 'By name';

  @override
  String get partiesSortBalance => 'Most owed first';

  @override
  String get partiesSortOldest => 'Oldest due first';

  @override
  String partiesCapped(int count) {
    return 'Showing the first $count — search to find the rest';
  }

  @override
  String get importFromWhere => 'Where is this file from?';

  @override
  String get importSourceOurs => 'Bazaar Ledger list';

  @override
  String get importSourceVyaparItems => 'Vyapar items';

  @override
  String get importSourceVyaparParties => 'Vyapar parties';

  @override
  String get importSourceKhatabook => 'Khatabook';

  @override
  String get importSourceOther => 'Other';

  @override
  String importRecognised(String source) {
    return 'Recognised: $source';
  }

  @override
  String get importGuideTitle => 'How to get this file';

  @override
  String importGuideOurs(String headings) {
    return 'Put these headings in the first row: $headings. Then one item, or one customer, on each row.';
  }

  @override
  String get importGuideVyaparItems =>
      '1. Open Vyapar on the computer or phone your shop is on.\n2. From the menu open Utilities, then Export Items, and save it as Excel.\n3. Send the file to this phone (WhatsApp it to yourself, or by cable) and choose it below.\nVyapar\'s Import Items sheet, filled in, comes in the same way.';

  @override
  String get importGuideVyaparParties =>
      '1. In Vyapar open Reports, then Party Reports, then All Parties.\n2. Tap the Excel button at the top and save the file.\n3. Send it to this phone and choose it below.\nEach balance comes in on its own side: To Receive is what a customer owes you.';

  @override
  String get importGuideKhatabook =>
      '1. Khatabook\'s phone app saves its reports as PDF, and a PDF cannot be read. If your Khatabook, on a computer or the web, gives the customer list as Excel or CSV, download that.\n2. If it only gives a PDF, make a sheet with the headings Name, Phone, You will get, You will give, and copy the balances in.\n3. Send the file to this phone and choose it below.';

  @override
  String get importGuideOther =>
      'Any .xlsx, .xls or .csv with headings in the first row. A heading this app does not know can be chosen by hand under Columns.';

  @override
  String get importReading => 'Reading the file…';

  @override
  String get importChecking => 'Checking against what the shop already has…';

  @override
  String get importColumnsTitle => 'Columns';

  @override
  String get importColumnsHint =>
      'If a column was read wrong, choose the right one.';

  @override
  String get importColumnNone => 'Not in this file';

  @override
  String importColumnLetter(String letter) {
    return 'Column $letter';
  }

  @override
  String get importFieldName => 'Name';

  @override
  String get importFieldSalePrice => 'Sale price';

  @override
  String get importFieldPurchasePrice => 'Purchase price';

  @override
  String get importFieldWholesalePrice => 'Wholesale price';

  @override
  String get importFieldMrp => 'MRP';

  @override
  String get importFieldStock => 'Stock on hand';

  @override
  String get importFieldMinStock => 'Minimum stock';

  @override
  String get importFieldUnit => 'Unit';

  @override
  String get importFieldSecondaryUnit => 'Second unit';

  @override
  String get importFieldConversion => 'Second units in one';

  @override
  String get importFieldCode => 'Code';

  @override
  String get importFieldBarcode => 'Barcode';

  @override
  String get importFieldCategory => 'Category';

  @override
  String get importFieldDescription => 'Description';

  @override
  String get importFieldHsCode => 'HS / PCT code';

  @override
  String get importFieldItemType => 'Item or service';

  @override
  String get importFieldHsn => 'HSN (India\'s, not kept)';

  @override
  String get importFieldTax => 'Tax rate (not read)';

  @override
  String get importFieldPhone => 'Phone';

  @override
  String get importFieldBalance => 'Balance';

  @override
  String get importFieldReceivable => 'They owe you';

  @override
  String get importFieldPayable => 'You owe them';

  @override
  String get importFieldBalanceType => 'To receive or to pay';

  @override
  String get importFieldType => 'Customer or supplier';

  @override
  String get importFieldCity => 'City';

  @override
  String get importFieldAddress => 'Address';

  @override
  String get importFieldCreditLimit => 'Credit limit';

  @override
  String get importFieldGstin => 'GSTIN (India\'s, not kept)';

  @override
  String importNoteGst(String count, String rates) {
    return '$count items had an Indian GST rate ($rates). GST is not Pakistan\'s sales tax, so no rate is carried: each item takes the shop\'s usual tax, as one added by hand does.';
  }

  @override
  String importNoteTax(String count) {
    return '$count items had a tax rate. It is not read: each item takes the shop\'s usual tax, as one added by hand does.';
  }

  @override
  String importNoteHsn(String count) {
    return '$count items had an HSN code. That is India\'s; Pakistan\'s is the PCT code, so none is kept. Add PCT codes to the items you report to FBR.';
  }

  @override
  String importNoteGstin(String count) {
    return '$count parties had a GSTIN. That is India\'s tax number, not an NTN, so it is not kept.';
  }

  @override
  String get importNoteRupee =>
      'Amounts carried the ₹ sign, as Vyapar writes it. They are read as the rupees you kept them in.';

  @override
  String importNoteColumns(String columns) {
    return 'Not kept: $columns';
  }

  @override
  String importNoteServices(String count) {
    return '$count services come in with no stock to count.';
  }

  @override
  String importUnknownUnit(String count, String unit) {
    return '$count items are in \"$unit\", which this shop has no unit for: they are kept in pieces, prices and stock as the file has them.';
  }

  @override
  String importSecondUnit(String count, String unit) {
    return '$count items have a second unit ($unit): they are kept in their first unit only.';
  }

  @override
  String importBalancesOwed(String count, String amount) {
    return '$count owe you $amount';
  }

  @override
  String importBalancesAhead(String count, String amount) {
    return '$count paid ahead: you hold $amount of theirs';
  }

  @override
  String importBalancesSuppliers(String count, String amount) {
    return '$count suppliers you owe $amount: not brought in. Enter each as a purchase bill.';
  }

  @override
  String importOwedQuestion(String count) {
    return '$count you owe, and the file does not say who they are. They are:';
  }

  @override
  String get importOwedSuppliers => 'Suppliers';

  @override
  String get importOwedCustomers => 'Customers who paid ahead';

  @override
  String importDuplicates(String count) {
    return '$count already in the shop';
  }

  @override
  String get importDuplicatesSkip => 'Leave them as they are';

  @override
  String get importDuplicatesUpdate => 'Bring them up to date';

  @override
  String get importDuplicatesItemsHint =>
      'Prices come from the file; a code or barcode only where the item has none. The stock on the shelf is not changed.';

  @override
  String get importDuplicatesPartiesHint =>
      'Phone, address and credit limit are filled in where missing. What they owe is not changed.';

  @override
  String importPartial(String count) {
    return '$count come in with something left out';
  }

  @override
  String importMore(String count) {
    return 'and $count more';
  }

  @override
  String importLine(String line, String reason) {
    return 'Row $line: $reason';
  }

  @override
  String get importIssueNoName => 'no name';

  @override
  String importIssueTwice(String name) {
    return '$name is in the file twice';
  }

  @override
  String get importIssueTotal => 'a total line, not an item or a party';

  @override
  String importIssueNoPrice(String name) {
    return '$name has no sale price';
  }

  @override
  String importIssueNotPrice(String name, String value) {
    return '$name: \"$value\" is not a price';
  }

  @override
  String importIssueNotQty(String name, String value) {
    return '$name: \"$value\" is not a stock quantity';
  }

  @override
  String importIssueNotAmount(String name, String value) {
    return '$name: \"$value\" is not an amount';
  }

  @override
  String importIssueNegativeStock(String name, String value) {
    return '$name comes in with no stock; the file says $value';
  }

  @override
  String importIssueBarcode(String name, String value) {
    return '$name comes in without its barcode; Excel saved it as $value';
  }

  @override
  String importIssueSupplierOwed(String name, String value) {
    return '$name comes in as a supplier without the Rs $value you owe them: enter it as a purchase bill';
  }

  @override
  String importIssueSupplierOwes(String name, String value) {
    return '$name comes in as a supplier without the Rs $value they owe you';
  }

  @override
  String importIssueAlreadyItem(String name) {
    return '$name is already an item';
  }

  @override
  String importIssueAlreadyItemAs(String name, String value) {
    return '$name is already an item, as $value';
  }

  @override
  String importIssueAlreadyParty(String name) {
    return '$name is already in the khata';
  }

  @override
  String importIssueAlreadyPartyAs(String name, String value) {
    return '$name is already in the khata, as $value';
  }

  @override
  String importIssueOther(String name, String value) {
    return '$name: $value';
  }

  @override
  String importProgress(String total, String done) {
    return 'Bringing in $done of $total…';
  }

  @override
  String importUpdated(String count) {
    return '$count brought up to date';
  }

  @override
  String get importRefusedUnreadable =>
      'This file could not be read as a sheet. Open it in Excel or Google Sheets, save it as .xlsx or .csv, and choose that.';

  @override
  String get importRefusedOld =>
      'This .xls is from Excel 95 or older. Save it again as .xlsx and choose that.';

  @override
  String get importRefusedPassword =>
      'This workbook has a password. Take the password off in Excel, save it, and choose it again.';

  @override
  String get importNeedItemColumns =>
      'The Name and Sale price columns were not found. Choose them under Columns below.';

  @override
  String get importNeedPartyColumns =>
      'The Name column was not found. Choose it under Columns below.';

  @override
  String get reportStockSummary => 'Stock summary';

  @override
  String get reportStockSummaryHint =>
      'Every item\'s stock, price and value, on any day';

  @override
  String get reportItemByParty => 'Item report by party';

  @override
  String get reportItemByPartyHint => 'Who bought an item, and who supplied it';

  @override
  String get reportItemProfit => 'Item-wise profit and loss';

  @override
  String get reportItemProfitHint => 'What each item made over its cost';

  @override
  String get reportCategoryProfit => 'Category-wise profit and loss';

  @override
  String get reportCategoryProfitHint => 'Profit by item category';

  @override
  String get reportLowStock => 'Low stock summary';

  @override
  String get reportLowStockHint => 'What is running out, and how much to order';

  @override
  String get reportItemDetail => 'Item detail';

  @override
  String get reportItemDetailHint => 'One item\'s stock, day by day';

  @override
  String get reportStockDetail => 'Stock detail';

  @override
  String get reportStockDetailHint =>
      'Opening, in, out and closing for every item';

  @override
  String get reportSalePurchaseByCategory => 'Sale and purchase by category';

  @override
  String get reportSalePurchaseByCategoryHint =>
      'How much of each category was sold and bought';

  @override
  String get reportStockByCategory => 'Stock summary by category';

  @override
  String get reportStockByCategoryHint =>
      'Stock and its value, a category at a time';

  @override
  String get reportBatches => 'Item batch report';

  @override
  String get reportBatchesHint => 'Every batch on the shelf, with its expiry';

  @override
  String get reportSerials => 'Serial and IMEI report';

  @override
  String get reportSerialsHint =>
      'Every numbered piece: here, sold or sent back';

  @override
  String get reportItemDiscount => 'Item-wise discount';

  @override
  String get reportItemDiscountHint => 'What came off each item\'s price';

  @override
  String get reportStockTransfers => 'Stock transfer report';

  @override
  String get reportStockTransfersHint =>
      'Goods moved between the shop, godowns and vans';

  @override
  String get reportProduction => 'Production register';

  @override
  String get reportProductionHint =>
      'Every production run, what it used and what it cost';

  @override
  String get reportFastSlow => 'Fast, slow and dead stock';

  @override
  String get reportFastSlowHint =>
      'What sells, what does not, and the money stuck in it';

  @override
  String get reportStockAgeing => 'Stock ageing';

  @override
  String get reportStockAgeingHint =>
      'How long the stock has been on the shelf';

  @override
  String get reportFilterPlace => 'Place';

  @override
  String get reportFilterInStock => 'In stock only';

  @override
  String get reportFilterAsOf => 'As of';

  @override
  String get reportFilterSalesDays => 'Selling over';

  @override
  String get reportFilterCoverDays => 'Order for';

  @override
  String get reportFilterFastAt => 'Fast from';

  @override
  String get reportFilterSlowBelow => 'Slow under';

  @override
  String get reportFilterSerial => 'Serial or IMEI';

  @override
  String get reportFilterSerialHint => 'The number, or its last few digits';

  @override
  String reportFilterDaysValue(int days) {
    return '$days days';
  }

  @override
  String reportFilterBillsValue(int bills) {
    return '$bills bills';
  }

  @override
  String get copyTitle => 'Which copy?';

  @override
  String get copyOriginal => 'Original';

  @override
  String get copyDuplicate => 'Duplicate';

  @override
  String get copyTriplicate => 'Triplicate';

  @override
  String get copyTransporter => 'Transporter';

  @override
  String get copyAutoHint =>
      'Leave it, and the first is the original, every one after it a duplicate';

  @override
  String get copyChosenHint => 'The paper says which copy it is';

  @override
  String get copyTransporterHint =>
      'Goods, quantities and who they are for — no prices at all';

  @override
  String get copyOriginalGone => 'The original has already been printed';

  @override
  String get transportTitle => 'Transport details';

  @override
  String get transportHint =>
      'The bilty and vehicle number print on the bill. Nothing about the money changes.';

  @override
  String get transportAdd => 'Add transport details (bilty, vehicle)';

  @override
  String get transportTransporter => 'Transporter / adda';

  @override
  String get transportVehicle => 'Vehicle no';

  @override
  String get transportBilty => 'Bilty no';

  @override
  String get transportShipTo => 'Ship to';

  @override
  String get settingsBillDesign => 'Bill design';

  @override
  String get billDesignIntro =>
      'How your PDF bills look: layout, colour, logo and payment QR. The till slip stays as it is; only the balance block, the footer and the QR are decided for it here.';

  @override
  String get billDesignLayout => 'Layout';

  @override
  String get billThemeClassic => 'Classic';

  @override
  String get billThemeClassicHint =>
      'The shop name centred, like a bill book from the stationer';

  @override
  String get billThemeModern => 'Modern';

  @override
  String get billThemeModernHint =>
      'A band of your colour across the top with the name and logo';

  @override
  String get billThemeCompact => 'Compact';

  @override
  String get billThemeCompactHint =>
      'Small type, so a long wholesale bill fits one page';

  @override
  String get billThemeTax => 'Sales tax invoice';

  @override
  String get billThemeTaxHint =>
      'As FBR asks: both sides\' NTN/STRN, and for every line the value before tax, the rate, the tax and the value with tax';

  @override
  String get billDesignTaxNeedsNtn =>
      'A tax invoice needs your NTN and STRN in Shop details';

  @override
  String get billDesignColour => 'Colour';

  @override
  String get billAccentInk => 'Black';

  @override
  String get billAccentBlue => 'Blue';

  @override
  String get billAccentGreen => 'Green';

  @override
  String get billAccentMaroon => 'Maroon';

  @override
  String get billAccentOrange => 'Orange';

  @override
  String get billAccentPurple => 'Purple';

  @override
  String get billDesignPage => 'Page size';

  @override
  String get billDesignPictures => 'Logo and QR';

  @override
  String get billDesignLogo => 'Shop logo';

  @override
  String get billDesignLogoHint => 'Printed at the top of PDF bills';

  @override
  String get billDesignPaymentQr => 'Payment QR';

  @override
  String get billDesignPaymentQrHint =>
      'Your own QR from your bank, JazzCash or Easypaisa — a screenshot or photo. Printed at the foot of PDF bills.';

  @override
  String get billDesignQrOnThermal => 'QR on the till slip too';

  @override
  String get billDesignQrOnThermalHint =>
      'Print one slip and scan it with a phone before relying on it';

  @override
  String get billDesignKhata => 'Previous balance on the bill';

  @override
  String get billDesignKhataHint =>
      'On a credit customer\'s bill: what they owed before, this bill, and the total. A copy of an old bill carries the figures of the bill\'s own day.';

  @override
  String get billDesignFooter => 'Footer';

  @override
  String get billDesignFooterLabel => 'One per line (up to 4)';

  @override
  String get billDesignFooterHint =>
      'Thanks, return policy, anything — Urdu, Roman Urdu or English';

  @override
  String get billDesignFooterPresets => 'Add with one tap';

  @override
  String get billDesignPreview => 'Preview';

  @override
  String get billDesignPreviewPdf => 'PDF';

  @override
  String get billDesignPreviewSlip => 'Till slip';

  @override
  String get billDesignPreviewNote =>
      'A sketch of the look. To see the real PDF, use the button below.';

  @override
  String get billDesignSamplePdf => 'See a sample PDF';

  @override
  String get billDesignSaved => 'Bill design saved';

  @override
  String get settingsTextSize => 'Text size';

  @override
  String get settingsTextSizeNormal => 'Normal';

  @override
  String get settingsTextSizeLarge => 'Large';

  @override
  String get settingsTextSizeLarger => 'Larger';

  @override
  String get settingsTextSizeHint =>
      'On this phone\'s screens only. Bills, receipts and PDFs print the same at every size.';

  @override
  String itemStockLeft(String amount) {
    return '$amount in stock';
  }

  @override
  String get expenseWhose => 'Whose spending';

  @override
  String get expenseForShop => 'Shop\'s spending';

  @override
  String get expenseForHome => 'Home spending';

  @override
  String get expenseHomeChip => 'Home';

  @override
  String get expenseHomeExplain =>
      'Home spending is the owner\'s own money taken out of the shop. It is not a cost of the shop, so it never lowers the profit; it lowers the owner\'s share instead.';

  @override
  String get expenseHomeGoodsLink => 'Took goods home from the shelf?';

  @override
  String get expenseRemind => 'Remind me every month';

  @override
  String get expenseRemindDay => 'Day of the month';

  @override
  String get expenseRemindDayInvalid => 'The day of the month is 1 to 31';

  @override
  String get expenseMonthShop => 'Shop, this month';

  @override
  String get expenseMonthHome => 'Home, this month';

  @override
  String get expenseGoodsCancelOnly =>
      'Goods taken home are not edited: cancel this and enter it again.';

  @override
  String get expenseHomeNotAllowed =>
      'Only the owner or the accountant can change home spending.';

  @override
  String get billsTitle => 'Monthly bills';

  @override
  String get billsEmpty => 'No monthly bills yet';

  @override
  String get billsEmptyHint =>
      'Rent, bijli, wages: add them once and the app reminds you on the day. Nothing is paid by itself.';

  @override
  String get billsNew => 'New monthly bill';

  @override
  String billDue(String name) {
    return 'Due this month: $name';
  }

  @override
  String billDueOn(String date) {
    return 'Due on $date';
  }

  @override
  String get billPayNow => 'Pay now';

  @override
  String get billSkip => 'Not this month';

  @override
  String get billSkipped => 'Not reminded again this month';

  @override
  String billEvery(String day) {
    return 'Every month on the $day';
  }

  @override
  String get billName => 'What the bill is';

  @override
  String get billAmount => 'Usual amount';

  @override
  String get billSave => 'Save the bill';

  @override
  String get monthlyBillSaved => 'Monthly bill saved';

  @override
  String get billDelete => 'Stop reminding';

  @override
  String get billDeleted => 'Reminder stopped';

  @override
  String get billPaidFrom => 'Usually paid from';

  @override
  String get headsTitle => 'Heads';

  @override
  String get headsExpense => 'Spending heads';

  @override
  String get headsIncome => 'Income heads';

  @override
  String get headsAddExpense => 'New spending head';

  @override
  String get headsAddIncome => 'New income head';

  @override
  String get headName => 'Name';

  @override
  String get headDirect => 'Cost of the goods (comes off before gross profit)';

  @override
  String get headDirectChip => 'Direct';

  @override
  String get headIndirectChip => 'Indirect';

  @override
  String get headHidden => 'Hidden';

  @override
  String get headHide => 'Hide from the list';

  @override
  String get headSave => 'Save';

  @override
  String get headSaved => 'Saved';

  @override
  String get headDirectExplain =>
      'A cost of the goods (freight on goods coming in) comes off the sales before gross profit; the rest (rent, wages, bijli) after it. Changing it moves the head in every month\'s profit and loss.';

  @override
  String get incomeTitle => 'Other income';

  @override
  String get incomeEmpty => 'No other income yet';

  @override
  String get incomeEmptyHint =>
      'Rent from a sub-let, commission, bank profit, scrap sold: money that is not a sale goes here.';

  @override
  String get incomeNew => 'New income';

  @override
  String get incomeHead => 'Under';

  @override
  String get incomeFrom => 'From whom (optional)';

  @override
  String get incomeFromParty => 'Pick from the khata';

  @override
  String get incomeInto => 'Received into';

  @override
  String get incomeNote => 'What it was (optional)';

  @override
  String get incomeSave => 'Save income';

  @override
  String incomeSaved(String docNo) {
    return 'Income $docNo saved';
  }

  @override
  String get incomeThisMonth => 'This month';

  @override
  String get incomeNotASale =>
      'Not a sale: the profit and loss shows it under other income, below gross profit.';

  @override
  String get incomeHeadRent => 'Rent received';

  @override
  String get incomeHeadCommission => 'Commission';

  @override
  String get incomeHeadInterest => 'Bank profit, interest';

  @override
  String get incomeHeadScrap => 'Scrap, empties sold';

  @override
  String get incomeHeadRefund => 'Refund received';

  @override
  String get incomeHeadOther => 'Other';

  @override
  String get homeGoodsTitle => 'Goods taken home';

  @override
  String get homeGoodsExplain =>
      'Goods off the shop\'s shelf for the house. They leave at what they cost, and come off the owner\'s share, not the profit.';

  @override
  String get homeGoodsSearch => 'Which item';

  @override
  String get homeGoodsQty => 'How much';

  @override
  String homeGoodsOnHand(String qty) {
    return '$qty on the shelf';
  }

  @override
  String get homeGoodsNote => 'Note (optional)';

  @override
  String get homeGoodsSave => 'Save: taken home';

  @override
  String homeGoodsSaved(String docNo, String amount) {
    return '$docNo: goods worth $amount taken home';
  }

  @override
  String get homeGoodsPick => 'Pick an item first';

  @override
  String get homeGoodsQtyInvalid => 'Write how much, like 2 or 1.5';

  @override
  String get reportDailySummary => 'Day summary (Z report)';

  @override
  String get reportDailySummaryHint =>
      'Tonight\'s sales, money by mode, udhaar, expenses and the drawer';

  @override
  String get reportBankStatement => 'Bank statement';

  @override
  String get reportBankStatementHint =>
      'Every deposit and withdrawal, with the balance after each';

  @override
  String get reportDiscount => 'Discount report';

  @override
  String get reportDiscountHint =>
      'Discount given to each party, and taken from suppliers';

  @override
  String get reportDiscountByCashier => 'Discount by cashier';

  @override
  String get reportDiscountByCashierHint =>
      'How much discount each cashier gives away';

  @override
  String get reportSalesByCashier => 'Sales by cashier';

  @override
  String get reportSalesByCashierHint =>
      'Bills, sales, discounts, returns and voids per person';

  @override
  String get reportSalesByCounter => 'Sales by counter';

  @override
  String get reportSalesByCounterHint => 'The same, per phone or till';

  @override
  String get reportPaymentModes => 'Payment-mode summary';

  @override
  String get reportPaymentModesHint =>
      'Cash, bank, JazzCash, Easypaisa, cheque and udhaar, each on its own line';

  @override
  String get reportHourlySales => 'Hourly sales';

  @override
  String get reportHourlySalesHint => 'Which hours of the day are busiest';

  @override
  String get reportPaymentPerformance => 'Customer payment performance';

  @override
  String get reportPaymentPerformanceHint =>
      'How long each customer takes to pay, and who pays late';

  @override
  String get reportDefaulters => 'Defaulter list';

  @override
  String get reportDefaultersHint =>
      'Customers whose udhaar is past its due date';

  @override
  String get reportChangedBills => 'Changed and cancelled bills';

  @override
  String get reportChangedBillsHint =>
      'Every void, return and edit, with who, when and why';

  @override
  String get reportTaxReport => 'Tax report';

  @override
  String get reportTaxReportHint =>
      'Output tax on sales against input tax, by party, with NTN';

  @override
  String get reportTaxRate => 'Tax rate report';

  @override
  String get reportTaxRateHint =>
      'Tax by rate: 18%, reduced, exempt, zero, Third Schedule, further tax';

  @override
  String get reportSalesByHsCode => 'Sales by HS code';

  @override
  String get reportSalesByHsCodeHint => 'What was sold under each HS code';

  @override
  String get reportAnnexC => 'Annex-C (sales)';

  @override
  String get reportAnnexCHint =>
      'Every sale line in FBR\'s Annex-C columns, for the accountant';

  @override
  String get reportAnnexA => 'Annex-A (purchases)';

  @override
  String get reportAnnexAHint =>
      'Every purchase line in FBR\'s Annex-A columns';

  @override
  String get reportExpenseTransactions => 'Expense transactions';

  @override
  String get reportExpenseTransactionsHint =>
      'Every expense: its head, where it was paid from, what for';

  @override
  String get reportExpenseCategories => 'Expense categories';

  @override
  String get reportExpenseCategoriesHint =>
      'Totals for each head, direct and indirect';

  @override
  String get reportExpenseItems => 'Expense items';

  @override
  String get reportExpenseItemsHint =>
      'What the money went on within each head';

  @override
  String get reportOpenQuotations => 'Open quotations';

  @override
  String get reportOpenQuotationsHint =>
      'Quotations not yet billed, and how long they have waited';

  @override
  String get reportOpenChallans => 'Challans not yet billed';

  @override
  String get reportOpenChallansHint =>
      'Goods sent on a challan whose bill is not made yet';

  @override
  String get reportOpenOrderItems => 'Quotation and challan items';

  @override
  String get reportOpenOrderItemsHint =>
      'The items and quantities on open quotations and challans';

  @override
  String get reportFilterAccount => 'Account';

  @override
  String get reportFilterHead => 'Expense head';

  @override
  String get dayCloseSummary => 'See the day\'s summary (Z report)';

  @override
  String dueOn(String date) {
    return 'Due $date';
  }

  @override
  String get dueToday => 'Due today';

  @override
  String dueOverdue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Overdue $days days',
      one: 'Overdue 1 day',
    );
    return '$_temp0';
  }

  @override
  String get dueNotYet => 'Not yet due';

  @override
  String khataCreditDays(int days) {
    return '$days days\' credit';
  }

  @override
  String khataCreditUsual(int days) {
    return 'The shop\'s usual $days days';
  }

  @override
  String khataReturn(String no) {
    return 'Return $no';
  }

  @override
  String get partyCreditDays => 'Days of credit (optional)';

  @override
  String partyCreditDaysHint(int days) {
    return 'Left blank, $days days. Changing it moves the due date of bills still open too.';
  }

  @override
  String get partyCreditDaysInvalid => 'Between 0 and 365 days';

  @override
  String get promiseTitle => 'Promise to pay';

  @override
  String get promiseRecord => 'Note a promise';

  @override
  String get promiseNew => 'New promise';

  @override
  String get promiseNone =>
      'When did they say they\'d pay? Note it here and it comes up on the day.';

  @override
  String get promiseWhen => 'When did they say?';

  @override
  String get promiseTomorrow => 'Tomorrow';

  @override
  String get promiseFriday => 'Friday';

  @override
  String get promiseNextWeek => 'In a week';

  @override
  String get promiseSalaryDay => 'Salary day (the 1st)';

  @override
  String get promisePickDay => 'Pick a day';

  @override
  String get promiseAmount => 'How much they said (optional)';

  @override
  String get promiseNote => 'What they said (optional)';

  @override
  String get promiseSave => 'Save the promise';

  @override
  String promiseSaved(String date) {
    return 'Promise noted: $date';
  }

  @override
  String promiseFor(String date) {
    return 'Promised for $date';
  }

  @override
  String promiseForAmount(String date, String amount) {
    return 'Rs $amount promised for $date';
  }

  @override
  String get promisePending => 'Waiting';

  @override
  String get promiseDueToday => 'Due today';

  @override
  String get promiseKept => 'Kept';

  @override
  String get promiseBroken => 'Broken';

  @override
  String get promiseReplaced => 'Replaced';

  @override
  String get promiseWithdrawnLabel => 'Taken off';

  @override
  String get promiseWithdraw => 'Take the promise off';

  @override
  String get promiseWithdrawn =>
      'Promise taken off. It stays with the earlier ones.';

  @override
  String get promiseHistory => 'Earlier promises';

  @override
  String promiseBy(String name, String date) {
    return 'Noted by $name on $date';
  }

  @override
  String promisePaidSince(String amount) {
    return 'Rs $amount has come in since';
  }

  @override
  String homeUdhaarDueToday(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers due today · Rs $amount',
      one: '1 customer due today · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String homeUdhaarOverdue(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers overdue · Rs $amount',
      one: '1 customer overdue · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String homeUdhaarPromised(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers promised to pay today · Rs $amount',
      one: '1 customer promised to pay today · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String get chaseSortLate => 'Most late first';

  @override
  String get chaseSortPromise => 'By promised day';

  @override
  String get chaseFilterPromised => 'With a promise';

  @override
  String get chaseFilterDueToday => 'Due today';

  @override
  String get chaseFilterPromisedToday => 'Promised today';

  @override
  String get promiseToday => 'Today';

  @override
  String get chaseFilterOverdue => 'Late ones';

  @override
  String get khataRemindOff => 'Not reminded';

  @override
  String get remindedToday => 'Reminded today';

  @override
  String remindedDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Reminded $days days ago',
      one: 'Reminded yesterday',
    );
    return '$_temp0';
  }

  @override
  String remindedBy(String when, String name, String channel) {
    return '$when · $name · $channel';
  }

  @override
  String get reminderChannelSms => 'SMS';

  @override
  String get reminderChannelShare => 'Share sheet';

  @override
  String get reminderLangUrdu => 'اردو (Urdu)';

  @override
  String get reminderLangRoman => 'Roman Urdu';

  @override
  String get reminderLangEnglish => 'English';

  @override
  String get chaseRemind => 'Send reminders';

  @override
  String get chaseSelectLate => 'Tick everyone late';

  @override
  String chaseSendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remind $count',
      one: 'Remind 1',
    );
    return '$_temp0';
  }

  @override
  String get chasePickHint => 'Tick the customers to remind';

  @override
  String get roundTitle => 'Reminders';

  @override
  String roundResume(int left) {
    String _temp0 = intl.Intl.pluralLogic(
      left,
      locale: localeName,
      other: 'A round of reminders is unfinished: $left left',
      one: 'A round of reminders is unfinished: 1 left',
    );
    return '$_temp0';
  }

  @override
  String get roundResumeAction => 'Carry on';

  @override
  String get roundDiscard => 'End it';

  @override
  String get roundChannelSms => 'SMS';

  @override
  String get roundOpenWhatsApp => 'Open in WhatsApp';

  @override
  String get roundOpenSms => 'Open in messages';

  @override
  String get roundSent => 'Sent ✓';

  @override
  String get roundSkip => 'Skip';

  @override
  String get roundLater => 'Later';

  @override
  String roundDone(int sent, int skipped) {
    return 'All done: $sent sent, $skipped skipped';
  }

  @override
  String get roundFinish => 'Finish';

  @override
  String get roundNoNumber => 'No number: goes by the share sheet';

  @override
  String get partyReminders => 'Reminders';

  @override
  String get partyReminderLanguage => 'Which language to send in';

  @override
  String get partyReminderOptOut => 'Don\'t send this customer reminders';

  @override
  String get settingsReminders => 'Reminder messages';

  @override
  String get templatesTitle => 'Reminder messages';

  @override
  String get templatesHint =>
      'Each customer gets the message in their language. The parts in braces fill themselves in; a line whose part is empty is left out.';

  @override
  String get templatesField => 'Message';

  @override
  String get templatesPreview => 'It will read';

  @override
  String get templatesSaved => 'Message saved';

  @override
  String get templatesReset => 'Back to the shop\'s words';

  @override
  String get templatesResetDone => 'The shop\'s words are back';

  @override
  String get templatesSampleName => 'Aslam Karyana';

  @override
  String get khataWriteOff => 'Write off as bad debt';

  @override
  String get writeOffTitle => 'Write off as bad debt';

  @override
  String get writeOffExplain =>
      'This comes off the khata and goes to the Bad Debts expense, which the profit and loss shows. If it was a mistake, cancel the entry on the khata and the udhaar comes back.';

  @override
  String writeOffWhole(String amount) {
    return 'Owed in all: Rs $amount';
  }

  @override
  String get writeOffWholeShort => 'All of it';

  @override
  String get writeOffBills => 'Some bills';

  @override
  String get writeOffWhy => 'Why is it being let go?';

  @override
  String get writeOffReasonMoved => 'Moved away';

  @override
  String get writeOffReasonDied => 'Passed away';

  @override
  String get writeOffReasonRefused => 'Refuses to pay';

  @override
  String get writeOffReasonClosed => 'Their business closed';

  @override
  String get writeOffReasonText => 'Write the reason';

  @override
  String get writeOffReasonRequired => 'A write-off has to say why';

  @override
  String get writeOffPickBills => 'Pick at least one bill';

  @override
  String get writeOffSave => 'Write it off';

  @override
  String writeOffSaved(String no, String amount) {
    return '$no: Rs $amount written off';
  }

  @override
  String get badDebtsTitle => 'Money let go';

  @override
  String get badDebtsWrittenOff => 'Bad debts';

  @override
  String get badDebtsDiscounts => 'Discounts';

  @override
  String get badDebtsEmpty => 'Nothing let go yet';

  @override
  String get allowanceTotal => 'Total (not counting cancelled)';

  @override
  String allowanceBy(String name) {
    return 'Let go by $name';
  }

  @override
  String allowanceDiscountLine(String no) {
    return 'Discount $no';
  }

  @override
  String allowanceWriteOffLine(String no) {
    return 'Written off $no';
  }

  @override
  String entryDiscountTitle(String no) {
    return 'Settlement discount $no';
  }

  @override
  String entryWriteOffTitle(String no) {
    return 'Bad debt $no';
  }

  @override
  String get entryAllowanceNoEdit =>
      'This is not edited: cancel it and enter it again.';

  @override
  String get tenderModeAdjustment => 'Let go';

  @override
  String get settleDiscountToggle => 'Let the rest go (settle with a discount)';

  @override
  String settleDiscountLine(String amount) {
    return 'Discount: Rs $amount, every bill settled';
  }

  @override
  String get settleDiscountNone => 'This settles it all; no discount is needed';

  @override
  String get settleDiscountReason => 'Reason for the discount (optional)';

  @override
  String settleDiscountSaved(String amount, String discount) {
    return 'Rs $amount received, Rs $discount let go';
  }

  @override
  String get settleDiscountOverCeiling =>
      'That much discount is more than your role gives. The owner, a manager or the accountant can settle it.';

  @override
  String get chaseBadDebts => 'Money let go';

  @override
  String get billMoreActions => 'More';

  @override
  String get copyAction => 'New bill like this';

  @override
  String get correctAction => 'Correct and reissue';

  @override
  String copyRatesTitle(String docNo) {
    return '$docNo again: which prices?';
  }

  @override
  String get copyRatesToday => 'Today\'s prices';

  @override
  String get copyRatesTodayHint => 'This customer\'s prices and discount today';

  @override
  String get copyRatesOld => 'Prices as billed';

  @override
  String copyRatesOldHint(String docNo) {
    return 'What $docNo charged, discounts and all';
  }

  @override
  String copyLoaded(String docNo) {
    return 'A copy of $docNo is on the counter';
  }

  @override
  String copyLeftOut(String names) {
    return 'Not carried over: $names';
  }

  @override
  String copyNothing(String docNo) {
    return 'Nothing on $docNo can go back on the counter';
  }

  @override
  String copyWhyGone(String name) {
    return '$name (item archived)';
  }

  @override
  String copyWhyFree(String name) {
    return '$name (free)';
  }

  @override
  String copyWhySerial(String name) {
    return '$name (scan the serial again)';
  }

  @override
  String copyWhyTwice(String name) {
    return '$name (twice on the bill)';
  }

  @override
  String copyNoCustomer(String name) {
    return '$name is no longer in the khata; the bill has no customer';
  }

  @override
  String repeatLastOrder(String docNo) {
    return 'Repeat last order ($docNo)';
  }

  @override
  String get correctTitle => 'Correct and reissue';

  @override
  String get correctExplain =>
      'This bill is cancelled (its number and paper stay as they are) and a copy opens on the counter. Put the mistake right and save the new bill; the two stay linked.';

  @override
  String correctPaid(String amount, String mode) {
    return 'Rs $amount ($mode) was taken on this bill. The new bill starts with the same amount filled in.';
  }

  @override
  String get correctUdhaar =>
      'This bill was on udhaar; the new one opens on udhaar too.';

  @override
  String get correctAbandon =>
      'If the new bill is not saved, this one stays cancelled all the same.';

  @override
  String correctAbandonPaid(String amount) {
    return 'If the new bill is not saved, this one stays cancelled all the same, and Rs $amount goes back to the customer.';
  }

  @override
  String get correctConfirm => 'Cancel and open the new bill';

  @override
  String get reasonWrongItem => 'Wrong item';

  @override
  String get reasonWrongQty => 'Wrong quantity';

  @override
  String get reasonWrongPrice => 'Wrong price';

  @override
  String get reasonWrongCustomer => 'Wrong customer';

  @override
  String get reasonOrderCancelled => 'Order cancelled';

  @override
  String correctOnCounter(String docNo) {
    return 'New bill in place of $docNo';
  }

  @override
  String correctOnCounterHint(String docNo) {
    return '$docNo has been cancelled. Put it right, then take payment.';
  }

  @override
  String correctClearConfirm(String docNo) {
    return 'Drop the new bill? $docNo stays cancelled all the same.';
  }

  @override
  String tenderPaidBefore(String docNo, String amount, String mode) {
    return 'Rs $amount ($mode) was taken on $docNo; it is filled in here.';
  }

  @override
  String tenderPaidBeforeUdhaar(String docNo) {
    return '$docNo was all on udhaar.';
  }

  @override
  String tenderGiveBack(String amount) {
    return 'Give Rs $amount back to the customer';
  }

  @override
  String tenderTakeMore(String amount) {
    return 'Take Rs $amount more';
  }

  @override
  String billReplaces(String docNo) {
    return 'Replaces $docNo';
  }

  @override
  String billReplacedBy(String docNo) {
    return 'Replaced by $docNo';
  }

  @override
  String billReplacedByVoid(String docNo) {
    return 'Replaced by $docNo (cancelled too)';
  }

  @override
  String get copyHint => 'The same goods and customer, on a new bill';

  @override
  String get trailAction => 'History';

  @override
  String trailTitle(String no) {
    return 'History · $no';
  }

  @override
  String get trailEmpty => 'Nothing has been recorded for this yet';

  @override
  String trailByOn(String who, String device, String when) {
    return '$who on $device · $when';
  }

  @override
  String trailBy(String who, String when) {
    return '$who · $when';
  }

  @override
  String trailWhy(String reason) {
    return 'Why: $reason';
  }

  @override
  String get trailMade => 'Made';

  @override
  String get trailPrinted => 'Printed';

  @override
  String get trailPrintFailed => 'Print did not come out';

  @override
  String get trailCancelled => 'Cancelled';

  @override
  String get trailReturned => 'Goods came back';

  @override
  String get trailPaid => 'Money went against it';

  @override
  String get trailPaidAtCounter => 'Paid at the counter';

  @override
  String get trailLetGo => 'Let go';

  @override
  String get trailSettled => 'Went against this bill';

  @override
  String get trailReleased => 'Taken off this bill (cancelled)';

  @override
  String get trailCorrected => 'Corrected';

  @override
  String get trailChanged => 'Changed';

  @override
  String get trailApproved => 'Allowed with a PIN';

  @override
  String get trailMadeFrom => 'Made from';

  @override
  String get trailBecame => 'Became a bill';

  @override
  String get trailReturnOf => 'Return against';

  @override
  String trailOpen(String no) {
    return 'Open $no';
  }

  @override
  String get trailFieldName => 'Name';

  @override
  String get trailFieldPhone => 'Phone';

  @override
  String get trailFieldAddress => 'Address';

  @override
  String get trailFieldSaleRate => 'Sale rate';

  @override
  String get trailFieldPurchaseRate => 'Purchase rate';

  @override
  String get trailFieldCreditLimit => 'Credit limit';

  @override
  String get trailFieldOpening => 'Opening balance';

  @override
  String get trailFieldAmount => 'Amount';

  @override
  String get trailFieldActive => 'Shown';

  @override
  String get trailFieldGroup => 'Group';

  @override
  String get trailFieldBarcode => 'Barcode';

  @override
  String get trailYes => 'Yes';

  @override
  String get trailNo => 'No';

  @override
  String get approvalClosedTitle => 'These books are closed';

  @override
  String approvalClosedBody(String date, String entryDate) {
    return 'The books are closed up to $date, and this is dated $entryDate. Only the owner can let it in, with their PIN and a reason.';
  }

  @override
  String get approvalLockTitle => 'Data Lock: a PIN is needed';

  @override
  String get approvalLockBody =>
      'A PIN is asked before anything is cancelled, written off or hidden.';

  @override
  String get approvalWho => 'Whose PIN';

  @override
  String get approvalReason => 'Reason (required)';

  @override
  String get approvalAllow => 'Allow';

  @override
  String get approvalWrongPin => 'Wrong PIN';

  @override
  String get approvalTooMany => 'Too many wrong PINs. Wait half a minute.';

  @override
  String get approvalReasonNeeded => 'Say why';

  @override
  String get approvalNoPin => 'They have no PIN; choose somebody who has';

  @override
  String get booksLockTitle => 'Closed books and Data Lock';

  @override
  String booksClosedThrough(String date) {
    return 'Books closed up to $date';
  }

  @override
  String get booksOpenNow => 'No days are closed';

  @override
  String get booksCloseExplain =>
      'Nothing dated on or before that day can be added, cancelled or corrected unless the owner allows it with their PIN and a reason. A return today against an old bill is dated today and goes through.';

  @override
  String booksCloseThrough(String date) {
    return 'Close up to $date';
  }

  @override
  String get booksClosePick => 'Pick another day';

  @override
  String get booksReopen => 'Open the books again';

  @override
  String booksClosedDone(String date) {
    return 'Books closed up to $date';
  }

  @override
  String get booksReopened => 'The books are open again';

  @override
  String get dataLockTitle => 'A PIN before cancelling (Data Lock)';

  @override
  String get dataLockExplain =>
      'Cancelling a bill or a payment, correcting a payment, writing off udhaar, hiding an item or a customer, or restoring a backup: each asks a PIN first. The PIN of whoever is doing it, or the owner\'s.';

  @override
  String get dataLockNeedsPin => 'Set your own PIN first (Staff and PINs)';

  @override
  String get lateArrivalsTitle =>
      'Entries that arrived from counters after closing';

  @override
  String get lateArrivalsExplain =>
      'These were made on another counter before it knew the books were closed, so they were taken in. Look over the closed days again with them.';
}
