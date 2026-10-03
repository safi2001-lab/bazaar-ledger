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
  String get homeReports => 'Report';

  @override
  String get reportsTitle => 'Report';

  @override
  String get reportProfitAndLoss => 'Nafa nuqsan';

  @override
  String get reportProfitAndLossHint =>
      'Bikri, maal ki laagat, kharchay aur asal nafa';

  @override
  String get reportSalesByItem => 'Cheez-war bikri';

  @override
  String get reportSalesByItemHint =>
      'Kaunsi cheez kitni biki aur kitna nafa diya';

  @override
  String get reportExpenses => 'Kharchay';

  @override
  String get reportExpensesHint => 'Kiraya, bijli, tankhwa: kahan kitna gaya';

  @override
  String get reportCashBook => 'Cash book';

  @override
  String get reportCashBookHint =>
      'Galle mein kya aaya, kya gaya, kitna hona chahiye';

  @override
  String get reportDayBook => 'Roznamcha';

  @override
  String get reportDayBookHint => 'Khaton mein har entry, jis tarteeb se hui';

  @override
  String get reportStockValue => 'Stock ki qeemat';

  @override
  String get reportStockValueHint => 'Shelf par kitne ka maal hai';

  @override
  String get reportToday => 'Aaj';

  @override
  String get reportThisMonth => 'Is mahina';

  @override
  String get reportLastMonth => 'Pichla mahina';

  @override
  String get reportThisYear => 'Is saal';

  @override
  String get reportAsOfNow => 'Abhi tak';

  @override
  String get reportShareCsv => 'CSV bhejein';

  @override
  String get reportSalesByDay => 'Roz ki bikri';

  @override
  String get reportSalesByDayHint =>
      'Har din kitne bill, kitni bikri, kitna udhaar';

  @override
  String get reportReceivables => 'Udhaar kitna purana';

  @override
  String get reportReceivablesHint => 'Kis par kitna baqi hai, aur kab se';

  @override
  String get reportSharePdf => 'PDF bhejein';

  @override
  String get reportPayables => 'Suppliers ka baqi';

  @override
  String get reportPayablesHint => 'Kis supplier ka kitna dena hai, aur kab se';

  @override
  String get usersTitle => 'Staff aur PIN';

  @override
  String get usersMyPin => 'Mera PIN rakhein';

  @override
  String get usersAdd => 'Staff shamil karein';

  @override
  String get usersName => 'Naam';

  @override
  String get usersPin => 'PIN (4 se 6 hindsay)';

  @override
  String get usersPinAgain => 'PIN dobara';

  @override
  String get usersPinMismatch => 'Dono PIN ek jaisay nahi';

  @override
  String get usersPinInvalid => 'PIN 4 se 6 hindson ka ho';

  @override
  String get usersPinSaved => 'PIN rakh diya';

  @override
  String get usersNoPin => 'PIN nahi';

  @override
  String get usersInactive => 'Staff mein nahi';

  @override
  String get usersRemove => 'Staff se hatayein';

  @override
  String get usersLetBack => 'Wapas shamil karein';

  @override
  String get usersNewPin => 'Naya PIN';

  @override
  String get usersRole => 'Kaam';

  @override
  String get usersOwnerPinFirst =>
      'Pehle apna PIN rakhein, taake staff aap ki screens na khol sakay.';

  @override
  String get roleOwner => 'Malik';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleAccountant => 'Munshi';

  @override
  String get roleCashier => 'Cashier';

  @override
  String get signInTitle => 'Kaun hai?';

  @override
  String get signInPin => 'PIN';

  @override
  String get signInOpen => 'Kholein';

  @override
  String get signInWrong => 'Ghalat PIN';

  @override
  String get homeLock => 'Taala lagayein';

  @override
  String homeSignedInAs(String name, String role) {
    return '$name ($role)';
  }

  @override
  String get homeDayClose => 'Din band';

  @override
  String get dayCloseTitle => 'Din band karein';

  @override
  String get dayCloseExpected => 'Khaton ke hisaab se galle mein';

  @override
  String get dayCloseCounted => 'Gin kar kitna nikla';

  @override
  String get dayCloseNote => 'Farq ki wajah (marzi se)';

  @override
  String get dayCloseSave => 'Din band karein';

  @override
  String get dayCloseMatches => 'Galla khaton se barabar hai';

  @override
  String dayCloseShort(String amount) {
    return '$amount kam hai';
  }

  @override
  String dayCloseOver(String amount) {
    return '$amount zyada hai';
  }

  @override
  String get dayCloseDone => 'Din band ho gaya';

  @override
  String dayCloseLast(String when, String name) {
    return 'Pichli dafa: $when, $name';
  }

  @override
  String get auditTitle => 'Kaun ne kya kiya';

  @override
  String get auditEveryone => 'Sab';

  @override
  String get auditEmpty => 'Abhi kuch nahi hua';

  @override
  String get reportTrialBalance => 'Trial balance';

  @override
  String get reportTrialBalanceHint =>
      'Har khata apni taraf, dono taraf barabar';

  @override
  String get reportBalanceSheet => 'Balance sheet';

  @override
  String get reportBalanceSheetHint =>
      'Dukaan ke paas kya hai, kis ka dena hai, malik ka kya hai';

  @override
  String get homeAccounts => 'Hisaab kitaab';

  @override
  String get accountsTitle => 'Hisaab kitaab';

  @override
  String get accountsWriteVoucher => 'Voucher likhein';

  @override
  String get accountTypeAsset => 'Jo dukaan ke paas hai';

  @override
  String get accountTypeLiability => 'Jo dena hai';

  @override
  String get accountTypeEquity => 'Malik ka';

  @override
  String get accountTypeIncome => 'Aamdani';

  @override
  String get accountTypeExpense => 'Kharchay';

  @override
  String get accountLedgerEmpty => 'Is khate mein abhi kuch nahi';

  @override
  String get journalTitle => 'Journal voucher';

  @override
  String get journalNarration => 'Kis liye (zaroori)';

  @override
  String get journalDebit => 'Debit';

  @override
  String get journalCredit => 'Credit';

  @override
  String get journalAddLine => 'Aur line';

  @override
  String get journalSave => 'Voucher save karein';

  @override
  String journalSaved(String entryNo) {
    return 'Voucher $entryNo save ho gaya';
  }

  @override
  String journalDifference(String amount) {
    return 'Farq: $amount';
  }

  @override
  String get journalBalanced => 'Dono taraf barabar';

  @override
  String get journalPickAccount => 'Khata chunein';

  @override
  String get firmsTitle => 'Dukaanein aur firms';

  @override
  String get firmsAdd => 'Nayi firm';

  @override
  String get firmsName => 'Firm ka naam';

  @override
  String get firmsOwner => 'Malik ka naam';

  @override
  String get firmsCity => 'Shehar';

  @override
  String get firmsOpen => 'Kholein';

  @override
  String get firmsCurrent => 'Khuli hui';

  @override
  String firmsAdded(String name) {
    return '$name ban gayi';
  }

  @override
  String firmsSwitched(String name) {
    return 'Ab $name khuli hai';
  }

  @override
  String posScannedExpired(String batch, String date) {
    return 'Batch $batch ki expiry $date guzar chuki hai. Yeh na bechein.';
  }

  @override
  String posSerialAlreadyOnBill(String serial) {
    return '$serial pehle se bill par hai';
  }

  @override
  String get posScanTheSerial =>
      'Yeh cheez serial / IMEI se bikti hai. Uska number scan ya type karein.';

  @override
  String get reportExpiry => 'Expiry';

  @override
  String get reportExpiryHint =>
      'Kaunsa batch guzar gaya, kaunsa guzarne wala hai';

  @override
  String get itemTracksBatch => 'Batch aur expiry se';

  @override
  String get itemTracksSerial => 'Serial / IMEI se';

  @override
  String get purchaseBatch => 'Batch no.';

  @override
  String get purchaseExpiry => 'Expiry';

  @override
  String get purchaseSerials => 'Serial / IMEI (har line mein ek)';

  @override
  String purchaseSerialCount(int count) {
    return '$count number';
  }

  @override
  String get purchaseSerialsNeeded => 'Har piece ka serial / IMEI likhein';

  @override
  String get purchaseBatchNeeded =>
      'Batch no. likhein, aur expiry YYYY-MM-DD mein';

  @override
  String get placesTitle => 'Maal kahan hai';

  @override
  String get placesMain => 'Dukaan';

  @override
  String get placesBatches => 'Batch';

  @override
  String get placesSerials => 'Serial / IMEI';

  @override
  String get placesMove => 'Maal bhejein';

  @override
  String get placesTo => 'Kahan (masalan GODOWN)';

  @override
  String get placesMoveButton => 'Bhej dein';

  @override
  String get placesMoved => 'Maal bhej diya';

  @override
  String get partyTaxRegistered => 'Sales tax mein registered';

  @override
  String get partyOnAtl => 'Active taxpayer list (ATL) par hai';

  @override
  String get taxTitle => 'Tax';

  @override
  String get taxNeverSent =>
      'Sab hisaab isi phone par hota hai, kahin bheja nahi jata. Return khud ya accountant se IRIS par file karein.';

  @override
  String get taxRegistered => 'Dukaan sales tax mein registered hai';

  @override
  String get taxRegisteredHint =>
      'Registered dukaan bill par 18% sales tax lagati hai; ghair registered koi tax nahi lagati';

  @override
  String get taxPricesInclude => 'Qeematon mein tax shamil hai';

  @override
  String get taxTajirDost => 'Tajir Dost 1%';

  @override
  String get taxTurnoverThisMonth => 'Is mahine ki bikri';

  @override
  String get taxFixedAtOnePercent => '1% fixed tax';

  @override
  String get taxUtilityWht => 'Bijli ke bill par kata hua tax';

  @override
  String get taxToPay => 'Dena hai';

  @override
  String get reportSalesTax => 'Sales tax';

  @override
  String get reportSalesTaxHint =>
      'Is mahine kitna sales tax aur further tax dena hai';

  @override
  String get reportTajirDost => 'Tajir Dost 1%';

  @override
  String get reportTajirDostHint => 'Har mahine ki bikri ka 1%';

  @override
  String get paySection73 =>
      'Section 73: Rs 50,000 se zyada naqad adaygi par is maal ka input tax nahi milega. Bank ya cheque se dein.';

  @override
  String get syncTitle => 'Wi-fi par counters';

  @override
  String get syncStaysInShop =>
      'Counters dukaan ke apne wi-fi par milte hain. Internet par kuch nahin jata.';

  @override
  String get syncHostSwitch => 'Counters ko is phone se milne dein';

  @override
  String get syncHostHint =>
      'Yeh phone master hai. Isay dukaan ke wi-fi par khula rakhein.';

  @override
  String get syncAddress => 'Counters ke liye pata';

  @override
  String get syncNoAddress => 'Yeh phone kisi wi-fi par nahin';

  @override
  String get syncLetJoin => 'Naya counter jorein';

  @override
  String get syncJoinCode => 'Yeh code counter par likhein';

  @override
  String get syncDevices => 'Is dukaan ke phone';

  @override
  String get syncMasterRole => 'Master';

  @override
  String syncCounterRole(String prefix) {
    return 'Counter · bill $prefix';
  }

  @override
  String get syncThisPhone => 'Yeh phone';

  @override
  String syncLastSynced(String when) {
    return 'Aakhri sync $when';
  }

  @override
  String get syncNever => 'Abhi sync nahin hua';

  @override
  String get syncNow => 'Abhi sync karein';

  @override
  String syncDone(String sent, String received) {
    return '$sent bheje, $received aaye';
  }

  @override
  String syncConflicts(String count) {
    return '$count takraao nishaan wale naam se rakhe gaye';
  }

  @override
  String syncCounterOf(String host) {
    return 'Yeh phone $host wale master ka counter hai. Har aadhe minute mein khud sync hota hai.';
  }

  @override
  String get syncJoinTitle => 'Dukaan ke master phone se jurein';

  @override
  String get syncJoinHint =>
      'Master par: Settings, Wi-fi par counters, Naya counter jorein. Dono phone ek hi wi-fi par hon.';

  @override
  String get syncMasterAddress => 'Master ka pata';

  @override
  String get syncCode => 'Master par dikhaya code';

  @override
  String get syncCounterName => 'Is counter ka naam';

  @override
  String get syncCounterNameHint => 'maslan Counter 2';

  @override
  String get syncJoin => 'Jurein';

  @override
  String get importTitle => 'Excel se laayein';

  @override
  String get importHint =>
      'Apni purani list .xlsx, .xls ya .csv mein chunein. Pehli line mein columns ke naam hon, maslan Name, Sale price, Stock.';

  @override
  String get importItems => 'Maal';

  @override
  String get importParties => 'Khata';

  @override
  String get importPick => 'File chunein';

  @override
  String importReady(String count) {
    return '$count line tayyar';
  }

  @override
  String importProblems(String count) {
    return '$count line nahin aa sakti';
  }

  @override
  String importRun(String count) {
    return '$count laayein';
  }

  @override
  String importDone(String added, String skipped) {
    return '$added aa gaye, $skipped chhor diye';
  }

  @override
  String importColumns(String columns) {
    return 'Columns: $columns';
  }

  @override
  String get settingsBooksEncrypted => 'Is phone par hisaab encrypted hai';

  @override
  String get settingsBooksPlain =>
      'Is phone par hisaab encrypted nahin: phone ka keystore key nahin rakh saka';

  @override
  String settingsCrashes(String count) {
    return 'App is phone par $count dafa kisi ghalti par ruki';
  }

  @override
  String get settingsCrashesClear => 'Saaf karein';

  @override
  String get itemVipPrice => 'VIP qeemat';

  @override
  String get partyTierVip => 'VIP';

  @override
  String posScaleUnknown(String plu) {
    return 'Scale label par PLU $plu kisi maal ka code nahin';
  }

  @override
  String posScaleNoPrice(String name) {
    return '$name ki qeemat nahin, is liye scale ki qeemat se wazan nahin nikal sakta';
  }

  @override
  String get scaleTitle => 'Tarazu ke labels';

  @override
  String get scaleHint =>
      'Tarazu jo barcode chhapta hai us mein maal ka PLU aur wazan ya qeemat hoti hai. Maal ka code wahi rakhein jo tarazu mein PLU hai.';

  @override
  String get scaleWeightPrefixes => 'Wazan wale prefix (maslan 21, 22)';

  @override
  String get scalePricePrefixes => 'Qeemat wale prefix (maslan 23, 24)';

  @override
  String get scalePluDigits => 'PLU ke hindse';

  @override
  String get scalePriceInPaisa => 'Qeemat paison mein chhapti hai';

  @override
  String get scaleSave => 'Save karein';

  @override
  String get scaleSaved => 'Tarazu ke labels save ho gaye';

  @override
  String get recipesTitle => 'Banana (recipe)';

  @override
  String get recipesNew => 'Nayi recipe';

  @override
  String get recipesEmpty =>
      'Abhi koi recipe nahin. Jo cheez aap khud banate hain, us ki recipe likhein.';

  @override
  String recipesMakes(String qty, String unit, String name) {
    return 'Ek batch: $qty $unit $name';
  }

  @override
  String get recipesMake => 'Banayein';

  @override
  String get recipesRuns => 'Kitne batch';

  @override
  String recipesMade(String no, String qty, String name) {
    return '$no: $qty $name ban gaye';
  }

  @override
  String get recipesName => 'Recipe ka naam';

  @override
  String get recipesOutput => 'Kya banta hai';

  @override
  String get recipesPickItem => 'Maal chunein';

  @override
  String get recipesBatchMakes => 'Ek batch mein kitna';

  @override
  String get recipesOverhead => 'Mazdoori aur packing (Rs)';

  @override
  String get recipesComponents => 'Kya lagta hai (ek batch mein)';

  @override
  String get recipesPerBatch => 'Ek batch mein';

  @override
  String get recipesAddComponent => 'Aur cheez';

  @override
  String get recipesSave => 'Save karein';

  @override
  String get vansTitle => 'Gaariyan (van)';

  @override
  String get vansNew => 'Nayi gaari';

  @override
  String get vansName => 'Gaari ka naam';

  @override
  String get vansAdd => 'Jorein';

  @override
  String get vansEmpty => 'Abhi koi gaari nahin';

  @override
  String get vansThisPhone => 'Yeh phone kahan se bechta hai';

  @override
  String get vansShopFloor => 'Dukaan';

  @override
  String vansToday(String count) {
    return 'Aaj $count bill, cash:';
  }

  @override
  String vansSettled(String amount) {
    return 'Hisaab ho gaya: $amount jama';
  }

  @override
  String get vansLoad => 'Maal laadein';

  @override
  String get vansSettle => 'Hisaab karein';

  @override
  String get vansOnBoard => 'Gaari mein maal';

  @override
  String get vansQty => 'Kitna';

  @override
  String get vansExpected => 'Rider ke paas hona chahiye';

  @override
  String get vansCounted => 'Rider ne diya (Rs)';

  @override
  String get vansReturnUnsold => 'Bacha hua maal dukaan wapas';

  @override
  String get vansSettledEven => 'Hisaab barabar';

  @override
  String vansSettledShort(String amount) {
    return 'Hisaab ho gaya, $amount kam';
  }

  @override
  String vansSettledOver(String amount) {
    return 'Hisaab ho gaya, $amount zyada';
  }

  @override
  String get fbrTitle => 'FBR digital invoicing';

  @override
  String get fbrWhatIsSent =>
      'Chalu karne par har bill (maal, qeemat, tax, kharidar ka NTN) FBR ko jata hai. Band ho to kuch nahin jata.';

  @override
  String get fbrReport => 'Har bill FBR ko bhejein';

  @override
  String get fbrSandbox => 'FBR ka test gateway (sandbox)';

  @override
  String get fbrToken => 'PRAL ka token';

  @override
  String get fbrBaseUrl => 'Integrator ka pata (khali = FBR)';

  @override
  String get fbrSave => 'Save karein';

  @override
  String get fbrSaved => 'FBR ki setting save ho gayi';

  @override
  String get fbrBills => 'FBR ko bheje bill';

  @override
  String get fbrSendNow => 'Abhi bhejein';

  @override
  String fbrSent(String posted, String rejected, String waiting) {
    return '$posted qabool, $rejected wapas, $waiting intezar mein';
  }

  @override
  String get fbrPosted => 'Qabool';

  @override
  String get fbrRejected => 'Wapas';

  @override
  String get fbrPending => 'Intezar';

  @override
  String get fbrLate => '72 ghante guzar gaye; credit note banayein';

  @override
  String get fbrRetry => 'Dobara bhejein';

  @override
  String get driveTitle => 'Google Drive par roz backup';

  @override
  String get driveExplain =>
      'Roz jab app khulti hai, hisaab upar wale password se band ho kar aap ki apni Google Drive ke app folder mein chala jata hai. Aakhri 7 rakhe jate hain. Naye phone par wahi Google account aur yehi password chahiye.';

  @override
  String get driveTurnOn => 'Drive backup chalu karein';

  @override
  String get driveTurnOff => 'Drive backup band karein';

  @override
  String get driveOn => 'Drive backup chalu hai';

  @override
  String driveLast(String when) {
    return 'Drive par aakhri backup: $when';
  }

  @override
  String driveFailed(String reason) {
    return 'Drive tak nahi pohncha: $reason';
  }

  @override
  String get driveNow => 'Abhi Drive par bhejein';

  @override
  String get driveRestore => 'Google Drive se wapas layein';

  @override
  String get driveNone => 'Drive par koi backup nahi mila';

  @override
  String get drivePick => 'Kaunsi backup wapas layein?';

  @override
  String get planTitle => 'Plan';

  @override
  String planCurrent(String plan) {
    return 'Aap ka plan: $plan';
  }

  @override
  String planPerYear(String price) {
    return '$price / saal';
  }

  @override
  String get planBuy => 'Yeh plan lein';

  @override
  String get planIsYours => 'Yeh aap ka plan hai';

  @override
  String get planRestore => 'Pehle se khareeda hai? Wapas layein';

  @override
  String get planNoBilling =>
      'Is build mein plan khareedne ka intezam nahi. Play Store wali app se khareedein.';

  @override
  String planNeeded(String plan) {
    return 'Iske liye $plan plan chahiye';
  }

  @override
  String get planTestTitle => 'Sirf test ke liye: plan chunein';

  @override
  String get planTestNote =>
      'Yeh sirf test build mein hai, asal app mein nahi. Koi paisa nahi lagta.';

  @override
  String get planTestReal => 'Jo khareeda hai';

  @override
  String planTestActive(String plan) {
    return 'Test plan chal raha hai: $plan';
  }

  @override
  String get planFreeIncludes =>
      'Hamesha muft: bill, khata, stock, cash book, printing, WhatsApp aur hath se backup.';

  @override
  String get planFeatNoWatermark => 'Bill par \'Bazaar Ledger\' ki line nahi';

  @override
  String get planFeatAutoDriveBackup => 'Roz Google Drive backup';

  @override
  String get planFeatCheques => 'Post-dated cheque';

  @override
  String get planFeatPriceLists => 'Wholesale aur VIP rate';

  @override
  String get planFeatAccountingReports =>
      'Munafa-nuqsan, balance sheet aur tax reports';

  @override
  String get planFeatTracking => 'Batch, expiry aur serial/IMEI';

  @override
  String get planFeatScaleLabels => 'Tarazu ke labels';

  @override
  String get planFeatGodowns => 'Godown aur stock transfer';

  @override
  String get planFeatLanSync => 'Wi-fi par kai counter';

  @override
  String get planFeatFbr => 'FBR ko bill live bhejna';

  @override
  String get planFeatManufacturing => 'Recipe aur maal banana';

  @override
  String get planFeatVans => 'Gaari (van) sales';

  @override
  String planFirms(int count) {
    return '$count firms tak';
  }

  @override
  String get planFirmsUnlimited => 'Jitni chahein firms';

  @override
  String planUsers(int count) {
    return '$count log, apne PIN ke sath';
  }

  @override
  String get planUsersUnlimited => 'Jitne chahein log';

  @override
  String get syncFind => 'Wi-fi par master dhoondein';

  @override
  String get syncFindNone =>
      'Koi master nahi mila. Dono phone ek hi wi-fi par hon, ya address khud likhein.';

  @override
  String get reportPurchaseRegister => 'Khareed register';

  @override
  String get reportPurchaseRegisterHint =>
      'Har khareed ka bill, supplier ka NTN aur tax';

  @override
  String get statementShare => 'Hisaab ka statement (PDF)';

  @override
  String get statementThisMonth => 'Is mahine';

  @override
  String get statementLastMonth => 'Pichhle mahine';

  @override
  String get statementThisYear => 'Is saal';

  @override
  String get statementAll => 'Shuru se ab tak';

  @override
  String get chargeCancel => 'Yeh charge wapas lein';

  @override
  String chargeCancelConfirm(String no) {
    return '$no wapas lena hai? Khata se hat jayega.';
  }

  @override
  String get chargeCancelReason => 'Charge wapas liya';

  @override
  String get chargeCancelled => 'Charge wapas ho gaya';

  @override
  String challanBillAll(int count) {
    return 'Is gahak ke $count aur challan bhi isi bill mein';
  }

  @override
  String get accountsAdd => 'Naya account';

  @override
  String get accountsAddName => 'Account ka naam';

  @override
  String get accountsTypeAsset => 'Asaasa (asset)';

  @override
  String get accountsTypeLiability => 'Qarz (liability)';

  @override
  String get accountsTypeEquity => 'Malik ka (equity)';

  @override
  String get accountsTypeIncome => 'Aamdani';

  @override
  String get accountsTypeExpense => 'Kharcha';

  @override
  String get accountsCloseYear => 'Saal band karein';

  @override
  String accountsCloseYearConfirm(String year) {
    return 'Saal $year ka munafa retained earnings mein chala jayega. Band karein?';
  }

  @override
  String accountsYearClosed(String no) {
    return 'Saal band ho gaya ($no)';
  }

  @override
  String get vansSettleYesterday => 'Kal ka hisaab (aaj nahi)';

  @override
  String get syncClashHint =>
      'Do counters par ek hi code ya barcode se do cheezen ban gayin. Dono rakhi gayin, doosri ke naam par ~ nishaan hai. Theek kar ke \'Ho gaya\' dabayein.';

  @override
  String get syncClashDone => 'Ho gaya';

  @override
  String get chequeDone => 'Ho gaya';

  @override
  String quickAddCustomer(String name) {
    return '\'$name\' ko naya gahak banayein';
  }

  @override
  String quickAddSupplier(String name) {
    return '\'$name\' ko naya supplier banayein';
  }

  @override
  String quickAddItem(String name) {
    return '\'$name\' ko naya maal banayein';
  }

  @override
  String quickAddBarcode(String code) {
    return 'Barcode $code se naya maal banayein';
  }

  @override
  String quickAddCode(String code) {
    return 'Code $code se naya maal banayein';
  }

  @override
  String get quickAddScaleHint =>
      'Code lag jaye to tarazu ka har label khud bill par aa jaye ga.';

  @override
  String get quickBackToBill => 'Bill par wapas';

  @override
  String get quickSupplierTitle => 'Naya supplier';

  @override
  String get quickPartyMobile => 'Mobile (marzi se)';

  @override
  String get quickPartyMobileHint => '0300 1234567';

  @override
  String get quickPartyMobileInvalid =>
      'Mobile number is tarah likhein: 0300 1234567';

  @override
  String get quickPartyCreditLimit => 'Udhaar ki hadd (marzi se)';

  @override
  String get quickPartyTwins => 'Yeh pehle se khata mein hain';

  @override
  String get quickPartyTwinsHint =>
      'Agar yehi hain to naam par tap karein. Koi aur hain to naya banayein.';

  @override
  String get quickAddAnyway => 'Nahi, naya banayein';

  @override
  String get quickItemTwins => 'Yeh maal pehle se hai';

  @override
  String get quickItemTwinsHint =>
      'Agar yehi hai to is par tap karein. Kuch aur hai to naya banayein.';

  @override
  String get quickItemBuyingAt => 'Khareed ki qeemat (fi unit)';

  @override
  String get quickItemNoCost =>
      'Khareed ki qeemat aur stock maalik baad mein Maal se daalein ge.';

  @override
  String entryReceiptTitle(String no) {
    return 'Wasooli $no';
  }

  @override
  String entryPaymentTitle(String no) {
    return 'Adaygi $no';
  }

  @override
  String get entryDate => 'Tareekh';

  @override
  String get entryHow => 'Kis tarah';

  @override
  String get entryAccount => 'Kis account mein';

  @override
  String get entryFrom => 'Kis se mile';

  @override
  String get entryTo => 'Kis ko diye';

  @override
  String get entryReference => 'Reference ya note';

  @override
  String get entryEnteredBy => 'Kis ne likha';

  @override
  String get entrySettled => 'Yeh bill is se chuke';

  @override
  String get entryShare => 'Raseed bhejein (PDF)';

  @override
  String get entryCancel => 'Mansookh karein';

  @override
  String get entryCancelTitle => 'Yeh entry mansookh karein';

  @override
  String get entryCancelExplain =>
      'Kuch mit-ta nahi. Ulta ijraa aaj ki tareekh se likha jayega, asal entry \'mansookh\' ke nishan ke sath hisaab mein rahegi, aur jo bill is se chuke thay woh dobara baqi ho jayenge.';

  @override
  String get entryCancelled => 'Mansookh';

  @override
  String entryCancelledWhy(String reason) {
    return 'Mansookh: $reason';
  }

  @override
  String entryReplaces(String no) {
    return '$no ki jagah likhi gayi';
  }

  @override
  String entryReplacedBy(String no) {
    return 'Is ki jagah ab $no hai';
  }

  @override
  String entryTakenWithBill(String no) {
    return 'Yeh paisay bill $no ke sath counter par liye gaye thay, is liye bill ke sath hi jayenge. Bill khol kar wapsi ya mansookhi karein.';
  }

  @override
  String get entryChequeAtBank =>
      'Cheque bank mein hai. Clear ya bounce hone ka intezar karein aur Cheque screen par darj karein.';

  @override
  String get entryChequeCleared =>
      'Cheque clear ho chuka, paisay bank mein hain, is liye ab mansookh nahi ho sakta.';

  @override
  String get entryChequeBounced =>
      'Cheque bounce ho chuka. Jo is ne chukaya tha woh pehle hi wapas khate mein hai.';

  @override
  String get entryNotAllowed =>
      'Isay sirf malik, manager ya accountant badal ya mansookh kar sakte hain.';

  @override
  String get entryOpenBill => 'Bill kholein';

  @override
  String entryEditTitle(String no) {
    return '$no theek karein';
  }

  @override
  String get entryEditExplain =>
      'Purani entry mansookh hogi aur theek wali aaj ki tareekh se likhi jayegi. Dono hisaab mein rahengi.';

  @override
  String get entryEditReason => 'Kya galat tha (marzi se)';

  @override
  String get entryEditReasonDefault => 'Galat likha gaya tha';

  @override
  String get entryEditSave => 'Tabdeeli save karein';

  @override
  String entryEditSaved(String no, String newNo) {
    return '$no theek ho gaya, ab $newNo';
  }

  @override
  String entryPaidBy(String nos) {
    return 'Is par $nos ki adaygi ho chuki hai. Pehle woh khol kar mansookh karein.';
  }

  @override
  String chargeEntryHint(String amount) {
    return '$amount ka charge. Raqam ya wajah galat hai to theek karein; ghalti se dala tha to wapas lein.';
  }

  @override
  String get openingTitle => 'Purana baqaya theek karein';

  @override
  String get openingNow => 'Abhi likha hai';

  @override
  String get openingNew => 'Sahi purana baqaya';

  @override
  String get openingExplain =>
      'Purana ijraa ulta ho kar sahi raqam ka naya likha jayega. Khate ki shuruat ka baqaya isi se badlega.';

  @override
  String get openingCorrect => 'Theek karein';

  @override
  String get openingSaved => 'Purana baqaya theek ho gaya';

  @override
  String get reasonPick => 'Wajah chunein';

  @override
  String get reasonWrongEntry => 'Galat entry';

  @override
  String get reasonDuplicate => 'Do baar likh di';

  @override
  String get reasonWrongAmount => 'Galat raqam';

  @override
  String get reasonDispute => 'Gahak ka ikhtilaf';

  @override
  String get reasonOther => 'Kuch aur';

  @override
  String get reasonDetail => 'Tafseel (marzi se)';

  @override
  String entryCancelledBy(String name, String when) {
    return '$name ne $when ko mansookh kiya';
  }

  @override
  String get salesSearch => 'Bill talash karein';

  @override
  String get salesSearchHint => 'Bill number, naam, phone ya raqam';

  @override
  String get salesClearSearch => 'Talash saaf karein';

  @override
  String get salesPeriodAll => 'Sab din';

  @override
  String get salesPeriodToday => 'Aaj';

  @override
  String get salesPeriodWeek => 'Is hafte';

  @override
  String get salesPeriodMonth => 'Is mahine';

  @override
  String get salesPeriodLastMonth => 'Pichhle mahine';

  @override
  String get salesPeriodPick => 'Tareekhen chunein';

  @override
  String salesPeriodRange(String from, String to) {
    return '$from se $to';
  }

  @override
  String get salesStandingAll => 'Sab bill';

  @override
  String get salesStandingPaid => 'Ada ho chuke';

  @override
  String get salesStandingUdhaar => 'Udhaar wale';

  @override
  String get salesStandingCancelled => 'Mansookh kiye';

  @override
  String get salesNoneFound => 'Is talash par koi bill nahi';

  @override
  String get salesNoneFoundHint =>
      'Doosra naam, number ya tareekh aazma kar dekhein';

  @override
  String get salesClearFilters => 'Sab bill dikhayein';

  @override
  String get sendAction => 'Bhejein';

  @override
  String sendTitle(String docNo) {
    return 'Bhejein: $docNo';
  }

  @override
  String get sendWalkIn => 'Aam gahak, koi number nahi';

  @override
  String get sendWhatsApp => 'WhatsApp par bhejein';

  @override
  String get sendWhatsAppShort => 'WhatsApp';

  @override
  String sendWhatsAppTo(String name) {
    return '$name ki chat khulegi, bill ki tafseel likhi hui';
  }

  @override
  String get sendWhatsAppNoNumber =>
      'Number nahi hai, PDF share sheet se jayegi';

  @override
  String get sendNoNumber =>
      'Is gahak ka WhatsApp number nahi, PDF share sheet se bheji';

  @override
  String get sendNoWhatsApp =>
      'Is phone par WhatsApp nahi mila, PDF share sheet se bheji';

  @override
  String get sendPdfHint => 'File, saath mein bill ki tafseel';

  @override
  String get sendPicture => 'Tasveer bhejein';

  @override
  String get sendPictureShort => 'Tasveer';

  @override
  String get sendPictureHint => 'Bill ki tasveer, chat mein seedha khulti hai';

  @override
  String get sendPrintHint => 'Is counter ke printer par';

  @override
  String get documentView => 'Poora dekhein';

  @override
  String get purchaseSendBack => 'Maal wapas karein';

  @override
  String get reportGroupTransaction => 'Len den';

  @override
  String get reportGroupParty => 'Party ki report';

  @override
  String get reportGroupItemStock => 'Cheezen aur stock';

  @override
  String get reportGroupBusiness => 'Karobar ki halat';

  @override
  String get reportGroupTaxes => 'Tax';

  @override
  String get reportGroupExpense => 'Kharchay';

  @override
  String get reportGroupOrders => 'Bikri aur khareed ke order';

  @override
  String get reportGroupLoans => 'Qarz ke khate';

  @override
  String get reportFavourites => 'Pasandeeda';

  @override
  String get reportRecent => 'Haal hi mein khole';

  @override
  String get reportSearchHint => 'Report ka naam likhein';

  @override
  String get reportSearchNone => 'Is naam ki koi report nahi';

  @override
  String get reportStar => 'Pasandeeda mein daalein';

  @override
  String get reportUnstar => 'Pasandeeda se hatayein';

  @override
  String get reportSale => 'Bikri report';

  @override
  String get reportSaleHint =>
      'Har bill: kul, kitna mila, kitna baqi, kaise diya';

  @override
  String get reportPurchase => 'Khareed report';

  @override
  String get reportPurchaseHint =>
      'Har khareed ka bill: kul, kitna diya, kitna baqi';

  @override
  String get reportAllTransactions => 'Tamam len den';

  @override
  String get reportAllTransactionsHint =>
      'Har bill, wapsi, kharcha aur payment, ek jagah';

  @override
  String get reportBillWiseProfit => 'Bill-war nafa';

  @override
  String get reportBillWiseProfitHint =>
      'Har bill par laagat se upar kitna kamaya';

  @override
  String get reportCashflow => 'Cash flow';

  @override
  String get reportCashflowHint =>
      'Galle aur bank mein paisa kahan se aaya, kahan gaya';

  @override
  String get reportPartyStatement => 'Party ka statement';

  @override
  String get reportPartyStatementHint =>
      'Ek party ka poora hisaab, har entry ke baad baqi';

  @override
  String get reportPartyProfit => 'Party-war nafa nuqsan';

  @override
  String get reportPartyProfitHint => 'Kis gahak se kitna nafa hua';

  @override
  String get reportAllParties => 'Tamam parties';

  @override
  String get reportAllPartiesHint =>
      'Har party ka lena, dena aur udhaar ki hadd';

  @override
  String get reportPartyItems => 'Party ki cheezen';

  @override
  String get reportPartyItemsHint => 'Party ne kaunsi cheez kitni li ya di';

  @override
  String get reportSalePurchaseByParty => 'Party-war bikri aur khareed';

  @override
  String get reportSalePurchaseByPartyHint =>
      'Har party ko kitna becha, us se kitna khareeda';

  @override
  String get reportSalePurchaseByGroup => 'Group-war bikri aur khareed';

  @override
  String get reportSalePurchaseByGroupHint =>
      'Har party group ki bikri aur khareed';

  @override
  String get reportYesterday => 'Kal';

  @override
  String get reportThisWeek => 'Is hafta';

  @override
  String get reportThisQuarter => 'Yeh teen mahine';

  @override
  String get reportLastYear => 'Pichla saal';

  @override
  String get reportCustom => 'Apni tareekhen';

  @override
  String get reportFilterParty => 'Party';

  @override
  String get reportFilterItem => 'Cheez';

  @override
  String get reportFilterCategory => 'Cheez ki qisam';

  @override
  String get reportFilterGroup => 'Party group';

  @override
  String get reportFilterType => 'Len den ki qisam';

  @override
  String get reportFilterMode => 'Kaise diya';

  @override
  String get reportFilterUser => 'Kis ne likha';

  @override
  String get reportFilterStatus => 'Adaigi';

  @override
  String get reportFilterWithBalance => 'Sirf jin ka baqi hai';

  @override
  String get reportFilterClear => 'Hatayein';

  @override
  String get reportFilterNothing => 'Kuch nahi mila';

  @override
  String get reportFilterUngrouped => 'Bina group';

  @override
  String get reportStatusPaid => 'Poora mila';

  @override
  String get reportStatusPartial => 'Kuch mila';

  @override
  String get reportStatusUnpaid => 'Kuch nahi mila';

  @override
  String get reportTypeSale => 'Bikri';

  @override
  String get reportTypeSaleReturn => 'Bikri ki wapsi';

  @override
  String get reportTypePurchase => 'Khareed';

  @override
  String get reportTypePurchaseReturn => 'Khareed ki wapsi';

  @override
  String get reportTypeExpense => 'Kharcha';

  @override
  String get reportTypeCharge => 'Charge ya doosri aamdani';

  @override
  String get reportTypeQuotation => 'Quotation';

  @override
  String get reportTypeChallan => 'Challan';

  @override
  String get reportTypeSaleOrder => 'Bikri ka order';

  @override
  String get reportTypePurchaseOrder => 'Khareed ka order';

  @override
  String get reportTypeProforma => 'Proforma';

  @override
  String get reportTypePaymentIn => 'Paisay aaye';

  @override
  String get reportTypePaymentOut => 'Paisay diye';

  @override
  String get reportShareExcel => 'Excel bhejein';

  @override
  String reportShowMore(int shown, int total) {
    return 'Aur dikhayein ($shown / $total)';
  }

  @override
  String get reportChooseParty => 'Statement dekhne ke liye party chunein';

  @override
  String reportVsPrevious(String change) {
    return '$change pichli dafa se';
  }

  @override
  String reportSortedBy(String column) {
    return '$column se tarteeb';
  }

  @override
  String get reportExcel => 'Excel';

  @override
  String get reportCsv => 'CSV';

  @override
  String get reportPrint => 'Print';

  @override
  String get reportPrintTitle => 'Printer par chhapein';

  @override
  String get loansTitle => 'Qarzay';

  @override
  String get loansNew => 'Naya qarza';

  @override
  String get loansEmpty => 'Koi qarza nahi';

  @override
  String get loansEmptyHint =>
      'Bank, committee, rishtedar ya supplier se liya qarza yahan likhein. Har qist mein asal aur sood alag likha jaye ga.';

  @override
  String get loansTotalOwed => 'Kul baqi qarza';

  @override
  String get loanOwed => 'Baqi';

  @override
  String loanOf(String amount) {
    return '$amount mein se';
  }

  @override
  String loanTakenOn(String date) {
    return 'Liya: $date';
  }

  @override
  String get loanCancelled => 'Cancel ho gaya';

  @override
  String get loanLender => 'Kis se liya (bank, committee, rishtedar)';

  @override
  String get loanAmount => 'Qarze ki raqam';

  @override
  String get loanInto => 'Paisay kahan aaye';

  @override
  String loanDate(String date) {
    return 'Tareekh: $date';
  }

  @override
  String get loanPickDate => 'Tareekh badlein';

  @override
  String get loanRate => 'Sood (markup), % saalana (marzi se)';

  @override
  String get loanTerm => 'Kitne mahine mein wapis (marzi se)';

  @override
  String get loanInstalment => 'Mahana qist (marzi se)';

  @override
  String get loanFee => 'Processing fee (marzi se)';

  @override
  String loanReceivedAfterFee(String amount) {
    return 'Fee ke baad haath mein: $amount';
  }

  @override
  String get loanNotes => 'Note (marzi se)';

  @override
  String get loanSave => 'Qarza save karein';

  @override
  String get loanSaved => 'Qarza save ho gaya';

  @override
  String get loanRepay => 'Qist dein';

  @override
  String get loanPaid => 'Kitne diye';

  @override
  String get loanInterest => 'Is mein sood (markup)';

  @override
  String get loanCharges => 'Charges ya jurmana (marzi se)';

  @override
  String get loanFrom => 'Kahan se diye';

  @override
  String get loanPrincipalLine => 'Qarze mein se kam';

  @override
  String get loanAfterLine => 'Is ke baad baqi';

  @override
  String get loanRepaySave => 'Qist save karein';

  @override
  String loanRepaid(String entryNo) {
    return 'Qist $entryNo save ho gayi';
  }

  @override
  String loanInterestSuggested(String rate) {
    return 'Sood $rate saalana ke hisaab se lagaya hai. Bank ki parchi se theek kar lein.';
  }

  @override
  String get loanSharePdf => 'Statement (PDF)';

  @override
  String get loanShareCsv => 'Statement (Excel, CSV)';

  @override
  String get loanOpening => 'Shuru mein baqi';

  @override
  String get loanClosing => 'Aakhir mein baqi';

  @override
  String get loanKindReceived => 'Qarza mila';

  @override
  String get loanKindRepaid => 'Qist di';

  @override
  String get loanKindCancelled => 'Cancel kiya';

  @override
  String get loanColBorrowed => 'Mila';

  @override
  String get loanColPrincipal => 'Asal';

  @override
  String get loanColInterest => 'Sood';

  @override
  String get loanColCharges => 'Fee, charges';

  @override
  String get loanCancelEntry => 'Ghalat hai, cancel karein';

  @override
  String get loanCancelReason => 'Kyun cancel kar rahe hain (zaroori)';

  @override
  String loanCancelDone(String entryNo) {
    return 'Cancel ho gaya ($entryNo)';
  }

  @override
  String loanRateShown(String rate) {
    return '$rate saalana';
  }

  @override
  String loanInstalmentShown(String amount) {
    return 'Qist $amount';
  }

  @override
  String get loanAmountInvalid => 'Raqam theek likhein, jaise 25000 ya 2500.50';

  @override
  String get posBillTo => 'Bill kis ke naam';

  @override
  String posCartEmptyFor(String name) {
    return '$name ka bill abhi khali hai';
  }

  @override
  String get looseTitle => 'Khula maal';

  @override
  String get looseHint =>
      'Cheez banaye baghair bechein. Maal ki list mein kuch save nahi hoga aur stock nahi hile ga.';

  @override
  String get looseName => 'Kya hai (marzi se)';

  @override
  String get looseNameHint => 'Maslan: pyaz';

  @override
  String get looseRate => 'Qeemat (fi unit, ya poori raqam)';

  @override
  String looseAmount(String amount) {
    return 'Raqam: $amount';
  }

  @override
  String get looseAdd => 'Bill mein daalein';

  @override
  String get looseNoCost =>
      'Is ki laagat maloom nahi, is liye munafe mein yeh poori raqam munafa gini jaye gi.';

  @override
  String get looseNeedsPrice => 'Tadaad aur qeemat likhein';

  @override
  String get looseFbrRefused =>
      'Yeh dukaan FBR ko bill bhejti hai, aur FBR ko har line ka HS code chahiye. Khula maal ki jagah is ki cheez bana kar bechein.';

  @override
  String get looseNotKept =>
      'Khula maal quotation ya challan par nahi ja sakta. Is ki cheez banayein, ya abhi bill banayein.';

  @override
  String looseOffer(String name) {
    return '\'$name\' khula bechein (cheez nahi banegi)';
  }

  @override
  String get looseBadge => 'Khula maal · stock nahi';

  @override
  String get dealsSoldTitle => 'Is gahak ko pichhli dafa';

  @override
  String get dealsBoughtTitle => 'Is supplier se pichhli khareed';

  @override
  String get dealsTapHint =>
      'Kisi par tap karein to wohi qeemat is line par lag jaye gi.';

  @override
  String dealLastTime(String price, String date) {
    return 'Pichhli dafa $price · $date';
  }

  @override
  String dealOtherUnit(String unit) {
    return 'Yeh qeemat $unit ki hai. Pehle line ko $unit mein karein.';
  }

  @override
  String dealUse(String price) {
    return 'Yeh qeemat lagayein: $price';
  }

  @override
  String dealLastBought(String price, String supplier, String date) {
    return 'Aakhri khareed $price · $supplier · $date';
  }

  @override
  String posBillFor(String name) {
    return '$name ka bill';
  }

  @override
  String get partyGroup => 'Group (marzi se)';

  @override
  String get partyGroupHint => 'Mohalla, route ya qisam';

  @override
  String get partyRemarks => 'Counter ke liye note';

  @override
  String get partyRemarksHint => 'Jaise: Sirf cash — cheque bounce ho chuka';

  @override
  String get groupsTitle => 'Group';

  @override
  String get groupsEmpty => 'Abhi koi group nahi';

  @override
  String get groupsEmptyHint =>
      'Gahak ke form mein group likhein — mohalla, route ya qisam — ya list mein kai gahak chun kar ek saath group lagayein';

  @override
  String get groupAll => 'Sab';

  @override
  String get groupNone => 'Baghair group';

  @override
  String groupMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log',
      one: '1 shakhs',
    );
    return '$_temp0';
  }

  @override
  String get groupReceivable => 'Lene hain';

  @override
  String get groupPayable => 'Dene hain';

  @override
  String get groupRename => 'Naam badlein';

  @override
  String get groupNewName => 'Naya naam';

  @override
  String groupRenameMerges(String name) {
    return '\'$name\' pehle se hai — dono group ek ho jayenge';
  }

  @override
  String get groupMerge => 'Doosre group mein milayein';

  @override
  String get groupMergeInto => 'Kis group mein milana hai?';

  @override
  String groupMergeConfirm(String from, String to) {
    return '\'$from\' ke sab log \'$to\' mein chale jayenge, aur \'$from\' khatam ho jayega.';
  }

  @override
  String get groupNoOther => 'Milane ke liye koi doosra group nahi';

  @override
  String groupMoved(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log \'$name\' mein',
      one: '1 shakhs \'$name\' mein',
    );
    return '$_temp0';
  }

  @override
  String groupCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log group se bahar',
      one: '1 shakhs group se bahar',
    );
    return '$_temp0';
  }

  @override
  String get groupSet => 'Group lagayein';

  @override
  String groupSetFor(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gahak ka group',
      one: '1 gahak ka group',
    );
    return '$_temp0';
  }

  @override
  String get groupClear => 'Group se nikalein';

  @override
  String get groupMembersTitle => 'Is group ke log';

  @override
  String get groupNobody => 'Is group mein koi nahi';

  @override
  String get partiesSelect => 'Kai gahak chunein';

  @override
  String partiesSelected(int count) {
    return '$count chune';
  }

  @override
  String get partiesSort => 'Tarteeb';

  @override
  String get partiesSortName => 'Naam se';

  @override
  String get partiesSortBalance => 'Zyada udhaar pehle';

  @override
  String get partiesSortOldest => 'Sab se purana udhaar pehle';

  @override
  String partiesCapped(int count) {
    return 'Pehle $count dikhaye — baqi talash se dhoondein';
  }

  @override
  String get importFromWhere => 'Yeh file kahan se aayi hai?';

  @override
  String get importSourceOurs => 'Bazaar Ledger ki list';

  @override
  String get importSourceVyaparItems => 'Vyapar ka maal';

  @override
  String get importSourceVyaparParties => 'Vyapar ki parties';

  @override
  String get importSourceKhatabook => 'Khatabook';

  @override
  String get importSourceOther => 'Koi aur';

  @override
  String importRecognised(String source) {
    return 'Pehchaan liya: $source';
  }

  @override
  String get importGuideTitle => 'Yeh file kaise nikalein';

  @override
  String importGuideOurs(String headings) {
    return 'Pehli line mein yeh naam likhein: $headings. Phir har line par ek cheez, ya ek customer.';
  }

  @override
  String get importGuideVyaparItems =>
      '1. Jis computer ya phone par dukaan ka Vyapar hai, us par Vyapar kholein.\n2. Menu se Utilities, phir Export Items kholein aur Excel mein save karein.\n3. File is phone par bhejein (apne aap ko WhatsApp karein, ya cable se) aur neeche chunein.\nVyapar ki Import Items wali bhari hui sheet bhi isi tarah aa jati hai.';

  @override
  String get importGuideVyaparParties =>
      '1. Vyapar mein Reports, phir Party Reports, phir All Parties kholein.\n2. Oopar Excel ka button dabayein aur file save karein.\n3. File is phone par bhejein aur neeche chunein.\nHar baqaya apni taraf aata hai: To Receive woh hai jo customer ne aap ko dena hai.';

  @override
  String get importGuideKhatabook =>
      '1. Khatabook ki phone app report PDF mein deti hai, aur PDF parhi nahin ja sakti. Agar aap ka Khatabook, computer ya web par, customers ki list Excel ya CSV mein deta hai to woh download karein.\n2. Agar sirf PDF milti hai to ek sheet banayein jis mein Name, Phone, You will get, You will give likha ho, aur baqaya us mein likh dein.\n3. File is phone par bhejein aur neeche chunein.';

  @override
  String get importGuideOther =>
      'Koi bhi .xlsx, .xls ya .csv jis ki pehli line mein columns ke naam hon. Jo naam app na pehchane, use Columns mein khud chun lein.';

  @override
  String get importReading => 'File parhi ja rahi hai…';

  @override
  String get importChecking =>
      'Dukaan mein pehle se maujood cheezon se mila rahe hain…';

  @override
  String get importColumnsTitle => 'Columns';

  @override
  String get importColumnsHint =>
      'Agar koi column ghalat parha gaya ho to sahi chunein.';

  @override
  String get importColumnNone => 'Is file mein nahin';

  @override
  String importColumnLetter(String letter) {
    return 'Column $letter';
  }

  @override
  String get importFieldName => 'Naam';

  @override
  String get importFieldSalePrice => 'Bechne ki qeemat';

  @override
  String get importFieldPurchasePrice => 'Khareed ki qeemat';

  @override
  String get importFieldWholesalePrice => 'Thok ki qeemat';

  @override
  String get importFieldMrp => 'MRP';

  @override
  String get importFieldStock => 'Maujooda stock';

  @override
  String get importFieldMinStock => 'Kam az kam stock';

  @override
  String get importFieldUnit => 'Unit';

  @override
  String get importFieldSecondaryUnit => 'Doosra unit';

  @override
  String get importFieldConversion => 'Ek mein doosre unit kitne';

  @override
  String get importFieldCode => 'Code';

  @override
  String get importFieldBarcode => 'Barcode';

  @override
  String get importFieldCategory => 'Qism';

  @override
  String get importFieldDescription => 'Tafseel';

  @override
  String get importFieldHsCode => 'HS / PCT code';

  @override
  String get importFieldItemType => 'Maal ya service';

  @override
  String get importFieldHsn => 'HSN (India ka, nahin rakha jata)';

  @override
  String get importFieldTax => 'Tax rate (nahin parha jata)';

  @override
  String get importFieldPhone => 'Phone';

  @override
  String get importFieldBalance => 'Baqaya';

  @override
  String get importFieldReceivable => 'Unhon ne aap ko dena hai';

  @override
  String get importFieldPayable => 'Aap ne unhein dena hai';

  @override
  String get importFieldBalanceType => 'Lena ya dena';

  @override
  String get importFieldType => 'Customer ya supplier';

  @override
  String get importFieldCity => 'Shehar';

  @override
  String get importFieldAddress => 'Pata';

  @override
  String get importFieldCreditLimit => 'Udhaar ki hadd';

  @override
  String get importFieldGstin => 'GSTIN (India ka, nahin rakha jata)';

  @override
  String importNoteGst(String count, String rates) {
    return '$count cheezon par India ka GST rate tha ($rates). GST Pakistan ka sales tax nahin, is liye koi rate nahin liya gaya: har cheez par dukaan ka aam tax lagega, jaise haath se daali cheez par.';
  }

  @override
  String importNoteTax(String count) {
    return '$count cheezon par tax rate tha. Woh nahin parha gaya: har cheez par dukaan ka aam tax lagega, jaise haath se daali cheez par.';
  }

  @override
  String importNoteHsn(String count) {
    return '$count cheezon ka HSN code tha. Woh India ka hai; Pakistan ka PCT code hota hai, is liye nahin rakha gaya. FBR ko report hone wali cheezon mein PCT code daalein.';
  }

  @override
  String importNoteGstin(String count) {
    return '$count parties ka GSTIN tha. Woh India ka tax number hai, NTN nahin, is liye nahin rakha gaya.';
  }

  @override
  String get importNoteRupee =>
      'Raqam par ₹ ka nishaan tha, jaise Vyapar likhta hai. Inhein aap ke rupay hi samjha gaya hai.';

  @override
  String importNoteColumns(String columns) {
    return 'Nahin rakhe gaye: $columns';
  }

  @override
  String importNoteServices(String count) {
    return '$count services ka stock nahin gina jata.';
  }

  @override
  String importUnknownUnit(String count, String unit) {
    return '$count cheezein \"$unit\" mein hain, jo is dukaan ka unit nahin: yeh adad mein rakhi jayengi, qeemat aur stock file jaise.';
  }

  @override
  String importSecondUnit(String count, String unit) {
    return '$count cheezon ka doosra unit hai ($unit): yeh sirf pehle unit mein rakhi jayengi.';
  }

  @override
  String importBalancesOwed(String count, String amount) {
    return '$count ne aap ko $amount dene hain';
  }

  @override
  String importBalancesAhead(String count, String amount) {
    return '$count ne pehle se diye: aap ke paas un ke $amount hain';
  }

  @override
  String importBalancesSuppliers(String count, String amount) {
    return '$count suppliers jin ko aap ne $amount dene hain: yeh baqaya nahin laaya gaya. Har ek ka purchase bill darj karein.';
  }

  @override
  String importOwedQuestion(String count) {
    return '$count jin ko aap ne dena hai, aur file nahin batati ke woh kaun hain. Woh hain:';
  }

  @override
  String get importOwedSuppliers => 'Suppliers';

  @override
  String get importOwedCustomers => 'Pehle se paise de chuke customers';

  @override
  String importDuplicates(String count) {
    return '$count pehle se dukaan mein hain';
  }

  @override
  String get importDuplicatesSkip => 'Jaise hain rehne dein';

  @override
  String get importDuplicatesUpdate => 'File se naya karein';

  @override
  String get importDuplicatesItemsHint =>
      'Qeemat file se aayegi; code ya barcode sirf wahan jahan pehle nahin. Shelf ka stock nahin badlega.';

  @override
  String get importDuplicatesPartiesHint =>
      'Phone, pata aur udhaar ki hadd sirf khaali jagah bhari jayegi. Baqaya nahin badlega.';

  @override
  String importPartial(String count) {
    return '$count kuch chhor kar aayenge';
  }

  @override
  String importMore(String count) {
    return 'aur $count';
  }

  @override
  String importLine(String line, String reason) {
    return 'Line $line: $reason';
  }

  @override
  String get importIssueNoName => 'naam nahin';

  @override
  String importIssueTwice(String name) {
    return '$name file mein do dafa hai';
  }

  @override
  String get importIssueTotal =>
      'yeh total ki line hai, koi cheez ya party nahin';

  @override
  String importIssueNoPrice(String name) {
    return '$name ki bechne ki qeemat nahin';
  }

  @override
  String importIssueNotPrice(String name, String value) {
    return '$name: \"$value\" qeemat nahin';
  }

  @override
  String importIssueNotQty(String name, String value) {
    return '$name: \"$value\" stock ki tadaad nahin';
  }

  @override
  String importIssueNotAmount(String name, String value) {
    return '$name: \"$value\" raqam nahin';
  }

  @override
  String importIssueNegativeStock(String name, String value) {
    return '$name baghair stock ke aayega; file mein $value likha hai';
  }

  @override
  String importIssueBarcode(String name, String value) {
    return '$name baghair barcode ke aayega; Excel ne use $value bana diya';
  }

  @override
  String importIssueSupplierOwed(String name, String value) {
    return '$name supplier ban kar aayega, aap ke dene wale Rs $value ke baghair: yeh purchase bill mein darj karein';
  }

  @override
  String importIssueSupplierOwes(String name, String value) {
    return '$name supplier ban kar aayega, un ke dene wale Rs $value ke baghair';
  }

  @override
  String importIssueAlreadyItem(String name) {
    return '$name pehle se maal mein hai';
  }

  @override
  String importIssueAlreadyItemAs(String name, String value) {
    return '$name pehle se maal mein hai, $value ke naam se';
  }

  @override
  String importIssueAlreadyParty(String name) {
    return '$name pehle se khate mein hai';
  }

  @override
  String importIssueAlreadyPartyAs(String name, String value) {
    return '$name pehle se khate mein hai, $value ke naam se';
  }

  @override
  String importIssueOther(String name, String value) {
    return '$name: $value';
  }

  @override
  String importProgress(String total, String done) {
    return '$total mein se $done aa rahe hain…';
  }

  @override
  String importUpdated(String count) {
    return '$count naye kiye gaye';
  }

  @override
  String get importRefusedUnreadable =>
      'Yeh file sheet ki tarah parhi nahin ja saki. Ise Excel ya Google Sheets mein khol kar .xlsx ya .csv mein save karein, phir woh chunein.';

  @override
  String get importRefusedOld =>
      'Yeh .xls Excel 95 ya us se purani hai. Ise .xlsx mein dobara save kar ke chunein.';

  @override
  String get importRefusedPassword =>
      'Is workbook par password hai. Excel mein password hata kar save karein aur dobara chunein.';

  @override
  String get importNeedItemColumns =>
      'Naam aur bechne ki qeemat ke columns nahin mile. Neeche Columns mein chunein.';

  @override
  String get importNeedPartyColumns =>
      'Naam ka column nahin mila. Neeche Columns mein chunein.';

  @override
  String get reportStockSummary => 'Stock ka khulasa';

  @override
  String get reportStockSummaryHint =>
      'Har cheez ka stock, qeemat aur maaliyat, kisi bhi din ki';

  @override
  String get reportItemByParty => 'Cheez ki party-war report';

  @override
  String get reportItemByPartyHint => 'Yeh cheez kis ne khareedi aur kis ne di';

  @override
  String get reportItemProfit => 'Cheez-war nafa nuqsan';

  @override
  String get reportItemProfitHint => 'Har cheez ne laagat se kitna kamaya';

  @override
  String get reportCategoryProfit => 'Category-war nafa nuqsan';

  @override
  String get reportCategoryProfitHint => 'Har category ka nafa';

  @override
  String get reportLowStock => 'Kam stock';

  @override
  String get reportLowStockHint =>
      'Kya khatam ho raha hai aur kitna mangwana hai';

  @override
  String get reportItemDetail => 'Cheez ki tafseel';

  @override
  String get reportItemDetailHint => 'Ek cheez ka stock, din ba din';

  @override
  String get reportStockDetail => 'Stock ki tafseel';

  @override
  String get reportStockDetailHint =>
      'Har cheez ka shuru ka stock, aamad, kharch aur akhir';

  @override
  String get reportSalePurchaseByCategory => 'Category-war bikri aur khareed';

  @override
  String get reportSalePurchaseByCategoryHint =>
      'Har category kitni biki aur kitni aayi';

  @override
  String get reportStockByCategory => 'Category-war stock';

  @override
  String get reportStockByCategoryHint => 'Har category ka stock aur maaliyat';

  @override
  String get reportBatches => 'Batch report';

  @override
  String get reportBatchesHint => 'Shelf par har batch, expiry ke saath';

  @override
  String get reportSerials => 'Serial aur IMEI report';

  @override
  String get reportSerialsHint =>
      'Har numbered cheez: mojood, biki ya wapas gayi';

  @override
  String get reportItemDiscount => 'Cheez-war discount';

  @override
  String get reportItemDiscountHint => 'Har cheez ki qeemat se kitna kam kiya';

  @override
  String get reportStockTransfers => 'Maal ki muntaqili';

  @override
  String get reportStockTransfersHint =>
      'Dukaan, godown aur van ke darmiyan maal';

  @override
  String get reportProduction => 'Production register';

  @override
  String get reportProductionHint => 'Har production: kya laga aur kitne ka';

  @override
  String get reportFastSlow => 'Tez, sust aur band maal';

  @override
  String get reportFastSlowHint =>
      'Kya bikta hai, kya nahi, aur kitna paisa phansa hai';

  @override
  String get reportStockAgeing => 'Maal kitna purana';

  @override
  String get reportStockAgeingHint => 'Maal kab se shelf par para hai';

  @override
  String get reportFilterPlace => 'Jagah';

  @override
  String get reportFilterInStock => 'Sirf mojood maal';

  @override
  String get reportFilterAsOf => 'Is din tak';

  @override
  String get reportFilterSalesDays => 'Bikri kitne din ki';

  @override
  String get reportFilterCoverDays => 'Kitne din ka maal';

  @override
  String get reportFilterFastAt => 'Tez kitne bills se';

  @override
  String get reportFilterSlowBelow => 'Sust kitne bills se kam';

  @override
  String get reportFilterSerial => 'Serial ya IMEI';

  @override
  String get reportFilterSerialHint => 'Number, ya uske aakhri chand hindse';

  @override
  String reportFilterDaysValue(int days) {
    return '$days din';
  }

  @override
  String reportFilterBillsValue(int bills) {
    return '$bills bill';
  }

  @override
  String get copyTitle => 'Kaunsi copy?';

  @override
  String get copyOriginal => 'Asal';

  @override
  String get copyDuplicate => 'Duplicate';

  @override
  String get copyTriplicate => 'Triplicate';

  @override
  String get copyTransporter => 'Transporter';

  @override
  String get copyAutoHint =>
      'Na chunein to: pehli dafa asal, us ke baad duplicate';

  @override
  String get copyChosenHint => 'Kaghaz par yahi copy likhi chhapegi';

  @override
  String get copyTransporterHint =>
      'Maal, miqdar aur kis ke liye — koi qeemat nahi';

  @override
  String get copyOriginalGone => 'Asal copy pehle chhap chuki hai';

  @override
  String get transportTitle => 'Transport ki tafseel';

  @override
  String get transportHint =>
      'Bilty aur gaari ka number bill par chhapega. Paison mein kuch nahi badlega.';

  @override
  String get transportAdd => 'Transport ki tafseel likhein (bilty, gaari)';

  @override
  String get transportTransporter => 'Transporter / adda';

  @override
  String get transportVehicle => 'Gaari no';

  @override
  String get transportBilty => 'Bilty no';

  @override
  String get transportShipTo => 'Kahan bhejna hai';

  @override
  String get settingsBillDesign => 'Bill ka design';

  @override
  String get billDesignIntro =>
      'PDF bill ka andaaz: design, rang, logo aur payment QR. Thermal slip waisi hi rehti hai; us par sirf baqaya, neeche ki likhai aur QR ka faisla yahan hota hai.';

  @override
  String get billDesignLayout => 'Design';

  @override
  String get billThemeClassic => 'Saada';

  @override
  String get billThemeClassicHint =>
      'Beech mein dukan ka naam, saada kaghaz jaisa';

  @override
  String get billThemeModern => 'Rangeen patti';

  @override
  String get billThemeModernHint =>
      'Upar dukan ke rang ki patti par naam aur logo';

  @override
  String get billThemeCompact => 'Chhota';

  @override
  String get billThemeCompactHint =>
      'Chhoti likhai, lamba wholesale bill ek safhe par';

  @override
  String get billThemeTax => 'Sales tax invoice';

  @override
  String get billThemeTaxHint =>
      'FBR ke mutabiq: dono taraf ka NTN/STRN, har line par tax se pehle, tax ki sharah, tax aur tax samet qeemat';

  @override
  String get billDesignTaxNeedsNtn =>
      'Tax invoice ke liye Dukan ki tafseel mein apna NTN aur STRN likhein';

  @override
  String get billDesignColour => 'Rang';

  @override
  String get billAccentInk => 'Siyah';

  @override
  String get billAccentBlue => 'Neela';

  @override
  String get billAccentGreen => 'Hara';

  @override
  String get billAccentMaroon => 'Maroon';

  @override
  String get billAccentOrange => 'Narangi';

  @override
  String get billAccentPurple => 'Jamni';

  @override
  String get billDesignPage => 'Kaghaz ka size';

  @override
  String get billDesignPictures => 'Logo aur QR';

  @override
  String get billDesignLogo => 'Dukan ka logo';

  @override
  String get billDesignLogoHint => 'PDF bill ke upar chhapta hai';

  @override
  String get billDesignPaymentQr => 'Payment QR';

  @override
  String get billDesignPaymentQrHint =>
      'Aap ke bank, JazzCash ya Easypaisa ka apna QR — screenshot ya tasveer. PDF bill ke neeche chhapta hai.';

  @override
  String get billDesignQrOnThermal => 'QR thermal slip par bhi';

  @override
  String get billDesignQrOnThermalHint =>
      'Pehle ek slip chhap kar phone se scan kar ke dekh lein';

  @override
  String get billDesignKhata => 'Pichhla baqaya bill par';

  @override
  String get billDesignKhataHint =>
      'Udhaar wale gahak ke bill par: pichhla baqaya, is bill, kul baqaya. Purane bill ki copy par wahi hisaab chhapta hai jo bill ke din tha.';

  @override
  String get billDesignFooter => 'Bill ke neeche ki likhai';

  @override
  String get billDesignFooterLabel => 'Har line alag (zyada se zyada 4)';

  @override
  String get billDesignFooterHint =>
      'Shukriya, wapsi ki shart, kuch bhi — Urdu, Roman ya English';

  @override
  String get billDesignFooterPresets => 'Ek tap mein daalein';

  @override
  String get billDesignPreview => 'Kaisa dikhega';

  @override
  String get billDesignPreviewPdf => 'PDF';

  @override
  String get billDesignPreviewSlip => 'Thermal slip';

  @override
  String get billDesignPreviewNote =>
      'Yeh andaaz ka khaka hai. Asal PDF dekhne ke liye neeche wala button dabayein.';

  @override
  String get billDesignSamplePdf => 'Namoona PDF dekhein';

  @override
  String get billDesignSaved => 'Bill ka design mehfooz ho gaya';

  @override
  String get settingsTextSize => 'Likhai ka size';

  @override
  String get settingsTextSizeNormal => 'Aam';

  @override
  String get settingsTextSizeLarge => 'Bara';

  @override
  String get settingsTextSizeLarger => 'Aur bara';

  @override
  String get settingsTextSizeHint =>
      'Sirf is phone ki screen par. Bill, raseed aur PDF har size par aik jaise chhapte hain.';

  @override
  String itemStockLeft(String amount) {
    return '$amount mojood';
  }

  @override
  String get expenseWhose => 'Kis ka kharcha';

  @override
  String get expenseForShop => 'Dukaan ka kharcha';

  @override
  String get expenseForHome => 'Ghar ka kharcha';

  @override
  String get expenseHomeChip => 'Ghar';

  @override
  String get expenseHomeExplain =>
      'Ghar ka kharcha malik ka apna paisa hai jo dukaan se nikla. Yeh dukaan ka kharcha nahi, is liye munafa kam nahi karta; malik ka hissa kam karta hai.';

  @override
  String get expenseHomeGoodsLink => 'Dukaan ka maal ghar le gaye?';

  @override
  String get expenseRemind => 'Har mahine yaad dilayen';

  @override
  String get expenseRemindDay => 'Mahine ki tareekh';

  @override
  String get expenseRemindDayInvalid => 'Mahine ki tareekh 1 se 31 tak likhein';

  @override
  String get expenseMonthShop => 'Is mahine dukaan';

  @override
  String get expenseMonthHome => 'Is mahine ghar';

  @override
  String get expenseGoodsCancelOnly =>
      'Ghar le gaye maal ko badla nahi jata: mansookh kar ke dobara likhein.';

  @override
  String get expenseHomeNotAllowed =>
      'Ghar ka kharcha sirf malik ya accountant badal sakte hain.';

  @override
  String get billsTitle => 'Mahana bill';

  @override
  String get billsEmpty => 'Abhi koi mahana bill nahi';

  @override
  String get billsEmptyHint =>
      'Kiraya, bijli, tankhwah: aik dafa likhein, app us tareekh ko yaad dilayegi. Khud se kuch nahi diya jata.';

  @override
  String get billsNew => 'Naya mahana bill';

  @override
  String billDue(String name) {
    return 'Is mahine dena hai: $name';
  }

  @override
  String billDueOn(String date) {
    return '$date ko dena tha';
  }

  @override
  String get billPayNow => 'Abhi dein';

  @override
  String get billSkip => 'Is mahine nahi';

  @override
  String get billSkipped => 'Is mahine dobara yaad nahi dilaya jayega';

  @override
  String billEvery(String day) {
    return 'Har mahine $day tareekh ko';
  }

  @override
  String get billName => 'Kis cheez ka bill';

  @override
  String get billAmount => 'Aam taur par raqam';

  @override
  String get billSave => 'Bill save karein';

  @override
  String get monthlyBillSaved => 'Mahana bill save ho gaya';

  @override
  String get billDelete => 'Yaad dilana band karein';

  @override
  String get billDeleted => 'Yaad dilana band ho gaya';

  @override
  String get billPaidFrom => 'Aam taur par kahan se';

  @override
  String get headsTitle => 'Mad';

  @override
  String get headsExpense => 'Kharche ki mad';

  @override
  String get headsIncome => 'Aamdani ki mad';

  @override
  String get headsAddExpense => 'Kharche ki nayi mad';

  @override
  String get headsAddIncome => 'Aamdani ki nayi mad';

  @override
  String get headName => 'Naam';

  @override
  String get headDirect => 'Maal ki lagat (gross munafe se pehle)';

  @override
  String get headDirectChip => 'Direct';

  @override
  String get headIndirectChip => 'Indirect';

  @override
  String get headHidden => 'Chhupi hui';

  @override
  String get headHide => 'List se chhupayein';

  @override
  String get headSave => 'Save karein';

  @override
  String get headSaved => 'Save ho gaya';

  @override
  String get headDirectExplain =>
      'Maal ki lagat (aate maal ka kiraya) bikri se gross munafe se pehle kat-ti hai; baqi (kiraya, tankhwah, bijli) us ke baad. Badalne se har mahine ke munafa nuqsan mein yeh mad jagah badalti hai.';

  @override
  String get incomeTitle => 'Deegar aamdani';

  @override
  String get incomeEmpty => 'Abhi koi deegar aamdani nahi';

  @override
  String get incomeEmptyHint =>
      'Upar wale kamre ka kiraya, commission, bank ka munafa, raddi: jo paisa bikri ke ilawa aaya yahan likhein.';

  @override
  String get incomeNew => 'Nayi aamdani';

  @override
  String get incomeHead => 'Kis mad mein';

  @override
  String get incomeFrom => 'Kis se mila (marzi se)';

  @override
  String get incomeFromParty => 'Khate se chunein';

  @override
  String get incomeInto => 'Kahan aaya';

  @override
  String get incomeNote => 'Kis cheez ka (marzi se)';

  @override
  String get incomeSave => 'Aamdani save karein';

  @override
  String incomeSaved(String docNo) {
    return 'Aamdani $docNo save ho gayi';
  }

  @override
  String get incomeThisMonth => 'Is mahine';

  @override
  String get incomeNotASale =>
      'Yeh bikri nahi: munafa nuqsan mein deegar aamdani mein, gross munafe ke baad aati hai.';

  @override
  String get incomeHeadRent => 'Kiraya mila';

  @override
  String get incomeHeadCommission => 'Commission';

  @override
  String get incomeHeadInterest => 'Bank ka munafa';

  @override
  String get incomeHeadScrap => 'Raddi, khali dabbe';

  @override
  String get incomeHeadRefund => 'Refund mila';

  @override
  String get incomeHeadOther => 'Deegar';

  @override
  String get homeGoodsTitle => 'Ghar le gaye maal';

  @override
  String get homeGoodsExplain =>
      'Dukaan ke shelf se ghar ke liye maal. Lagat par nikalta hai, aur malik ke hisse se kat-ta hai, munafe se nahi.';

  @override
  String get homeGoodsSearch => 'Kaunsa maal';

  @override
  String get homeGoodsQty => 'Kitna';

  @override
  String homeGoodsOnHand(String qty) {
    return 'Shelf par $qty';
  }

  @override
  String get homeGoodsNote => 'Note (marzi se)';

  @override
  String get homeGoodsSave => 'Ghar le gaye, save karein';

  @override
  String homeGoodsSaved(String docNo, String amount) {
    return '$docNo: $amount ka maal ghar gaya';
  }

  @override
  String get homeGoodsPick => 'Pehle maal chunein';

  @override
  String get homeGoodsQtyInvalid => 'Kitna likhein, jaise 2 ya 1.5';

  @override
  String get reportDailySummary => 'Din ka khulasa (Z report)';

  @override
  String get reportDailySummaryHint =>
      'Aaj ki bikri, har tareeqe se aaya paisa, udhaar, kharchay aur galla';

  @override
  String get reportBankStatement => 'Bank statement';

  @override
  String get reportBankStatementHint =>
      'Har jama aur nikasi, har ek ke baad baqi';

  @override
  String get reportDiscount => 'Discount report';

  @override
  String get reportDiscountHint =>
      'Har party ko kitna discount diya, supplier se kitna mila';

  @override
  String get reportDiscountByCashier => 'Cashier-war discount';

  @override
  String get reportDiscountByCashierHint =>
      'Kaunsa cashier kitna discount deta hai';

  @override
  String get reportSalesByCashier => 'Cashier-war bikri';

  @override
  String get reportSalesByCashierHint =>
      'Har banday ke bill, bikri, discount, wapsi aur cancel';

  @override
  String get reportSalesByCounter => 'Counter-war bikri';

  @override
  String get reportSalesByCounterHint => 'Yehi, har phone ya counter ka';

  @override
  String get reportPaymentModes => 'Adaigi ke tareeqay';

  @override
  String get reportPaymentModesHint =>
      'Naqad, bank, JazzCash, Easypaisa, cheque aur udhaar, har ek alag';

  @override
  String get reportHourlySales => 'Ghanta-war bikri';

  @override
  String get reportHourlySalesHint =>
      'Din ke kis waqt sab se zyada rush hota hai';

  @override
  String get reportPaymentPerformance => 'Gahakon ki adaigi';

  @override
  String get reportPaymentPerformanceHint =>
      'Kaun kitne din mein deta hai, kaun der se deta hai';

  @override
  String get reportDefaulters => 'Defaulter list';

  @override
  String get reportDefaultersHint => 'Jin ka udhaar apni muddat se guzar gaya';

  @override
  String get reportChangedBills => 'Badle aur cancel bill';

  @override
  String get reportChangedBillsHint =>
      'Har cancel, wapsi aur tabdeeli: kis ne, kab aur kyun';

  @override
  String get reportTaxReport => 'Tax report';

  @override
  String get reportTaxReportHint =>
      'Bikri aur khareed par tax, party-war, NTN ke saath';

  @override
  String get reportTaxRate => 'Tax rate report';

  @override
  String get reportTaxRateHint =>
      'Rate-war tax: 18%, kam rate, exempt, zero, Third Schedule, further tax';

  @override
  String get reportSalesByHsCode => 'HS code-war bikri';

  @override
  String get reportSalesByHsCodeHint => 'Har HS code ke tehat kitna becha';

  @override
  String get reportAnnexC => 'Annex-C (bikri)';

  @override
  String get reportAnnexCHint =>
      'Har bikri FBR ke Annex-C ke khanon mein, accountant ke liye';

  @override
  String get reportAnnexA => 'Annex-A (khareed)';

  @override
  String get reportAnnexAHint => 'Har khareed FBR ke Annex-A ke khanon mein';

  @override
  String get reportExpenseTransactions => 'Kharchon ki fehrist';

  @override
  String get reportExpenseTransactionsHint =>
      'Har kharcha: kis mad mein, kahan se diya, kis liye';

  @override
  String get reportExpenseCategories => 'Kharchon ki mad';

  @override
  String get reportExpenseCategoriesHint =>
      'Har mad ka kul, direct aur indirect';

  @override
  String get reportExpenseItems => 'Kharchay kis cheez par';

  @override
  String get reportExpenseItemsHint => 'Har mad mein paisa kis cheez par gaya';

  @override
  String get reportOpenQuotations => 'Khuli quotations';

  @override
  String get reportOpenQuotationsHint =>
      'Jo quotations abhi bill nahi baneen, kitne din se';

  @override
  String get reportOpenChallans => 'Bina bill ke challan';

  @override
  String get reportOpenChallansHint =>
      'Challan par gaya maal jis ka bill abhi nahi bana';

  @override
  String get reportOpenOrderItems => 'Quotation aur challan ki cheezen';

  @override
  String get reportOpenOrderItemsHint =>
      'Khuli quotations aur challan par cheezen aur miqdar';

  @override
  String get reportFilterAccount => 'Bank ya wallet';

  @override
  String get reportFilterHead => 'Kharche ki mad';

  @override
  String get dayCloseSummary => 'Din ka khulasa dekhein (Z report)';

  @override
  String dueOn(String date) {
    return '$date tak';
  }

  @override
  String get dueToday => 'Aaj dena hai';

  @override
  String dueOverdue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days din der',
      one: '1 din der',
    );
    return '$_temp0';
  }

  @override
  String get dueNotYet => 'Abhi waqt hai';

  @override
  String khataCreditDays(int days) {
    return '$days din ka udhaar';
  }

  @override
  String khataCreditUsual(int days) {
    return 'Aam muddat, $days din';
  }

  @override
  String khataReturn(String no) {
    return 'Wapsi $no';
  }

  @override
  String get partyCreditDays => 'Udhaar kitne din ka (marzi se)';

  @override
  String partyCreditDaysHint(int days) {
    return 'Khaali chhorein to $days din. Badalne se khule billon ki aakhri tareekh bhi badlegi.';
  }

  @override
  String get partyCreditDaysInvalid => '0 se 365 din ke darmiyan likhein';

  @override
  String get promiseTitle => 'Adaygi ka wada';

  @override
  String get promiseRecord => 'Wada likhein';

  @override
  String get promiseNew => 'Naya wada';

  @override
  String get promiseNone =>
      'Kab dene ka kaha? \"Jumma ko de dunga\" yahan likhein, us din yaad aayega.';

  @override
  String get promiseWhen => 'Kab dene ka kaha?';

  @override
  String get promiseTomorrow => 'Kal';

  @override
  String get promiseFriday => 'Jumma';

  @override
  String get promiseNextWeek => 'Agle hafte';

  @override
  String get promiseSalaryDay => 'Tankhwah (1 tareekh)';

  @override
  String get promisePickDay => 'Din chunein';

  @override
  String get promiseAmount => 'Kitne ka kaha (marzi se)';

  @override
  String get promiseNote => 'Unhon ne kya kaha (marzi se)';

  @override
  String get promiseSave => 'Wada save karein';

  @override
  String promiseSaved(String date) {
    return 'Wada likh liya: $date';
  }

  @override
  String promiseFor(String date) {
    return '$date ka wada';
  }

  @override
  String promiseForAmount(String date, String amount) {
    return '$date ko Rs $amount ka wada';
  }

  @override
  String get promisePending => 'Intezar';

  @override
  String get promiseDueToday => 'Aaj ka wada';

  @override
  String get promiseKept => 'Pura hua';

  @override
  String get promiseBroken => 'Toot gaya';

  @override
  String get promiseReplaced => 'Naye wade se badla';

  @override
  String get promiseWithdrawnLabel => 'Hata diya';

  @override
  String get promiseWithdraw => 'Wada hatayein';

  @override
  String get promiseWithdrawn => 'Wada hata diya. Purane wadon mein rahega.';

  @override
  String get promiseHistory => 'Purane wade';

  @override
  String promiseBy(String name, String date) {
    return '$name ne $date ko likha';
  }

  @override
  String promisePaidSince(String amount) {
    return 'Tab se Rs $amount aaye';
  }

  @override
  String homeUdhaarDueToday(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gahakon ka udhaar aaj dena hai · Rs $amount',
      one: '1 gahak ka udhaar aaj dena hai · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String homeUdhaarOverdue(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gahak der se · Rs $amount',
      one: '1 gahak der se · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String homeUdhaarPromised(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gahakon ne aaj dene ka wada kiya · Rs $amount',
      one: '1 gahak ne aaj dene ka wada kiya · Rs $amount',
    );
    return '$_temp0';
  }

  @override
  String get chaseSortLate => 'Sab se der wale pehle';

  @override
  String get chaseSortPromise => 'Wade ki tareekh se';

  @override
  String get chaseFilterPromised => 'Wade wale';

  @override
  String get chaseFilterDueToday => 'Aaj dena hai';

  @override
  String get chaseFilterPromisedToday => 'Aaj ka wada';

  @override
  String get promiseToday => 'Aaj';

  @override
  String get chaseFilterOverdue => 'Der wale';

  @override
  String get khataRemindOff => 'Yaad-dehani band';

  @override
  String get remindedToday => 'Aaj yaad dilaya';

  @override
  String remindedDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days din pehle yaad dilaya',
      one: 'Kal yaad dilaya',
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
  String get reminderLangUrdu => 'اردو';

  @override
  String get reminderLangRoman => 'Roman Urdu';

  @override
  String get reminderLangEnglish => 'English';

  @override
  String get chaseRemind => 'Yaad-dehani bhejein';

  @override
  String get chaseSelectLate => 'Sab der wale chunein';

  @override
  String chaseSendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ko yaad dilayein',
      one: '1 ko yaad dilayein',
    );
    return '$_temp0';
  }

  @override
  String get chasePickHint => 'Jin ko yaad dilana hai un par tick lagayein';

  @override
  String get roundTitle => 'Yaad-dehani';

  @override
  String roundResume(int left) {
    String _temp0 = intl.Intl.pluralLogic(
      left,
      locale: localeName,
      other: 'Yaad-dehani adhoori hai: $left baqi',
      one: 'Yaad-dehani adhoori hai: 1 baqi',
    );
    return '$_temp0';
  }

  @override
  String get roundResumeAction => 'Jaari rakhein';

  @override
  String get roundDiscard => 'Khatam karein';

  @override
  String get roundChannelSms => 'SMS';

  @override
  String get roundOpenWhatsApp => 'WhatsApp par kholein';

  @override
  String get roundOpenSms => 'SMS mein kholein';

  @override
  String get roundSent => 'Bhej diya ✓';

  @override
  String get roundSkip => 'Chhor dein';

  @override
  String get roundLater => 'Baad mein';

  @override
  String roundDone(int sent, int skipped) {
    return 'Sab ho gaye: $sent ko bheja, $skipped chhore';
  }

  @override
  String get roundFinish => 'Khatam';

  @override
  String get roundNoNumber => 'Number nahi, share sheet se jayega';

  @override
  String get partyReminders => 'Yaad-dehani';

  @override
  String get partyReminderLanguage => 'Kis zabaan mein bhejein';

  @override
  String get partyReminderOptOut => 'Is gahak ko yaad-dehani na bhejein';

  @override
  String get settingsReminders => 'Yaad-dehani ke paighamat';

  @override
  String get templatesTitle => 'Yaad-dehani ke paighamat';

  @override
  String get templatesHint =>
      'Har gahak ko unki zabaan wala paigham jata hai. Braces wale khaane khud bhar jate hain; jis line ka khaana khaali ho woh nahi jati.';

  @override
  String get templatesField => 'Paigham';

  @override
  String get templatesPreview => 'Aisa jayega';

  @override
  String get templatesSaved => 'Paigham save ho gaya';

  @override
  String get templatesReset => 'Dukaan ke asal alfaz wapas layein';

  @override
  String get templatesResetDone => 'Asal alfaz wapas aa gaye';

  @override
  String get templatesSampleName => 'Aslam Karyana';

  @override
  String get khataWriteOff => 'Doobi hui raqam likhein';

  @override
  String get writeOffTitle => 'Doobi hui raqam';

  @override
  String get writeOffExplain =>
      'Yeh raqam khate se hat kar \'Doobi hui raqam\' kharche mein jayegi aur munafa nuqsan mein nazar aayegi. Ghalti ho to khate mein is entry ko mansookh karein, udhaar wapas aa jayega.';

  @override
  String writeOffWhole(String amount) {
    return 'Kul baqaya: Rs $amount';
  }

  @override
  String get writeOffWholeShort => 'Poora baqaya';

  @override
  String get writeOffBills => 'Sirf kuch bill';

  @override
  String get writeOffWhy => 'Kyun chhor rahe hain?';

  @override
  String get writeOffReasonMoved => 'Gahak chala gaya';

  @override
  String get writeOffReasonDied => 'Wafaat ho gayi';

  @override
  String get writeOffReasonRefused => 'Dene se inkaar';

  @override
  String get writeOffReasonClosed => 'Un ka kaam band';

  @override
  String get writeOffReasonText => 'Wajah likhein';

  @override
  String get writeOffReasonRequired => 'Wajah zaroori hai';

  @override
  String get writeOffPickBills => 'Kam se kam aik bill chunein';

  @override
  String get writeOffSave => 'Doobi hui raqam mein likh dein';

  @override
  String writeOffSaved(String no, String amount) {
    return '$no: Rs $amount doobi hui raqam mein likh diye';
  }

  @override
  String get badDebtsTitle => 'Chhori hui raqam';

  @override
  String get badDebtsWrittenOff => 'Doobi hui';

  @override
  String get badDebtsDiscounts => 'Riayat';

  @override
  String get badDebtsEmpty => 'Abhi kuch nahi chhora';

  @override
  String get allowanceTotal => 'Kul (mansookh ke ilawa)';

  @override
  String allowanceBy(String name) {
    return '$name ne chhora';
  }

  @override
  String allowanceDiscountLine(String no) {
    return 'Riayat $no';
  }

  @override
  String allowanceWriteOffLine(String no) {
    return 'Doobi hui raqam $no';
  }

  @override
  String entryDiscountTitle(String no) {
    return 'Riayat $no';
  }

  @override
  String entryWriteOffTitle(String no) {
    return 'Doobi hui raqam $no';
  }

  @override
  String get entryAllowanceNoEdit =>
      'Isay badla nahi jata: mansookh kar ke dobara likhein.';

  @override
  String get tenderModeAdjustment => 'Chhoot';

  @override
  String get settleDiscountToggle => 'Baqi chhor dein (riayat se hisaab saaf)';

  @override
  String settleDiscountLine(String amount) {
    return 'Riayat: Rs $amount, sab bill saaf';
  }

  @override
  String get settleDiscountNone =>
      'Itne mein poora hisaab saaf hai, riayat ki zaroorat nahi';

  @override
  String get settleDiscountReason => 'Riayat ki wajah (marzi se)';

  @override
  String settleDiscountSaved(String amount, String discount) {
    return 'Rs $amount wasool, Rs $discount chhor diye';
  }

  @override
  String get settleDiscountOverCeiling =>
      'Itni riayat aap ki hadd se ziyada hai. Malik, manager ya accountant se karwayein.';

  @override
  String get chaseBadDebts => 'Chhori hui raqam';

  @override
  String get billMoreActions => 'Aur';

  @override
  String get copyAction => 'Isi tarah ka naya bill';

  @override
  String get correctAction => 'Ghalti theek karein';

  @override
  String copyRatesTitle(String docNo) {
    return '$docNo dobara: kaun se rate?';
  }

  @override
  String get copyRatesToday => 'Aaj ke rate';

  @override
  String get copyRatesTodayHint => 'Is gahak ki aaj ki qeemat aur riayat';

  @override
  String get copyRatesOld => 'Purane rate';

  @override
  String copyRatesOldHint(String docNo) {
    return 'Jo $docNo par lage the, riayat samait';
  }

  @override
  String copyLoaded(String docNo) {
    return '$docNo ki naqal counter par hai';
  }

  @override
  String copyLeftOut(String names) {
    return 'Yeh nahi aayin: $names';
  }

  @override
  String copyNothing(String docNo) {
    return '$docNo ki koi cheez counter par nahi aa sakti';
  }

  @override
  String copyWhyGone(String name) {
    return '$name (cheez hata di gayi)';
  }

  @override
  String copyWhyFree(String name) {
    return '$name (muft)';
  }

  @override
  String copyWhySerial(String name) {
    return '$name (serial dobara scan karein)';
  }

  @override
  String copyWhyTwice(String name) {
    return '$name (bill par do dafa)';
  }

  @override
  String copyNoCustomer(String name) {
    return '$name ab khate mein nahi; bill bina gahak ke';
  }

  @override
  String repeatLastOrder(String docNo) {
    return 'Pichhla order dobara ($docNo)';
  }

  @override
  String get correctTitle => 'Ghalti theek karein';

  @override
  String get correctExplain =>
      'Yeh bill mansookh hoga (iska number aur kaghaz waisay hi rahenge) aur iski naqal counter par khulegi. Ghalti theek kar ke naya bill save karein; dono bill aapas mein jure rahenge.';

  @override
  String correctPaid(String amount, String mode) {
    return 'Is bill par Rs $amount ($mode) liye gaye the. Naye bill mein yehi raqam pehle se likhi hogi.';
  }

  @override
  String get correctUdhaar =>
      'Yeh bill udhaar par tha; naya bill bhi udhaar par khulega.';

  @override
  String get correctAbandon =>
      'Naya bill save na kiya to bhi yeh bill mansookh hi rahega.';

  @override
  String correctAbandonPaid(String amount) {
    return 'Naya bill save na kiya to bhi yeh bill mansookh hi rahega, aur Rs $amount gahak ko wapas dene honge.';
  }

  @override
  String get correctConfirm => 'Mansookh kar ke naya bill kholein';

  @override
  String get reasonWrongItem => 'Galat cheez';

  @override
  String get reasonWrongQty => 'Galat tadaad';

  @override
  String get reasonWrongPrice => 'Galat qeemat';

  @override
  String get reasonWrongCustomer => 'Galat gahak';

  @override
  String get reasonOrderCancelled => 'Gahak ne order chhor diya';

  @override
  String correctOnCounter(String docNo) {
    return '$docNo ki jagah naya bill';
  }

  @override
  String correctOnCounterHint(String docNo) {
    return '$docNo mansookh ho chuka hai. Theek kar ke paisay lein.';
  }

  @override
  String correctClearConfirm(String docNo) {
    return 'Naya bill chhor dein? $docNo phir bhi mansookh rahega.';
  }

  @override
  String tenderPaidBefore(String docNo, String amount, String mode) {
    return '$docNo par Rs $amount ($mode) liye gaye the; wohi yahan likhe hain.';
  }

  @override
  String tenderPaidBeforeUdhaar(String docNo) {
    return '$docNo poora udhaar par tha.';
  }

  @override
  String tenderGiveBack(String amount) {
    return 'Rs $amount gahak ko wapas dein';
  }

  @override
  String tenderTakeMore(String amount) {
    return 'Rs $amount aur lein';
  }

  @override
  String billReplaces(String docNo) {
    return '$docNo ki jagah bana';
  }

  @override
  String billReplacedBy(String docNo) {
    return 'Iski jagah $docNo bana';
  }

  @override
  String billReplacedByVoid(String docNo) {
    return 'Iski jagah $docNo bana (woh bhi mansookh)';
  }

  @override
  String get copyHint => 'Wohi cheezein aur gahak, naye bill mein';

  @override
  String get trailAction => 'Tareekh';

  @override
  String trailTitle(String no) {
    return 'Tareekh · $no';
  }

  @override
  String get trailEmpty => 'Is par abhi kuch likha nahi gaya';

  @override
  String trailByOn(String who, String device, String when) {
    return '$who, $device par · $when';
  }

  @override
  String trailBy(String who, String when) {
    return '$who · $when';
  }

  @override
  String trailWhy(String reason) {
    return 'Wajah: $reason';
  }

  @override
  String get trailMade => 'Banaya gaya';

  @override
  String get trailPrinted => 'Print hua';

  @override
  String get trailPrintFailed => 'Print nahi hua';

  @override
  String get trailCancelled => 'Cancel hua';

  @override
  String get trailReturned => 'Maal wapas aaya';

  @override
  String get trailPaid => 'Is par raqam lagi';

  @override
  String get trailPaidAtCounter => 'Counter par diye';

  @override
  String get trailLetGo => 'Chhor diye';

  @override
  String get trailSettled => 'Is bill par laga';

  @override
  String get trailReleased => 'Is bill se hata (cancel)';

  @override
  String get trailCorrected => 'Durust kiya';

  @override
  String get trailChanged => 'Badla gaya';

  @override
  String get trailApproved => 'PIN se ijazat';

  @override
  String get trailMadeFrom => 'Is se bana';

  @override
  String get trailBecame => 'Bill bana';

  @override
  String get trailReturnOf => 'Is bill ki wapsi';

  @override
  String trailOpen(String no) {
    return '$no kholein';
  }

  @override
  String get trailFieldName => 'Naam';

  @override
  String get trailFieldPhone => 'Phone';

  @override
  String get trailFieldAddress => 'Pata';

  @override
  String get trailFieldSaleRate => 'Bechne ka rate';

  @override
  String get trailFieldPurchaseRate => 'Khareed ka rate';

  @override
  String get trailFieldCreditLimit => 'Udhaar ki hadd';

  @override
  String get trailFieldOpening => 'Pichla baqaya';

  @override
  String get trailFieldAmount => 'Raqam';

  @override
  String get trailFieldActive => 'Nazar aata hai';

  @override
  String get trailFieldGroup => 'Group';

  @override
  String get trailFieldBarcode => 'Barcode';

  @override
  String get trailYes => 'Haan';

  @override
  String get trailNo => 'Nahi';

  @override
  String get approvalClosedTitle => 'Hisaab band hai';

  @override
  String approvalClosedBody(String date, String entryDate) {
    return '$date tak ka hisaab band hai, aur yeh $entryDate ki entry hai. Sirf Malik apne PIN aur wajah ke saath ise andar daal sakta hai.';
  }

  @override
  String get approvalLockTitle => 'Data Lock: PIN chahiye';

  @override
  String get approvalLockBody =>
      'Kuch bhi cancel, chhorne ya chhupane se pehle PIN chahiye.';

  @override
  String get approvalWho => 'Kis ka PIN';

  @override
  String get approvalReason => 'Wajah (zaroori)';

  @override
  String get approvalAllow => 'Ijazat dein';

  @override
  String get approvalWrongPin => 'Ghalat PIN';

  @override
  String get approvalTooMany =>
      'Bohat ghalat PIN. Aadha minute ruk kar dobara.';

  @override
  String get approvalReasonNeeded => 'Wajah likhein';

  @override
  String get approvalNoPin => 'Is ka koi PIN nahi, kisi aur ka PIN dein';

  @override
  String get booksLockTitle => 'Hisaab band aur Data Lock';

  @override
  String booksClosedThrough(String date) {
    return '$date tak hisaab band hai';
  }

  @override
  String get booksOpenNow => 'Abhi koi din band nahi';

  @override
  String get booksCloseExplain =>
      'Band din par ya us se pehle ki koi nayi entry, cancel ya durustagi nahi hogi, jab tak Malik PIN aur wajah se ijazat na de. Aaj ki wapsi purane bill par bhi aaj ki hai, woh ho jati hai.';

  @override
  String booksCloseThrough(String date) {
    return '$date tak band karein';
  }

  @override
  String get booksClosePick => 'Koi aur din chunein';

  @override
  String get booksReopen => 'Hisaab dobara kholein';

  @override
  String booksClosedDone(String date) {
    return 'Hisaab $date tak band';
  }

  @override
  String get booksReopened => 'Hisaab dobara khul gaya';

  @override
  String get dataLockTitle => 'Cancel se pehle PIN (Data Lock)';

  @override
  String get dataLockExplain =>
      'Bill ya payment cancel karna, payment durust karna, udhaar chhorna, cheez ya customer chhupana, ya backup wapas lana: har ek se pehle PIN. Jo kar raha hai us ka apna PIN, ya Malik ka.';

  @override
  String get dataLockNeedsPin => 'Pehle apna PIN rakhein (Staff aur PIN)';

  @override
  String get lateArrivalsTitle => 'Band hone ke baad counter se aayi entries';

  @override
  String get lateArrivalsExplain =>
      'Yeh dusre counter par band hone se pehle bani thin, is liye le li gayin. Band dinon ka hisaab in ke saath dobara dekh lein.';

  @override
  String get homeOrders => 'Order';

  @override
  String get ordersTitle => 'Order';

  @override
  String get ordersPurchase => 'Purchase order (PO)';

  @override
  String get ordersPurchaseHint => 'Supplier se kya mangwaya, aur kitna aaya';

  @override
  String get ordersSale => 'Gahak ke order';

  @override
  String get ordersSaleHint => 'Gahak ne kya mangwaya, kitna diya, advance';

  @override
  String get ordersShortage => 'Mangwana hai';

  @override
  String get ordersShortageHint => 'Gahak ne maanga aur shelf par nahi tha';

  @override
  String get ordersReorder => 'Order banayein';

  @override
  String get ordersReorderHint =>
      'Kam maal aur mangwana hai, supplier ke hisaab se';

  @override
  String ordersOpenCount(int count) {
    return '$count khule';
  }

  @override
  String get orderListEmptyPurchase => 'Abhi koi PO nahi';

  @override
  String get orderListEmptyPurchaseHint =>
      'Supplier ko jo mangwana ho, uski PO banayein aur WhatsApp par bhejein';

  @override
  String get orderListEmptySale => 'Abhi koi gahak ka order nahi';

  @override
  String get orderListEmptySaleHint =>
      'Gahak ka order likhein, advance ke saath ya baghair';

  @override
  String get orderNewPurchase => 'Nayi PO';

  @override
  String get orderNewSale => 'Naya gahak order';

  @override
  String get orderStatusOpen => 'Khula';

  @override
  String get orderStatusPartIn => 'Kuch aa gaya';

  @override
  String get orderStatusPartOut => 'Kuch de diya';

  @override
  String get orderStatusDoneIn => 'Sab aa gaya';

  @override
  String get orderStatusDoneOut => 'Sab de diya';

  @override
  String get orderStatusCancelled => 'Mansookh';

  @override
  String get orderStatusClosed => 'Band, baqi nahi aayega';

  @override
  String get orderLate => 'Der ho gayi';

  @override
  String orderDue(String date) {
    return '$date tak';
  }

  @override
  String orderAdvance(String amount) {
    return 'Advance Rs $amount';
  }

  @override
  String get orderCustomer => 'Gahak chunein';

  @override
  String get orderPartyRequired => 'Pehle supplier ya gahak chunein';

  @override
  String get orderNoLinesHint => 'Jo mangwana hai woh shamil karein';

  @override
  String get orderDueExpected => 'Kab tak aaye';

  @override
  String get orderDuePromised => 'Kab tak dena hai';

  @override
  String get orderDueTomorrow => 'Kal';

  @override
  String orderDueInDays(int count) {
    return '$count din mein';
  }

  @override
  String get orderDueInvalid =>
      'Tareekh YYYY-MM-DD mein likhein, aaj ya aage ki';

  @override
  String get orderNote => 'Note (marzi se)';

  @override
  String get orderAdvanceAmount => 'Advance (marzi se)';

  @override
  String get orderSave => 'Order save karein';

  @override
  String orderSaved(String docNo) {
    return 'Order $docNo ban gaya';
  }

  @override
  String get orderRate => 'Rate';

  @override
  String get orderSupplierRate => 'Supplier ka rate';

  @override
  String get orderItemNeeds => 'Tadaad aur rate sahi likhein';

  @override
  String get orderItemUnitInexact =>
      'Is unit mein yeh tadaad poori nahi banti. Doosra unit chunein.';

  @override
  String get orderReceive => 'Maal aa gaya';

  @override
  String get orderToCounter => 'Counter par bill banayein';

  @override
  String get orderTakeAdvance => 'Advance lein';

  @override
  String orderAdvanceTaken(String amount) {
    return 'Rs $amount advance le liya';
  }

  @override
  String get orderCancel => 'Order mansookh karein';

  @override
  String get orderCancelReason => 'Wajah';

  @override
  String get orderCancelNeedsReason => 'Mansookh karne ki wajah likhein';

  @override
  String orderCancelConfirm(String docNo) {
    return '$docNo mansookh ho jaye ga. Jo aa chuka ya ja chuka woh rahe ga. Wajah likh kar dobara dabayein.';
  }

  @override
  String get orderCancelled => 'Order mansookh ho gaya';

  @override
  String orderLineIn(String done, String left, String unit) {
    return 'Aaya $done, baqi $left $unit';
  }

  @override
  String orderLineOut(String done, String left, String unit) {
    return 'Diya $done, baqi $left $unit';
  }

  @override
  String get orderFollowUps => 'Is order se';

  @override
  String get orderNothingLeft => 'Is order mein ab kuch baqi nahi';

  @override
  String orderStillToCome(String amount) {
    return 'Baqi: Rs $amount';
  }

  @override
  String purchaseFromOrder(String docNo) {
    return 'PO $docNo ke khilaf';
  }

  @override
  String purchaseOrderedRate(String rate, String unit) {
    return 'PO ka rate: $rate / $unit';
  }

  @override
  String purchaseRateDiffers(String now, String ordered) {
    return 'Rate PO se mukhtalif: $now vs $ordered';
  }

  @override
  String get shortageAdd => 'Mangwana hai mein likhein';

  @override
  String get shortageEmpty => 'Kuch mangwana baqi nahi';

  @override
  String get shortageEmptyHint =>
      'Gahak koi cheez maange jo shelf par nahi, to counter ke * se yahan likhein';

  @override
  String get shortageWhat => 'Kya maanga?';

  @override
  String get shortageWhatNeeded => 'Likhein gahak ne kya maanga';

  @override
  String get shortageQty => 'Kitna (marzi se)';

  @override
  String get shortageSave => 'List mein likhein';

  @override
  String shortageSaved(String name) {
    return '$name list mein likh diya';
  }

  @override
  String get shortageClear => 'Mil gaya';

  @override
  String get shortageShare => 'List bhejein';

  @override
  String get reorderEmpty => 'Abhi kuch mangwane ki zaroorat nahi';

  @override
  String get reorderEmptyHint =>
      'Cheez par kam se kam stock likhein, ya counter se mangwana hai mein daalein';

  @override
  String get reorderNoSupplier => 'Supplier maloom nahi';

  @override
  String reorderFacts(String stock, String sold, String onOrder) {
    return 'Stock $stock · $sold bika · $onOrder raaste mein';
  }

  @override
  String get reorderAsked => 'Gahak ne maanga';

  @override
  String get reorderMakeOne => 'Is ki PO';

  @override
  String reorderMakeAll(int count) {
    return 'PO banayein ($count supplier)';
  }

  @override
  String reorderMade(int count) {
    return '$count PO ban gayi';
  }

  @override
  String get reorderNothingPicked =>
      'Kuch chuna nahi. Tadaad likhein ya supplier chunein.';

  @override
  String get reportOpenPurchaseOrders => 'Khuli purchase orders';

  @override
  String get reportOpenPurchaseOrdersHint =>
      'Supplier se jo maal aana baqi hai, kitne din se';

  @override
  String get reportOpenSaleOrders => 'Khule gahak order';

  @override
  String get reportOpenSaleOrdersHint =>
      'Gahak ko jo dena baqi hai, advance ke saath';

  @override
  String get reportOrderItemsDue => 'Orders ki cheezein';

  @override
  String get reportOrderItemsDueHint =>
      'Har cheez: kitna mangwaya, aaya ya gaya, baqi';

  @override
  String get orderItemAdd => 'Order mein daalein';

  @override
  String get shortageWrite => 'Likhein';

  @override
  String get shelfRuleTitle => 'Stock khatam ho to';

  @override
  String get shelfRuleAllow => 'Bechte rahein';

  @override
  String get shelfRuleAllowHint =>
      'Koi sawal nahi. Stock minus mein chala jaye ga aur list mein laal dikhe ga.';

  @override
  String get shelfRuleWarn => 'Pehle poochein';

  @override
  String get shelfRuleWarnHint =>
      'Cashier se poocha jaye ga: stock itna hi hai, phir bhi bechein?';

  @override
  String get shelfRuleBlock => 'Na bechein';

  @override
  String get shelfRuleBlockHint =>
      'Stock se zyada nahi bikta. Maalik stock theek kare ya item ki setting badle.';

  @override
  String shelfRuleShop(String rule) {
    return 'Dukaan ki setting ($rule)';
  }

  @override
  String get shelfRuleShopHint =>
      'Har us item par lagti hai jis ki apni setting nahi. Har item apni bhi rakh sakta hai.';

  @override
  String get shelfRuleOwnerOnly => 'Yeh setting sirf maalik badal sakta hai.';

  @override
  String get shelfWarnTitle => 'Stock kam hai';

  @override
  String shelfWarnAsk(String onHand) {
    return 'Stock sirf $onHand hai — phir bhi bechein?';
  }

  @override
  String shelfOnBill(String item, String wanted) {
    return '$item: bill par $wanted';
  }

  @override
  String get shelfSellAnyway => 'Haan, bechein';

  @override
  String get shelfBlockedTitle => 'Stock se zyada nahi bik sakta';

  @override
  String shelfBlocked(String onHand) {
    return 'Stock sirf $onHand hai — is se zyada nahi bikta. Maalik stock theek kare ya item ki setting badle.';
  }

  @override
  String get itemsBelowNothing => 'Stock minus mein';

  @override
  String get itemPacksTitle => 'Packing (carton, dabba, bori)';

  @override
  String itemPacksHint(String unit) {
    return 'Aik pack mein kitna maal hai. Bill aur khareed pack se bhi ho sakti hai; stock $unit mein hi ginta hai.';
  }

  @override
  String get itemPackAdd => 'Pack jorein';

  @override
  String get itemPackUnit => 'Pack';

  @override
  String itemPackSize(String pack, String unit) {
    return '1 $pack mein kitne $unit?';
  }

  @override
  String get itemPackRemove => 'Pack hatayein';

  @override
  String get itemPackNoneLeft => 'Har pack lag chuka hai.';

  @override
  String get purchaseInPack => 'Kis mein aaya';

  @override
  String get reportLoanStatement => 'Qarz ka hisaab';

  @override
  String get reportLoanStatementHint =>
      'Sab qarz ek safhe par, ya ek qarz ki wasooli, adaigi aur sood';

  @override
  String get reportReceivablesByDue => 'Udhaar, adaigi ki tareekh se';

  @override
  String get reportReceivablesByDueHint =>
      'Kaun der se hai, aur har bill adaigi ki tareekh se kitne din upar';

  @override
  String get reportBadDebts => 'Doobi raqam aur riayat';

  @override
  String get reportBadDebtsHint =>
      'Chhora gaya udhaar: kis ka, kyun, kitna, aur kis ne chhora';

  @override
  String get reportFilterLoan => 'Qarz';

  @override
  String get reportViewTable => 'Table';

  @override
  String get reportViewChart => 'Chart';

  @override
  String reportChartRest(int count) {
    return 'Baaqi sab ($count)';
  }

  @override
  String get reportChartNothing => 'Is muddat mein dikhane ko kuch nahi';

  @override
  String reportChartHighest(String label, String amount) {
    return 'Sab se ziyada: $label, $amount';
  }

  @override
  String reportChartPicked(String label, String amount) {
    return '$label: $amount';
  }

  @override
  String get reportChartTotal => 'Kul';

  @override
  String reportChartLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines sifar ya kam hain, dikhayi nahi gayin',
      one: '1 line sifar ya kam hai, dikhayi nahi gayi',
    );
    return '$_temp0';
  }

  @override
  String reportChartSummary(String what, int count, String amount) {
    return '$what ka chart: $count hisse, kul $amount';
  }

  @override
  String get reportTodayTitle => 'Aaj';

  @override
  String get reportTodaySale => 'Bikri';

  @override
  String get reportTodayReceived => 'Wasool';

  @override
  String get reportTodayUdhaar => 'Udhaar diya';

  @override
  String get reportTodayExpenses => 'Kharche';

  @override
  String get reportTodayProfit => 'Maal ka nafa';

  @override
  String get reportTodayOpen => 'Aaj ka Z report kholein';

  @override
  String get reportFilterMinAmount => 'Raqam';

  @override
  String reportFilterMinAmountValue(String amount) {
    return '$amount ya ziyada';
  }

  @override
  String bonusOnCounter(String what) {
    return 'Bonus / muft: $what';
  }

  @override
  String get bonusTakeOff => 'Bonus hatayein';

  @override
  String bonusTakenOff(String what) {
    return 'Bonus hata diya: $what';
  }

  @override
  String get bonusPutBack => 'Wapas lagayein';

  @override
  String bonusSchemeHint(String label) {
    return 'Scheme $label';
  }

  @override
  String billSlabApplied(String percent, String from) {
    return 'Bill par $percent discount (Rs $from se upar)';
  }

  @override
  String get billSlabTakeOff => 'Hatayein';

  @override
  String billSlabTakenOff(String percent) {
    return '$percent bill discount hata diya';
  }

  @override
  String billSlabNext(String short, String percent) {
    return 'Rs $short ka aur saman lein to bill par $percent discount';
  }

  @override
  String get schemesTitle => 'Scheme aur slab';

  @override
  String get schemesIntro =>
      'Bonus (10+1), tadaad par sasta rate, aur bare bill par discount. Counter khud lagata hai, aur cashier bill se hata sakta hai.';

  @override
  String get schemesOwnerOnly => 'Scheme sirf malik badal sakta hai.';

  @override
  String get schemesItemsHeader => 'Maal ki scheme';

  @override
  String get schemesNoItems => 'Abhi kisi maal par scheme nahi.';

  @override
  String get schemesAddItem => 'Maal par scheme lagayein';

  @override
  String schemeBonusLabel(String label) {
    return 'Bonus $label';
  }

  @override
  String schemeSlabsLabel(int count) {
    return '$count rate slab';
  }

  @override
  String get billSlabsHeader => 'Bare bill par discount';

  @override
  String get billSlabFrom => 'Bill kam az kam (Rs)';

  @override
  String get billSlabPercent => 'Discount %';

  @override
  String get schemeAddSlab => 'Aur slab';

  @override
  String get schemeSaved => 'Scheme save ho gayi';

  @override
  String get schemeTakeOff => 'Scheme hatayein';

  @override
  String itemSchemeTitle(String name) {
    return 'Scheme: $name';
  }

  @override
  String get itemSchemeEntry => 'Scheme (10+1) aur tadaad par rate';

  @override
  String get itemSchemeSaveFirst =>
      'Pehle maal save karein, phir scheme lagayein.';

  @override
  String get bonusHeader => 'Bonus (muft maal)';

  @override
  String bonusBuy(String unit) {
    return 'Itne lein ($unit)';
  }

  @override
  String bonusFree(String unit) {
    return 'Itne muft ($unit)';
  }

  @override
  String get bonusCountedIn => 'Ginti kis mein';

  @override
  String bonusFreeGoods(String name) {
    return 'Muft: $name';
  }

  @override
  String get bonusSameItem => 'yehi maal';

  @override
  String get bonusOtherItem => 'Doosra maal';

  @override
  String bonusExplain(String buy, String free) {
    return 'Har $buy par $free muft';
  }

  @override
  String get slabsHeader => 'Tadaad par rate';

  @override
  String get slabHint =>
      'Slab ka rate sirf tab lagta hai jab gahak ki apni qeemat se kam ho.';

  @override
  String slabFrom(String unit) {
    return 'Kam az kam ($unit)';
  }

  @override
  String slabRate(String unit) {
    return 'Rate (fi $unit)';
  }

  @override
  String get schemeProblemFigures =>
      'Koi raqam theek nahi likhi. Tadaad aur rate dobara dekhein.';

  @override
  String get schemeProblemBonusEmpty =>
      'Bonus mein lene aur muft dono ki tadaad likhein.';

  @override
  String get schemeProblemSlabEmpty => 'Har slab ki tadaad aur rate likhein.';

  @override
  String get schemeProblemSlabTwice =>
      'Do slab aik hi raqam se shuru nahi ho sakte.';

  @override
  String get schemeProblemOutOfOrder =>
      'Bari slab ka rate ya discount behtar hona chahiye.';

  @override
  String get schemeProblemPercent => 'Discount 0% se zyada aur 50% tak ho.';

  @override
  String purchaseFree(String unit) {
    return 'Muft / bonus ($unit)';
  }

  @override
  String purchaseFreeOnLine(String what) {
    return '+ $what muft';
  }

  @override
  String get purchaseFreeWrong => 'Muft tadaad theek nahi likhi.';
}
