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

  @override
  String get khataRemind => 'Yaad dilayein';

  @override
  String get khataRemindNoPhone => 'Is gahak ka number nahi hai';

  @override
  String get khataRemindNothingOwed => 'Kuch baqi nahi hai';

  @override
  String get chaseTitle => 'Udhaar wasooli';

  @override
  String get chaseEmpty => 'Kisi ka udhaar baqi nahi';

  @override
  String get chaseEmptyHint => 'Sab hisaab saaf hai';

  @override
  String get chaseTotal => 'Kul udhaar';

  @override
  String get chaseOverdue => 'Der se baqi';

  @override
  String chaseSince(int days) {
    return '$days din se';
  }

  @override
  String chaseBills(int count) {
    return '$count bill';
  }

  @override
  String get chaseAll => 'Sab';

  @override
  String get khataHistory => 'Purana hisaab';

  @override
  String get khataHistoryEmpty => 'Abhi koi len-den nahi';

  @override
  String get homePurchases => 'Kharidari';

  @override
  String get purchaseTitle => 'Nayi kharidari';

  @override
  String get purchaseSupplier => 'Supplier chunein';

  @override
  String get purchaseSupplierRequired => 'Supplier chunna zaroori hai';

  @override
  String get purchaseAddItem => 'Cheez shamil karein';

  @override
  String get purchaseNoLines => 'Abhi koi cheez nahi';

  @override
  String get purchaseNoLinesHint => 'Jo maal aaya hai woh shamil karein';

  @override
  String get purchaseCost => 'Kharid qeemat';

  @override
  String get purchaseFreight => 'Kiraya aur mazdoori';

  @override
  String get purchasePaid => 'Abhi diye';

  @override
  String get purchaseBillNo => 'Supplier ka bill number';

  @override
  String get purchaseGoods => 'Maal';

  @override
  String get purchaseTotal => 'Kul';

  @override
  String get purchaseOwing => 'Baqi';

  @override
  String get purchaseSave => 'Kharidari save karein';

  @override
  String purchaseSaved(String docNo) {
    return 'Kharidari $docNo save ho gayi';
  }

  @override
  String purchaseNewAverage(String rate) {
    return 'Nayi lagat $rate';
  }

  @override
  String get purchasePaidTooMuch => 'Bill se ziyada nahi de sakte';

  @override
  String get purchasesTitle => 'Kharidari';

  @override
  String get purchasesEmpty => 'Abhi koi kharidari nahi';

  @override
  String get purchasesEmptyHint => 'Jo maal aaye us ka bill yahan likhein';

  @override
  String get voidTitle => 'Bill mansookh karein';

  @override
  String get voidAction => 'Bill mansookh';

  @override
  String get voidReason => 'Wajah';

  @override
  String get voidReasonRequired => 'Wajah likhna zaroori hai';

  @override
  String get voidConfirm => 'Haan, mansookh karein';

  @override
  String get voidExplain =>
      'Bill mit-ta nahi. Ulta ijraa likha jayega aur maal wapas shumar hoga.';

  @override
  String voidDone(String docNo) {
    return '$docNo mansookh ho gaya';
  }

  @override
  String get returnTitle => 'Maal wapas';

  @override
  String get returnAction => 'Wapas lein';

  @override
  String get returnNothingLeft => 'Is bill se sab kuch wapas ho chuka';

  @override
  String get returnReason => 'Wajah';

  @override
  String get returnReasonRequired => 'Wajah likhna zaroori hai';

  @override
  String get returnPickSomething => 'Kam az kam ek cheez chunein';

  @override
  String get returnRefundNow => 'Abhi wapas diye';

  @override
  String returnLeft(String qty) {
    return '$qty baqi';
  }

  @override
  String get returnTotal => 'Wapsi ki raqam';

  @override
  String get returnSave => 'Wapsi save karein';

  @override
  String returnDone(String docNo) {
    return '$docNo save ho gaya';
  }

  @override
  String get returnOnAccount => 'Gahak ke khate mein jama';

  @override
  String get homeExpenses => 'Kharcha';

  @override
  String get expensesTitle => 'Kharchay';

  @override
  String get expensesEmpty => 'Abhi koi kharcha nahi';

  @override
  String get expensesEmptyHint =>
      'Kiraya, bijli, tankhwah — jo paisa dukaan se bahar gaya yahan likhein';

  @override
  String get expenseNew => 'Naya kharcha';

  @override
  String get expenseHead => 'Kis mad mein';

  @override
  String get expenseHeadRent => 'Dukaan ka kiraya';

  @override
  String get expenseHeadSalaries => 'Tankhwah';

  @override
  String get expenseHeadUtilities => 'Bijli, gas, pani';

  @override
  String get expenseHeadFreight => 'Maal bardari';

  @override
  String get expenseHeadMisc => 'Mutafarriq';

  @override
  String get expenseAmount => 'Raqam';

  @override
  String get expenseNote => 'Kis cheez ke liye';

  @override
  String get expenseNoteRequired => 'Likhein yeh kharcha kis cheez ka tha';

  @override
  String get expensePaidNow => 'Abhi diye';

  @override
  String get expensePayLater => 'Baad mein dena hai';

  @override
  String get expensePaidFrom => 'Kahan se diye';

  @override
  String get expensePayee => 'Kis ko dena hai';

  @override
  String get expensePayeeRequired => 'Batayein yeh kis ko dena hai';

  @override
  String get expenseSave => 'Kharcha save karein';

  @override
  String expenseSaved(String docNo) {
    return 'Kharcha $docNo save ho gaya';
  }

  @override
  String expenseOwedTo(String name) {
    return '$name ko dena hai';
  }

  @override
  String partyWeOwe(String amount) {
    return '$amount dena hai';
  }

  @override
  String get khataPayable => 'Kitna dena hai';

  @override
  String get khataPay => 'Paisay dein';

  @override
  String get khataOpenPayables => 'Jin ka dena baqi hai';

  @override
  String get khataNoPayables => 'Is supplier ka sab chuka diya';

  @override
  String get payTitle => 'Supplier ko paisay dein';

  @override
  String get payAmount => 'Kitne diye';

  @override
  String get paySettles => 'Yeh bill chuk jayenge';

  @override
  String payTooMuch(String amount) {
    return 'Sirf $amount dena hai';
  }

  @override
  String get paySave => 'Payment save karein';

  @override
  String paySaved(String amount) {
    return '$amount de diye';
  }

  @override
  String get backupTitle => 'Backup';

  @override
  String get backupExplain =>
      'Poora hisaab ek file mein band ho jata hai jo sirf aap ke password se khulti hai. Isay WhatsApp par khud ko, Google Drive ya kisi aur phone par rakh lein. Phone gum ho jaye to isi se sab wapas aayega.';

  @override
  String backupLast(String when) {
    return 'Aakhri backup: $when';
  }

  @override
  String get backupNever => 'Abhi tak koi backup nahi banaya';

  @override
  String get backupPassphrase => 'Backup ka password';

  @override
  String get backupPassphraseAgain => 'Password dobara likhein';

  @override
  String get backupPassphraseHint =>
      'Kam az kam 8 huroof. Yeh password bhool gaye to backup kabhi nahi khulega — kahin likh kar rakhein.';

  @override
  String get backupPassphraseShort => 'Password kam az kam 8 huroof ka ho';

  @override
  String get backupPassphraseMismatch => 'Dono password ek jaise nahi';

  @override
  String get backupMake => 'Backup banayein';

  @override
  String get backupMade => 'Backup ban gaya — ab isay mehfooz jagah bhejein';

  @override
  String get backupRestore => 'Backup se wapas layein';

  @override
  String get restoreTitle => 'Backup se wapas layein';

  @override
  String get restorePick => 'Backup file chunein';

  @override
  String restoreMadeOn(String when) {
    return 'Yeh backup $when ko bana tha';
  }

  @override
  String get restoreOpen => 'Backup kholein';

  @override
  String get restoreFound => 'Is backup mein';

  @override
  String restoreCounts(String bills, String parties, String items) {
    return '$bills bill · $parties gahak/supplier · $items cheezein';
  }

  @override
  String restoreLastEntry(String date) {
    return 'Aakhri entry: $date';
  }

  @override
  String get restoreWarning =>
      'Is phone par jo hisaab abhi hai us ki jagah yeh aa jayega. Mojooda hisaab mitaya nahi jayega, alag rakh diya jayega.';

  @override
  String get restoreConfirm => 'Haan, wapas layein';

  @override
  String get restoreRestarting => 'Hisaab wapas aa raha hai…';

  @override
  String get setupRestore => 'Pehle se hisaab hai? Backup se wapas layein';

  @override
  String get partyArchive => 'Khate se hatayein';

  @override
  String get partyArchiveConfirm =>
      'Yeh naam khate ki list mein nazar nahi aayega. Purana hisaab jaisa tha waisa rahega, aur Settings mein \'Hatayi hui cheezein\' se wapas laya ja sakta hai.';

  @override
  String get partyArchived => 'Khate se hata diya gaya';

  @override
  String get recycleTitle => 'Hatayi hui cheezein';

  @override
  String get recycleItems => 'Cheezein';

  @override
  String get recycleParties => 'Gahak aur supplier';

  @override
  String get recycleEmpty => 'Kuch hataya nahi gaya';

  @override
  String get recycleRestore => 'Wapas layein';

  @override
  String recycleRestored(String name) {
    return '$name wapas aa gaya';
  }

  @override
  String get purchaseReturnTitle => 'Supplier ko maal wapas';

  @override
  String get purchaseReturnRefund => 'Supplier ne abhi wapas diye';

  @override
  String get chequeDue => 'Kab jama ho sakta hai';

  @override
  String get chequeDueToday => 'Aaj';

  @override
  String chequeDueInDays(String days) {
    return '$days din baad';
  }

  @override
  String get chequeDuePick => 'Tareekh chunein';

  @override
  String chequeDueOn(String date) {
    return 'Tareekh: $date';
  }

  @override
  String get chequeNeedsCustomer =>
      'Cheque sirf naam wale gahak se lein — bounce hua to kis se mangenge?';

  @override
  String get homeCheques => 'Cheque';

  @override
  String get chequesInHand => 'Haath mein';

  @override
  String get chequesBounced => 'Bounce hue';

  @override
  String get chequesEmpty => 'Koi cheque haath mein nahi';

  @override
  String get chequesEmptyHint =>
      'Wasooli ya bill par cheque lein to yahan nazar aayega';

  @override
  String get chequeDueTodayChip => 'Aaj jama karein';

  @override
  String chequeDueInChip(String days) {
    return '$days din baqi';
  }

  @override
  String chequeOverdueChip(String days) {
    return '$days din guzar gaye';
  }

  @override
  String get chequeNoDate => 'Tareekh nahi';

  @override
  String get chequeAtBank => 'Bank mein';

  @override
  String get chequeDeposit => 'Bank mein lagaya';

  @override
  String get chequeClear => 'Clear ho gaya';

  @override
  String get chequeBounce => 'Bounce ho gaya';

  @override
  String get chequeClearInto => 'Kis account mein aaya';

  @override
  String get chequeBounceReason => 'Bank ne kya likha (marzi se)';

  @override
  String chequeBounceWarning(String amount, String name) {
    return '$amount phir se $name ke khate mein chala jayega.';
  }

  @override
  String chequeNoticeBy(String date) {
    return '489-F notice $date tak bhejein';
  }

  @override
  String chequeBouncedOn(String date) {
    return 'Bounce: $date';
  }

  @override
  String chequeNotYet(String date) {
    return 'Bank ise $date se pehle nahi lega';
  }

  @override
  String homeChequesDue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheque bank le jane ka din aa gaya',
      one: '1 cheque bank le jane ka din aa gaya',
    );
    return '$_temp0';
  }

  @override
  String get chequeNoticeTitle => '489-F notice';

  @override
  String get chequeNoticeHint =>
      'Yeh notice aap ke hisaab se bana hai. Bhejne se pehle wakeel ko zaroor dikhayein.';

  @override
  String get chequeNoticeShare => 'Notice PDF share karein';

  @override
  String chequeNoticeLate(String date) {
    return 'Notice ki muddat $date ko guzar gayi';
  }

  @override
  String get tenderChequeBounced => 'Is gahak ka cheque bounce ho chuka hai';

  @override
  String tenderChequeBouncedDetail(int count, String owed) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheque wapas aaye',
      one: '1 cheque wapas aaya',
    );
    return '$_temp0, aur $owed ab bhi baqi hain. Naqad lein, ya soch kar udhaar dein.';
  }

  @override
  String get tenderChequeBouncedAllow => 'Phir bhi dein';

  @override
  String khataChequeBounced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cheque bounce hue',
      one: '1 cheque bounce hua',
    );
    return '$_temp0';
  }

  @override
  String get chequeBounceFee => 'Bank ki fee, agar kaati (marzi se)';

  @override
  String get chequeBounceFeeFrom => 'Fee kis account se gayi';

  @override
  String chequeBounceFeeNote(String chequeNo, String name) {
    return 'Cheque $chequeNo ($name) bounce ki bank fee';
  }

  @override
  String chequeBounceFeeFailed(String error) {
    return 'Bounce save ho gaya, lekin bank fee save nahi hui: $error';
  }

  @override
  String get payByCheque => 'Cheque se diya';

  @override
  String get payChequeDrawnOn => 'Kis bank account ka cheque';

  @override
  String get chequesIssued => 'Humare diye hue cheque';

  @override
  String get chequeIssuedPresentable => 'Pesh ho sakta hai';

  @override
  String get chequeIssuedPaid => 'Bank ne ada kar diya';

  @override
  String chequeIssuedBounceWarning(String amount, String name) {
    return '$amount phir se $name ko dene honge.';
  }

  @override
  String homeChequesIssuedDue(String amount, String days) {
    return 'Rs $amount ke apne cheque $days din mein pesh ho sakte hain — bank mein paisay rakhein';
  }

  @override
  String get partyPriceTier => 'Kis rate par bechna hai';

  @override
  String get partyTierRetail => 'Parchoon (retail)';

  @override
  String get partyTierWholesale => 'Thok (wholesale)';

  @override
  String get partyDiscount => 'Har cheez par discount % (marzi se)';

  @override
  String get partyDiscountInvalid => '0 se 100 ke darmiyan likhein';

  @override
  String get partyAddress => 'Pata';

  @override
  String get partyCity => 'Shehar';

  @override
  String get partyCnic => 'CNIC (marzi se)';

  @override
  String get homeQuotations => 'Quotation';

  @override
  String get quotationsTitle => 'Quotations';

  @override
  String get quotationsEmpty => 'Abhi koi quotation nahi';

  @override
  String get quotationsEmptyHint =>
      'Bill ke payment sheet par \"Quotation banayein\" dabayein';

  @override
  String get quotationMake => 'Quotation banayein';

  @override
  String quotationSaved(String docNo) {
    return 'Quotation $docNo ban gayi';
  }

  @override
  String quotationBilledAs(String docNo) {
    return 'Bill $docNo ban gaya';
  }

  @override
  String get quotationExpired => 'Muddat guzar gayi';

  @override
  String get quotationOpen => 'Khuli hai';

  @override
  String quotationValidUntil(String date) {
    return '$date tak';
  }

  @override
  String get quotationSharePdf => 'PDF bhejein';

  @override
  String get quotationBill => 'Is se bill banayein';

  @override
  String get quotationCounterBusy =>
      'Counter par pehle se ek bill chal raha hai. Pehle usay mukammal ya khali karein.';

  @override
  String get quotationItemGone =>
      'Is quotation ki ek cheez ab list mein nahi. Wapas la kar dobara koshish karein.';

  @override
  String get homeChallans => 'Challan';

  @override
  String get challansTitle => 'Delivery challan';

  @override
  String get challansEmpty => 'Abhi koi challan nahi';

  @override
  String get challansEmptyHint =>
      'Maal bill se pehle bhejna ho to payment sheet par \"Challan banayein\" dabayein';

  @override
  String get challanMake => 'Challan banayein';

  @override
  String challanSaved(String docNo) {
    return 'Challan $docNo ban gaya, maal nikal gaya';
  }

  @override
  String get challanNeedsCustomer =>
      'Challan par gahak ka naam zaroori hai. Pehle gahak chunein.';

  @override
  String get challanUnbilled => 'Bill baqi hai';

  @override
  String get challanCancelled => 'Maal wapas aa gaya';

  @override
  String get challanCancel => 'Maal wapas aa gaya';

  @override
  String get challanCancelReason => 'Challan wapas';

  @override
  String challanCancelConfirm(String docNo) {
    return 'Challan $docNo ka saara maal wapas shelf par aa jaye ga. Pakka?';
  }

  @override
  String get chargeTitle => 'Khate mein charge dalein';

  @override
  String get chargeAmount => 'Kitne ka charge';

  @override
  String get chargeNote => 'Kis cheez ka (zaroori)';

  @override
  String get chargeSave => 'Khate mein dalein';

  @override
  String chargeSaved(String amount) {
    return '$amount khate mein daal diya';
  }

  @override
  String get chargeNeedsAmount => 'Raqam likhein';

  @override
  String get chargeNeedsNote =>
      'Likhein kis cheez ka charge hai, warna gahak nahi dega';

  @override
  String chargeBounceFee(String name) {
    return 'Yeh fee $name ke khate mein bhi dalein';
  }

  @override
  String chargeBounceFeeNote(String chequeNo) {
    return 'Cheque $chequeNo bounce ki bank fee';
  }

  @override
  String get chequeDone => 'Ho gaya';
}
