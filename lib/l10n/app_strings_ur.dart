// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_strings.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppStringsUr extends AppStrings {
  AppStringsUr([String locale = 'ur']) : super(locale);

  @override
  String get appName => 'Bazaar Ledger';

  @override
  String get actionSave => 'Save karein';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete karein';

  @override
  String get actionEdit => 'Tabdeeli karein';

  @override
  String get actionRetry => 'Dobara koshish karein';

  @override
  String get actionContinue => 'Aage barhein';

  @override
  String get actionBack => 'Wapas';

  @override
  String get actionClose => 'Band karein';

  @override
  String get actionSearch => 'Talash karein';

  @override
  String get actionShare => 'Bhejein';

  @override
  String get actionPrint => 'Print karein';

  @override
  String get actionAdd => 'Shamil karein';

  @override
  String get actionDone => 'Ho gaya';

  @override
  String get actionOk => 'Theek hai';

  @override
  String get commonLoading => 'Khul raha hai...';

  @override
  String get commonSomethingWentWrong => 'Kuch masla ho gaya';

  @override
  String get commonNothingSaved => 'Kuch save nahi hua';

  @override
  String get commonRequired => 'Yeh khana zaroori hai';

  @override
  String get commonOffline =>
      'Internet nahi hai - koi baat nahi, sab kuch phone par chalta hai';

  @override
  String get commonYes => 'Haan';

  @override
  String get commonNo => 'Nahi';

  @override
  String get setupTitle => 'Apni dukan set karein';

  @override
  String get setupSubtitle =>
      'Sirf teen cheezein. Baqi baad mein bhi badal sakte hain.';

  @override
  String get setupShopName => 'Dukan ka naam';

  @override
  String get setupShopNameHint => 'Chishti Kiryana Store';

  @override
  String get setupOwnerName => 'Aap ka naam';

  @override
  String get setupOwnerNameHint => 'Malik Sahib';

  @override
  String get setupCity => 'Shehar';

  @override
  String get setupCityHint => 'Lahore';

  @override
  String get setupProvince => 'Suba';

  @override
  String get setupBusinessKind => 'Dukan ki qism';

  @override
  String get setupCounterName => 'Is counter ka naam';

  @override
  String get setupCounterHint => 'Counter 1';

  @override
  String get setupFinish => 'Dukan shuru karein';

  @override
  String get setupPrivacyNote =>
      'Aap ka saara hisaab isi phone mein rehta hai. Na koi account, na koi server.';

  @override
  String get businessKindGeneral => 'General store';

  @override
  String get businessKindKiryana => 'Kiryana';

  @override
  String get businessKindPharmacy => 'Medical store';

  @override
  String get businessKindGarments => 'Garments';

  @override
  String get businessKindCloth => 'Kapre ka kaam';

  @override
  String get businessKindHardware => 'Hardware';

  @override
  String get businessKindElectronics => 'Electronics';

  @override
  String get businessKindRestaurant => 'Hotel / Restaurant';

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
  String get homeTitle => 'Aaj ka hisaab';

  @override
  String get homeTodaySales => 'Aaj ki farokht';

  @override
  String homeBillCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bill',
      one: '1 bill',
      zero: 'Koi bill nahi',
    );
    return '$_temp0';
  }

  @override
  String get homeReceived => 'Wasool';

  @override
  String get homeOnUdhaar => 'Udhaar par';

  @override
  String get homeNewBill => 'Naya Bill';

  @override
  String get homeItems => 'Maal';

  @override
  String get homeSales => 'Farokht';

  @override
  String get homeCustomers => 'Gahak';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeNoSalesToday => 'Aaj abhi koi bill nahi bana';

  @override
  String get posTitle => 'Naya Bill';

  @override
  String get posSearchHint => 'Maal ka naam ya barcode';

  @override
  String get posCartEmpty => 'Bill abhi khali hai';

  @override
  String get posCartEmptyHint =>
      'Upar se maal talash karein aur bill mein daalein';

  @override
  String get posSubtotal => 'Subtotal';

  @override
  String get posDiscount => 'Riayat';

  @override
  String get posTax => 'Sales tax';

  @override
  String get posRoundOff => 'Round off';

  @override
  String get posTotal => 'Total';

  @override
  String get posCharge => 'Paisay lein';

  @override
  String posItemsInCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheezein',
      one: '1 cheez',
    );
    return '$_temp0';
  }

  @override
  String get posRemoveLine => 'Line hatayein';

  @override
  String get posClearCart => 'Bill khali karein';

  @override
  String get posClearCartConfirm => 'Poora bill khali kar dein?';

  @override
  String get posWalkInCustomer => 'Aam gahak';

  @override
  String get posChooseCustomer => 'Gahak chunein';

  @override
  String get posQty => 'Tadaad';

  @override
  String get posRate => 'Qeemat';

  @override
  String get posAmount => 'Raqam';

  @override
  String get posLineDiscount => 'Is line par riayat';

  @override
  String get posNoStock => 'Stock khatam';

  @override
  String posStockLeft(String qty, String unit) {
    return 'Stock: $qty $unit';
  }

  @override
  String get tenderTitle => 'Paisay lein';

  @override
  String get tenderDue => 'Dena hai';

  @override
  String get tenderTendered => 'Diye gaye';

  @override
  String get tenderChange => 'Wapsi';

  @override
  String get tenderExact => 'Poore paisay';

  @override
  String get tenderRemaining => 'Baqi';

  @override
  String get tenderOnUdhaar => 'Udhaar likh lein';

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
  String get tenderReference => 'Reference (marzi se)';

  @override
  String get tenderManualNote =>
      'Paisay jahan se bhi aayein, aap sirf yahan likh dein. App khud koi paisay nahi leti.';

  @override
  String get tenderSaveAndPrint => 'Save aur Print';

  @override
  String get tenderSave => 'Sirf Save karein';

  @override
  String get tenderUdhaarNeedsCustomer =>
      'Udhaar ke liye gahak chunna zaroori hai';

  @override
  String get tenderCashThresholdWarning =>
      'Rs 200,000 se upar ka bill cash mein lene par kharche ka 50% na-manzoor ho sakta hai (s.21(s)). Bank ya digital se lena behtar hai.';

  @override
  String billSaved(String docNo) {
    return 'Bill $docNo save ho gaya';
  }

  @override
  String get billSaveFailed => 'Bill save nahi hua. Kuch bhi likha nahi gaya.';

  @override
  String get itemsTitle => 'Maal';

  @override
  String get itemsEmpty => 'Abhi koi maal nahi';

  @override
  String get itemsEmptyHint =>
      'Pehla item daalein, phir bill banana shuru karein';

  @override
  String get itemsAdd => 'Naya maal';

  @override
  String get itemsEdit => 'Maal ki tabdeeli';

  @override
  String get itemName => 'Naam';

  @override
  String get itemNameHint => 'Cooking Oil 5L';

  @override
  String get itemCode => 'Code (marzi se)';

  @override
  String get itemBarcode => 'Barcode (marzi se)';

  @override
  String get itemCategory => 'Qism (marzi se)';

  @override
  String get itemUnit => 'Unit';

  @override
  String get itemSalePrice => 'Farokht ki qeemat';

  @override
  String get itemPurchasePrice => 'Khareed ki qeemat';

  @override
  String get itemOpeningStock => 'Mojooda stock';

  @override
  String get itemMinStock => 'Kam stock ki hadd';

  @override
  String get itemArchive => 'Counter se hatayein';

  @override
  String get itemArchived => 'Item hata diya gaya';

  @override
  String get itemSaved => 'Item save ho gaya';

  @override
  String itemInStock(String qty, String unit) {
    return '$qty $unit mojood';
  }

  @override
  String get itemLowStock => 'Stock kam hai';

  @override
  String get partiesTitle => 'Gahak';

  @override
  String get partiesEmpty => 'Abhi koi gahak nahi';

  @override
  String get partiesEmptyHint => 'Udhaar likhne ke liye gahak daalein';

  @override
  String get partiesAdd => 'Naya gahak';

  @override
  String get partyName => 'Naam';

  @override
  String get partyPhone => 'Phone';

  @override
  String get partyOpeningBalance => 'Purana baqaya';

  @override
  String get partyCreditLimit => 'Udhaar ki hadd';

  @override
  String partyOwes(String amount) {
    return '$amount udhaar';
  }

  @override
  String get partySettled => 'Hisaab saaf';

  @override
  String get salesTitle => 'Farokht';

  @override
  String get salesEmpty => 'Abhi koi bill nahi bana';

  @override
  String get salesEmptyHint => 'Pehla bill banayein, yahan aa jayega';

  @override
  String get salesPaid => 'Ada shuda';

  @override
  String salesUdhaar(String amount) {
    return 'Baqaya $amount';
  }

  @override
  String get salesVoided => 'Mansookh';

  @override
  String receiptTitle(String docNo) {
    return 'Bill $docNo';
  }

  @override
  String get receiptSharePdf => 'PDF bhejein';

  @override
  String get receiptPrint => 'Printer par bhejein';

  @override
  String get receiptPreview => 'Kaisa chhapega';

  @override
  String get receiptPaper80 => '80mm';

  @override
  String get receiptPaper58 => '58mm';

  @override
  String get receiptReprint => 'Dobara print';

  @override
  String get receiptNoPrinter =>
      'Abhi koi printer set nahi. Preview dekh sakte hain aur PDF bhej sakte hain.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Zaban';

  @override
  String get settingsLanguageRomanUrdu => 'Roman Urdu';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsTheme => 'Roshni';

  @override
  String get settingsThemeSystem => 'Phone jaisa';

  @override
  String get settingsThemeLight => 'Safaid';

  @override
  String get settingsThemeDark => 'Kaala';

  @override
  String get settingsShop => 'Dukan ki tafseel';

  @override
  String get settingsPayment => 'Paisay lene ki tafseel';

  @override
  String get settingsRaastAlias => 'Raast alias (mobile number)';

  @override
  String get settingsBankName => 'Bank ka naam';

  @override
  String get settingsAccountTitle => 'Account ka naam';

  @override
  String get settingsIban => 'IBAN';

  @override
  String get settingsPaymentNote =>
      'Yeh sirf bill par chhapega taake gahak khud bhej sake. App na paisay leti hai na bhejti hai, is liye koi bank account jodne ki zaroorat nahi.';

  @override
  String get settingsQrNote =>
      'Hum apni taraf se koi payment QR nahi banate. State Bank ke qanoon ke mutabiq QR sirf licensed banks aur payment companies bana sakti hain. Agar aap ke bank ne aap ko QR diya hai to us ki tasveer yahan laga dein.';

  @override
  String get settingsDataHealth => 'Data ki sehat';

  @override
  String get settingsDataHealthOk => 'Sab theek hai';

  @override
  String settingsDataHealthProblem(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count masle mile',
      one: '1 masla mila',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataHealthCheck => 'Abhi check karein';

  @override
  String get settingsAbout => 'App ke baare mein';

  @override
  String get settingsAboutBody =>
      'Sab kuch isi phone mein. Na server, na account, na internet ki zaroorat.';

  @override
  String get emptyNoResults => 'Kuch nahi mila';

  @override
  String get emptyNoResultsHint => 'Doosre lafz se talash karein';

  @override
  String get errorTitle => 'Ruk gaya';

  @override
  String get errorNothingWasSaved =>
      'Fikar na karein - kuch bhi galat save nahi hua.';

  @override
  String a11yRupees(String amount) {
    return 'Rupees $amount';
  }

  @override
  String a11yOwing(String amount) {
    return '$amount baqaya';
  }

  @override
  String get a11yLoading => 'Khul raha hai';

  @override
  String get errorStartupTitle => 'Hisaab khul nahi saka';

  @override
  String get errorStartupBody =>
      'Kuch zaya nahi hua. App band kar ke dobara kholein. Agar phir bhi yehi masla rahe to apni aakhri backup se wapas layein.';

  @override
  String get permissionDeniedTitle => 'Ijazat nahi mili';

  @override
  String get permissionDeniedBody =>
      'Yeh kaam karne ke liye phone ki settings mein is app ko ijazat deni hogi.';

  @override
  String get permissionOpenSettings => 'Phone ki settings kholein';

  @override
  String get tenderNoAccount =>
      'Paisay rakhne ka koi khata nahi mila. Settings mein cash khata dobara chalu karein.';

  @override
  String get itemArchiveConfirm =>
      'Yeh item counter par nazar nahi aayega. Purane bill jaise the waise hi rahenge.';

  @override
  String get settingsAddress => 'Pata';

  @override
  String get settingsTaxRegistered => 'Sales tax mein registered hoon';

  @override
  String get settingsTaxRegisteredNote =>
      'Zyada tar kiryana dukanein registered nahi hotin - bijli ke bill mein sales tax jama ho jata hai. Agar aap ke paas STRN hai tab hi yeh chalu karein.';

  @override
  String get errorStartupRecover => 'Backup se wapas layein';

  @override
  String get errorStartupNotReady =>
      'Backup se wapas lana M5 mein aayega. Abhi ke liye app band kar ke dobara kholein.';

  @override
  String healthWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count masle',
      one: '1 masla',
    );
    return 'Data mein $_temp0 mila. Settings mein dekh lein.';
  }

  @override
  String get stockAdjustTitle => 'Stock theek karein';

  @override
  String get stockAdjustCounted => 'Ginti ke baad kitna hai';

  @override
  String get stockAdjustCurrent => 'Abhi ledger kehta hai';

  @override
  String get stockAdjustReason => 'Wajah';

  @override
  String get stockAdjustReasonHint => 'Mahana ginti, toot gaya, chori';

  @override
  String get stockAdjustSave => 'Theek karein';

  @override
  String get stockAdjustDone => 'Stock theek ho gaya';

  @override
  String get stockAdjustNeedsReason => 'Wajah likhna zaroori hai';

  @override
  String get stockAdjustWriteOff => 'Zaya hua maal';

  @override
  String get stockAdjustRecount => 'Ginti';

  @override
  String get stockLowTitle => 'Kam stock';

  @override
  String get stockLowNone => 'Sab theek hai';

  @override
  String get stockLowSubtitle => 'Yeh cheezein khatam hone wali hain';

  @override
  String stockLowFloor(String floor) {
    return 'Hadd: $floor';
  }

  @override
  String get itemWholesalePrice => 'Thok ki qeemat';

  @override
  String get itemMrp => 'MRP (chhapi qeemat)';

  @override
  String get itemHsCode => 'HS code';

  @override
  String get itemDescription => 'Tafseel';

  @override
  String get itemTracksStock => 'Is ka stock rakhna hai';

  @override
  String get itemTracksStockOff => 'Service ya kharcha — stock nahi';

  @override
  String get itemMoreFields => 'Aur tafseel';

  @override
  String get settingsPrinter => 'Printer';

  @override
  String get printerTitle => 'Printer set karein';

  @override
  String get printerNone => 'Abhi koi printer nahi chuna.';

  @override
  String get printerHowItConnects => 'Printer kaise juda hai';

  @override
  String get printerViaLan => 'Wi-Fi par (LAN)';

  @override
  String get printerViaBluetooth => 'Bluetooth';

  @override
  String get printerViaUsb => 'USB taar';

  @override
  String get printerNotOnThisPhone => 'Is phone par nahi chal sakta';

  @override
  String get printerLooking => 'Printer dhoond rahe hain...';

  @override
  String get printerNoneFound =>
      'Koi printer nahi mila. Printer chalu hai? Wi-Fi ya Bluetooth juda hai?';

  @override
  String get printerSearchAgain => 'Dobara dhoondein';

  @override
  String get printerAddress => 'Printer ka pata';

  @override
  String get printerAddressHint => '192.168.1.50:9100';

  @override
  String get printerAddressNeeded => 'Pata likhna zaroori hai.';

  @override
  String get printerWidth => 'Kagaz ki chaurai';

  @override
  String get printerWidthHelp =>
      'Test print nikaal kar dekhein. Jo lakeer poori ek qatar mein aaye, wahi sahi hai.';

  @override
  String get printerColumns32 => '32 (58mm)';

  @override
  String get printerColumns42 => '42 (80mm)';

  @override
  String get printerColumns48 => '48 (80mm)';

  @override
  String get printerTestPrint => 'Test print nikaalein';

  @override
  String get printerTestSent => 'Test print bhej diya. Kagaz dekh lein.';

  @override
  String get printerCopies => 'Kitni copy';

  @override
  String get printerDrawer => 'Cash sale par draaz kholein';

  @override
  String get printerSave => 'Printer save karein';

  @override
  String get printerForget => 'Yeh printer hata dein';

  @override
  String get printerSaved => 'Printer save ho gaya.';

  @override
  String get printerPrinting => 'Print ho raha hai...';

  @override
  String get printerDone => 'Print ho gaya.';

  @override
  String get printerNotSent =>
      'Kuch nahi chhapa. Dobara koshish kar sakte hain.';

  @override
  String get printerPartial =>
      'Adha bill chhap kar ruk gaya. Kagaz dekh kar khud faisla karein.';

  @override
  String get printerUnknownAsk =>
      'Is bill ka print pehle nikla tha ya nahi, pata nahi chala. Kagaz dekh lein.';

  @override
  String get printerPrintAgain => 'Phir bhi print karein';

  @override
  String get printerAlreadyPrinted => 'Yeh bill pehle print ho chuka hai.';

  @override
  String get labelTitle => 'Sticker chhapein';

  @override
  String get labelCopies => 'Kitne sticker';

  @override
  String get labelPrint => 'Sticker chhapein';

  @override
  String get labelNoCode =>
      'Is cheez ka koi code nahi. Pehle barcode ya code likhein.';

  @override
  String get labelNoPrinter => 'Pehle printer set karein.';

  @override
  String get labelSent => 'Sticker printer par bhej diye.';

  @override
  String get labelPreview => 'Sticker par yeh aayega';

  @override
  String get historyTitle => 'Stock ki tafseel';

  @override
  String get historyNone => 'Abhi tak koi harkat nahi';

  @override
  String get historyOpening => 'Shuruaati stock';

  @override
  String get historySale => 'Bika';

  @override
  String get historySaleReturn => 'Wapas aaya';

  @override
  String get historyPurchase => 'Khareeda';

  @override
  String get historyAdjustment => 'Durusti';

  @override
  String get historyWastage => 'Zaya';

  @override
  String get historyOther => 'Aur';

  @override
  String historyBalance(Object qty) {
    return 'Baqi: $qty';
  }

  @override
  String get stockSummaryValue => 'Stock ki qeemat';

  @override
  String stockSummaryItems(Object count) {
    return '$count cheezein';
  }

  @override
  String stockSummaryLow(Object count) {
    return '$count kam';
  }

  @override
  String stockSummaryOut(Object count) {
    return '$count khatam';
  }

  @override
  String stockSummaryNegative(Object count) {
    return '$count ulta';
  }

  @override
  String get pictureAdd => 'Tasveer lagayein';

  @override
  String get pictureChange => 'Tasveer badlein';

  @override
  String get pictureRemove => 'Tasveer hatayein';

  @override
  String get pictureNotAnImage => 'Yeh tasveer nahi hai';

  @override
  String get scanTitle => 'Barcode scan karein';

  @override
  String get scanHint => 'Packet ka barcode camera ke saamne rakhein';

  @override
  String get scanNoCamera => 'Is phone mein camera nahi hai';

  @override
  String get scanDenied => 'Camera ki ijazat nahi mili';

  @override
  String get scanTorch => 'Roshni';

  @override
  String get scanNotFound => 'Yeh barcode kisi cheez par nahi hai';

  @override
  String get scanAddNew => 'Nayi cheez banayein';

  @override
  String get khataTitle => 'Khata';

  @override
  String get khataBalance => 'Kitna lena hai';

  @override
  String get khataAdvance => 'Jama shuda';

  @override
  String get khataOpenBills => 'Khule bill';

  @override
  String get khataNoBills => 'Koi udhaar baqi nahi';

  @override
  String get khataNoBillsHint => 'Is gahak ka poora hisaab saaf hai';

  @override
  String get khataReceive => 'Paisay wasool karein';

  @override
  String get khataDetails => 'Gahak ki tafseel';

  @override
  String get khataCreditLimitOver => 'Udhaar ki hadd se ziyada';

  @override
  String get wasooliTitle => 'Paisay wasool karein';

  @override
  String get wasooliAmount => 'Kitne paisay milay';

  @override
  String get wasooliMode => 'Kis tarah';

  @override
  String get wasooliReference => 'Reference (marzi se)';

  @override
  String get wasooliChequeNo => 'Cheque number';

  @override
  String get wasooliChequeBank => 'Bank ka naam';

  @override
  String get wasooliSettles => 'Yeh bill saaf honge';

  @override
  String get wasooliSettlesNone =>
      'Koi khula bill nahi — yeh raqam jama ho jayegi';

  @override
  String get wasooliOnAccount => 'Jama (advance)';

  @override
  String get wasooliSave => 'Wasooli save karein';

  @override
  String wasooliSaved(String amount) {
    return '$amount wasool ho gaye';
  }

  @override
  String get wasooliAmountRequired => 'Raqam likhein';

  @override
  String get wasooliChequeNoRequired => 'Cheque number likhein';

  @override
  String get tenderOverLimit => 'Udhaar ki hadd se ziyada';

  @override
  String tenderOverLimitDetail(String limit, String after) {
    return 'Hadd $limit hai. Is bill ke baad $after ho jayega.';
  }

  @override
  String get tenderOverLimitAllow => 'Phir bhi udhaar dein';
}
