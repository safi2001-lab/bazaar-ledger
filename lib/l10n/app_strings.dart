import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_strings_en.dart';
import 'app_strings_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppStrings
/// returned by `AppStrings.of(context)`.
///
/// Applications need to include `AppStrings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_strings.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppStrings.localizationsDelegates,
///   supportedLocales: AppStrings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppStrings.supportedLocales
/// property.
abstract class AppStrings {
  AppStrings(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
  ];

  /// The product name. Not translated.
  ///
  /// In ur, this message translates to:
  /// **'Bazaar Ledger'**
  String get appName;

  /// No description provided for @actionSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In ur, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In ur, this message translates to:
  /// **'Delete karein'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In ur, this message translates to:
  /// **'Tabdeeli karein'**
  String get actionEdit;

  /// No description provided for @actionRetry.
  ///
  /// In ur, this message translates to:
  /// **'Dobara koshish karein'**
  String get actionRetry;

  /// No description provided for @actionContinue.
  ///
  /// In ur, this message translates to:
  /// **'Aage barhein'**
  String get actionContinue;

  /// No description provided for @actionBack.
  ///
  /// In ur, this message translates to:
  /// **'Wapas'**
  String get actionBack;

  /// No description provided for @actionClose.
  ///
  /// In ur, this message translates to:
  /// **'Band karein'**
  String get actionClose;

  /// No description provided for @actionSearch.
  ///
  /// In ur, this message translates to:
  /// **'Talash karein'**
  String get actionSearch;

  /// No description provided for @actionShare.
  ///
  /// In ur, this message translates to:
  /// **'Bhejein'**
  String get actionShare;

  /// No description provided for @actionPrint.
  ///
  /// In ur, this message translates to:
  /// **'Print karein'**
  String get actionPrint;

  /// No description provided for @actionAdd.
  ///
  /// In ur, this message translates to:
  /// **'Shamil karein'**
  String get actionAdd;

  /// No description provided for @actionDone.
  ///
  /// In ur, this message translates to:
  /// **'Ho gaya'**
  String get actionDone;

  /// No description provided for @actionOk.
  ///
  /// In ur, this message translates to:
  /// **'Theek hai'**
  String get actionOk;

  /// No description provided for @commonLoading.
  ///
  /// In ur, this message translates to:
  /// **'Khul raha hai...'**
  String get commonLoading;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In ur, this message translates to:
  /// **'Kuch masla ho gaya'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonNothingSaved.
  ///
  /// In ur, this message translates to:
  /// **'Kuch save nahi hua'**
  String get commonNothingSaved;

  /// No description provided for @commonRequired.
  ///
  /// In ur, this message translates to:
  /// **'Yeh khana zaroori hai'**
  String get commonRequired;

  /// No description provided for @commonOffline.
  ///
  /// In ur, this message translates to:
  /// **'Internet nahi hai - koi baat nahi, sab kuch phone par chalta hai'**
  String get commonOffline;

  /// No description provided for @commonYes.
  ///
  /// In ur, this message translates to:
  /// **'Haan'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In ur, this message translates to:
  /// **'Nahi'**
  String get commonNo;

  /// No description provided for @setupTitle.
  ///
  /// In ur, this message translates to:
  /// **'Apni dukan set karein'**
  String get setupTitle;

  /// No description provided for @setupSubtitle.
  ///
  /// In ur, this message translates to:
  /// **'Sirf teen cheezein. Baqi baad mein bhi badal sakte hain.'**
  String get setupSubtitle;

  /// No description provided for @setupShopName.
  ///
  /// In ur, this message translates to:
  /// **'Dukan ka naam'**
  String get setupShopName;

  /// No description provided for @setupShopNameHint.
  ///
  /// In ur, this message translates to:
  /// **'Chishti Kiryana Store'**
  String get setupShopNameHint;

  /// No description provided for @setupOwnerName.
  ///
  /// In ur, this message translates to:
  /// **'Aap ka naam'**
  String get setupOwnerName;

  /// No description provided for @setupOwnerNameHint.
  ///
  /// In ur, this message translates to:
  /// **'Malik Sahib'**
  String get setupOwnerNameHint;

  /// No description provided for @setupCity.
  ///
  /// In ur, this message translates to:
  /// **'Shehar'**
  String get setupCity;

  /// No description provided for @setupCityHint.
  ///
  /// In ur, this message translates to:
  /// **'Lahore'**
  String get setupCityHint;

  /// No description provided for @setupProvince.
  ///
  /// In ur, this message translates to:
  /// **'Suba'**
  String get setupProvince;

  /// No description provided for @setupBusinessKind.
  ///
  /// In ur, this message translates to:
  /// **'Dukan ki qism'**
  String get setupBusinessKind;

  /// No description provided for @setupCounterName.
  ///
  /// In ur, this message translates to:
  /// **'Is counter ka naam'**
  String get setupCounterName;

  /// No description provided for @setupCounterHint.
  ///
  /// In ur, this message translates to:
  /// **'Counter 1'**
  String get setupCounterHint;

  /// No description provided for @setupFinish.
  ///
  /// In ur, this message translates to:
  /// **'Dukan shuru karein'**
  String get setupFinish;

  /// No description provided for @setupPrivacyNote.
  ///
  /// In ur, this message translates to:
  /// **'Aap ka saara hisaab isi phone mein rehta hai. Na koi account, na koi server.'**
  String get setupPrivacyNote;

  /// No description provided for @businessKindGeneral.
  ///
  /// In ur, this message translates to:
  /// **'General store'**
  String get businessKindGeneral;

  /// No description provided for @businessKindKiryana.
  ///
  /// In ur, this message translates to:
  /// **'Kiryana'**
  String get businessKindKiryana;

  /// No description provided for @businessKindPharmacy.
  ///
  /// In ur, this message translates to:
  /// **'Medical store'**
  String get businessKindPharmacy;

  /// No description provided for @businessKindGarments.
  ///
  /// In ur, this message translates to:
  /// **'Garments'**
  String get businessKindGarments;

  /// No description provided for @businessKindCloth.
  ///
  /// In ur, this message translates to:
  /// **'Kapre ka kaam'**
  String get businessKindCloth;

  /// No description provided for @businessKindHardware.
  ///
  /// In ur, this message translates to:
  /// **'Hardware'**
  String get businessKindHardware;

  /// No description provided for @businessKindElectronics.
  ///
  /// In ur, this message translates to:
  /// **'Electronics'**
  String get businessKindElectronics;

  /// No description provided for @businessKindRestaurant.
  ///
  /// In ur, this message translates to:
  /// **'Hotel / Restaurant'**
  String get businessKindRestaurant;

  /// No description provided for @businessKindServices.
  ///
  /// In ur, this message translates to:
  /// **'Services'**
  String get businessKindServices;

  /// No description provided for @businessKindWholesale.
  ///
  /// In ur, this message translates to:
  /// **'Wholesale'**
  String get businessKindWholesale;

  /// No description provided for @provincePunjab.
  ///
  /// In ur, this message translates to:
  /// **'Punjab'**
  String get provincePunjab;

  /// No description provided for @provinceSindh.
  ///
  /// In ur, this message translates to:
  /// **'Sindh'**
  String get provinceSindh;

  /// No description provided for @provinceKpk.
  ///
  /// In ur, this message translates to:
  /// **'Khyber Pakhtunkhwa'**
  String get provinceKpk;

  /// No description provided for @provinceBalochistan.
  ///
  /// In ur, this message translates to:
  /// **'Balochistan'**
  String get provinceBalochistan;

  /// No description provided for @provinceIct.
  ///
  /// In ur, this message translates to:
  /// **'Islamabad'**
  String get provinceIct;

  /// No description provided for @provinceGb.
  ///
  /// In ur, this message translates to:
  /// **'Gilgit-Baltistan'**
  String get provinceGb;

  /// No description provided for @provinceAjk.
  ///
  /// In ur, this message translates to:
  /// **'Azad Kashmir'**
  String get provinceAjk;

  /// No description provided for @homeTitle.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ka hisaab'**
  String get homeTitle;

  /// No description provided for @homeTodaySales.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki farokht'**
  String get homeTodaySales;

  /// No description provided for @homeBillCount.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =0{Koi bill nahi} =1{1 bill} other{{count} bill}}'**
  String homeBillCount(int count);

  /// No description provided for @homeReceived.
  ///
  /// In ur, this message translates to:
  /// **'Wasool'**
  String get homeReceived;

  /// No description provided for @homeOnUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar par'**
  String get homeOnUdhaar;

  /// No description provided for @homeNewBill.
  ///
  /// In ur, this message translates to:
  /// **'Naya Bill'**
  String get homeNewBill;

  /// No description provided for @homeItems.
  ///
  /// In ur, this message translates to:
  /// **'Maal'**
  String get homeItems;

  /// No description provided for @homeSales.
  ///
  /// In ur, this message translates to:
  /// **'Farokht'**
  String get homeSales;

  /// No description provided for @homeCustomers.
  ///
  /// In ur, this message translates to:
  /// **'Gahak'**
  String get homeCustomers;

  /// No description provided for @homeSettings.
  ///
  /// In ur, this message translates to:
  /// **'Settings'**
  String get homeSettings;

  /// No description provided for @homeNoSalesToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj abhi koi bill nahi bana'**
  String get homeNoSalesToday;

  /// No description provided for @posTitle.
  ///
  /// In ur, this message translates to:
  /// **'Naya Bill'**
  String get posTitle;

  /// No description provided for @posSearchHint.
  ///
  /// In ur, this message translates to:
  /// **'Maal ka naam ya barcode'**
  String get posSearchHint;

  /// No description provided for @posCartEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Bill abhi khali hai'**
  String get posCartEmpty;

  /// No description provided for @posCartEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Upar se maal talash karein aur bill mein daalein'**
  String get posCartEmptyHint;

  /// No description provided for @posSubtotal.
  ///
  /// In ur, this message translates to:
  /// **'Subtotal'**
  String get posSubtotal;

  /// No description provided for @posDiscount.
  ///
  /// In ur, this message translates to:
  /// **'Riayat'**
  String get posDiscount;

  /// No description provided for @posTax.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax'**
  String get posTax;

  /// No description provided for @posRoundOff.
  ///
  /// In ur, this message translates to:
  /// **'Round off'**
  String get posRoundOff;

  /// No description provided for @posTotal.
  ///
  /// In ur, this message translates to:
  /// **'Total'**
  String get posTotal;

  /// No description provided for @posCharge.
  ///
  /// In ur, this message translates to:
  /// **'Paisay lein'**
  String get posCharge;

  /// No description provided for @posItemsInCart.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheez} other{{count} cheezein}}'**
  String posItemsInCart(int count);

  /// No description provided for @posRemoveLine.
  ///
  /// In ur, this message translates to:
  /// **'Line hatayein'**
  String get posRemoveLine;

  /// No description provided for @posClearCart.
  ///
  /// In ur, this message translates to:
  /// **'Bill khali karein'**
  String get posClearCart;

  /// No description provided for @posClearCartConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Poora bill khali kar dein?'**
  String get posClearCartConfirm;

  /// No description provided for @posWalkInCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Aam gahak'**
  String get posWalkInCustomer;

  /// No description provided for @posChooseCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Gahak chunein'**
  String get posChooseCustomer;

  /// No description provided for @posQty.
  ///
  /// In ur, this message translates to:
  /// **'Tadaad'**
  String get posQty;

  /// No description provided for @posRate.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat'**
  String get posRate;

  /// No description provided for @posAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam'**
  String get posAmount;

  /// No description provided for @posLineDiscount.
  ///
  /// In ur, this message translates to:
  /// **'Is line par riayat'**
  String get posLineDiscount;

  /// No description provided for @posNoStock.
  ///
  /// In ur, this message translates to:
  /// **'Stock khatam'**
  String get posNoStock;

  /// No description provided for @posStockLeft.
  ///
  /// In ur, this message translates to:
  /// **'Stock: {qty} {unit}'**
  String posStockLeft(String qty, String unit);

  /// No description provided for @tenderTitle.
  ///
  /// In ur, this message translates to:
  /// **'Paisay lein'**
  String get tenderTitle;

  /// No description provided for @tenderDue.
  ///
  /// In ur, this message translates to:
  /// **'Dena hai'**
  String get tenderDue;

  /// No description provided for @tenderTendered.
  ///
  /// In ur, this message translates to:
  /// **'Diye gaye'**
  String get tenderTendered;

  /// No description provided for @tenderChange.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi'**
  String get tenderChange;

  /// No description provided for @tenderExact.
  ///
  /// In ur, this message translates to:
  /// **'Poore paisay'**
  String get tenderExact;

  /// No description provided for @tenderRemaining.
  ///
  /// In ur, this message translates to:
  /// **'Baqi'**
  String get tenderRemaining;

  /// No description provided for @tenderOnUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar likh lein'**
  String get tenderOnUdhaar;

  /// No description provided for @tenderModeCash.
  ///
  /// In ur, this message translates to:
  /// **'Cash'**
  String get tenderModeCash;

  /// No description provided for @tenderModeBank.
  ///
  /// In ur, this message translates to:
  /// **'Bank'**
  String get tenderModeBank;

  /// No description provided for @tenderModeJazzCash.
  ///
  /// In ur, this message translates to:
  /// **'JazzCash'**
  String get tenderModeJazzCash;

  /// No description provided for @tenderModeEasypaisa.
  ///
  /// In ur, this message translates to:
  /// **'EasyPaisa'**
  String get tenderModeEasypaisa;

  /// No description provided for @tenderModeRaast.
  ///
  /// In ur, this message translates to:
  /// **'Raast'**
  String get tenderModeRaast;

  /// No description provided for @tenderModeCard.
  ///
  /// In ur, this message translates to:
  /// **'Card'**
  String get tenderModeCard;

  /// No description provided for @tenderModeCheque.
  ///
  /// In ur, this message translates to:
  /// **'Cheque'**
  String get tenderModeCheque;

  /// No description provided for @tenderReference.
  ///
  /// In ur, this message translates to:
  /// **'Reference (marzi se)'**
  String get tenderReference;

  /// No description provided for @tenderManualNote.
  ///
  /// In ur, this message translates to:
  /// **'Paisay jahan se bhi aayein, aap sirf yahan likh dein. App khud koi paisay nahi leti.'**
  String get tenderManualNote;

  /// No description provided for @tenderSaveAndPrint.
  ///
  /// In ur, this message translates to:
  /// **'Save aur Print'**
  String get tenderSaveAndPrint;

  /// No description provided for @tenderSave.
  ///
  /// In ur, this message translates to:
  /// **'Sirf Save karein'**
  String get tenderSave;

  /// No description provided for @tenderUdhaarNeedsCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ke liye gahak chunna zaroori hai'**
  String get tenderUdhaarNeedsCustomer;

  /// No description provided for @tenderCashThresholdWarning.
  ///
  /// In ur, this message translates to:
  /// **'Rs 200,000 se upar ka bill cash mein lene par kharche ka 50% na-manzoor ho sakta hai (s.21(s)). Bank ya digital se lena behtar hai.'**
  String get tenderCashThresholdWarning;

  /// No description provided for @billSaved.
  ///
  /// In ur, this message translates to:
  /// **'Bill {docNo} save ho gaya'**
  String billSaved(String docNo);

  /// No description provided for @billSaveFailed.
  ///
  /// In ur, this message translates to:
  /// **'Bill save nahi hua. Kuch bhi likha nahi gaya.'**
  String get billSaveFailed;

  /// No description provided for @itemsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Maal'**
  String get itemsTitle;

  /// No description provided for @itemsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi maal nahi'**
  String get itemsEmpty;

  /// No description provided for @itemsEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Pehla item daalein, phir bill banana shuru karein'**
  String get itemsEmptyHint;

  /// No description provided for @itemsAdd.
  ///
  /// In ur, this message translates to:
  /// **'Naya maal'**
  String get itemsAdd;

  /// No description provided for @itemsEdit.
  ///
  /// In ur, this message translates to:
  /// **'Maal ki tabdeeli'**
  String get itemsEdit;

  /// No description provided for @itemName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get itemName;

  /// No description provided for @itemNameHint.
  ///
  /// In ur, this message translates to:
  /// **'Cooking Oil 5L'**
  String get itemNameHint;

  /// No description provided for @itemCode.
  ///
  /// In ur, this message translates to:
  /// **'Code (marzi se)'**
  String get itemCode;

  /// No description provided for @itemBarcode.
  ///
  /// In ur, this message translates to:
  /// **'Barcode (marzi se)'**
  String get itemBarcode;

  /// No description provided for @itemCategory.
  ///
  /// In ur, this message translates to:
  /// **'Qism (marzi se)'**
  String get itemCategory;

  /// No description provided for @itemUnit.
  ///
  /// In ur, this message translates to:
  /// **'Unit'**
  String get itemUnit;

  /// No description provided for @itemSalePrice.
  ///
  /// In ur, this message translates to:
  /// **'Farokht ki qeemat'**
  String get itemSalePrice;

  /// No description provided for @itemPurchasePrice.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ki qeemat'**
  String get itemPurchasePrice;

  /// No description provided for @itemOpeningStock.
  ///
  /// In ur, this message translates to:
  /// **'Mojooda stock'**
  String get itemOpeningStock;

  /// No description provided for @itemMinStock.
  ///
  /// In ur, this message translates to:
  /// **'Kam stock ki hadd'**
  String get itemMinStock;

  /// No description provided for @itemArchive.
  ///
  /// In ur, this message translates to:
  /// **'Counter se hatayein'**
  String get itemArchive;

  /// No description provided for @itemArchived.
  ///
  /// In ur, this message translates to:
  /// **'Item hata diya gaya'**
  String get itemArchived;

  /// No description provided for @itemSaved.
  ///
  /// In ur, this message translates to:
  /// **'Item save ho gaya'**
  String get itemSaved;

  /// No description provided for @itemInStock.
  ///
  /// In ur, this message translates to:
  /// **'{qty} {unit} mojood'**
  String itemInStock(String qty, String unit);

  /// No description provided for @itemLowStock.
  ///
  /// In ur, this message translates to:
  /// **'Stock kam hai'**
  String get itemLowStock;

  /// No description provided for @partiesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Gahak'**
  String get partiesTitle;

  /// No description provided for @partiesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi gahak nahi'**
  String get partiesEmpty;

  /// No description provided for @partiesEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar likhne ke liye gahak daalein'**
  String get partiesEmptyHint;

  /// No description provided for @partiesAdd.
  ///
  /// In ur, this message translates to:
  /// **'Naya gahak'**
  String get partiesAdd;

  /// No description provided for @partyName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get partyName;

  /// No description provided for @partyPhone.
  ///
  /// In ur, this message translates to:
  /// **'Phone'**
  String get partyPhone;

  /// No description provided for @partyOpeningBalance.
  ///
  /// In ur, this message translates to:
  /// **'Purana baqaya'**
  String get partyOpeningBalance;

  /// No description provided for @partyCreditLimit.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd'**
  String get partyCreditLimit;

  /// No description provided for @partyOwes.
  ///
  /// In ur, this message translates to:
  /// **'{amount} udhaar'**
  String partyOwes(String amount);

  /// No description provided for @partySettled.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab saaf'**
  String get partySettled;

  /// No description provided for @salesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Farokht'**
  String get salesTitle;

  /// No description provided for @salesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi bill nahi bana'**
  String get salesEmpty;

  /// No description provided for @salesEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Pehla bill banayein, yahan aa jayega'**
  String get salesEmptyHint;

  /// No description provided for @salesPaid.
  ///
  /// In ur, this message translates to:
  /// **'Ada shuda'**
  String get salesPaid;

  /// No description provided for @salesUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Baqaya {amount}'**
  String salesUdhaar(String amount);

  /// No description provided for @salesVoided.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh'**
  String get salesVoided;

  /// No description provided for @receiptTitle.
  ///
  /// In ur, this message translates to:
  /// **'Bill {docNo}'**
  String receiptTitle(String docNo);

  /// No description provided for @receiptSharePdf.
  ///
  /// In ur, this message translates to:
  /// **'PDF bhejein'**
  String get receiptSharePdf;

  /// No description provided for @receiptPrint.
  ///
  /// In ur, this message translates to:
  /// **'Printer par bhejein'**
  String get receiptPrint;

  /// No description provided for @receiptPreview.
  ///
  /// In ur, this message translates to:
  /// **'Kaisa chhapega'**
  String get receiptPreview;

  /// No description provided for @receiptPaper80.
  ///
  /// In ur, this message translates to:
  /// **'80mm'**
  String get receiptPaper80;

  /// No description provided for @receiptPaper58.
  ///
  /// In ur, this message translates to:
  /// **'58mm'**
  String get receiptPaper58;

  /// No description provided for @receiptReprint.
  ///
  /// In ur, this message translates to:
  /// **'Dobara print'**
  String get receiptReprint;

  /// No description provided for @receiptNoPrinter.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi printer set nahi. Preview dekh sakte hain aur PDF bhej sakte hain.'**
  String get receiptNoPrinter;

  /// No description provided for @settingsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In ur, this message translates to:
  /// **'Zaban'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageRomanUrdu.
  ///
  /// In ur, this message translates to:
  /// **'Roman Urdu'**
  String get settingsLanguageRomanUrdu;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In ur, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsTheme.
  ///
  /// In ur, this message translates to:
  /// **'Roshni'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In ur, this message translates to:
  /// **'Phone jaisa'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ur, this message translates to:
  /// **'Safaid'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ur, this message translates to:
  /// **'Kaala'**
  String get settingsThemeDark;

  /// No description provided for @settingsShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukan ki tafseel'**
  String get settingsShop;

  /// No description provided for @settingsPayment.
  ///
  /// In ur, this message translates to:
  /// **'Paisay lene ki tafseel'**
  String get settingsPayment;

  /// No description provided for @settingsRaastAlias.
  ///
  /// In ur, this message translates to:
  /// **'Raast alias (mobile number)'**
  String get settingsRaastAlias;

  /// No description provided for @settingsBankName.
  ///
  /// In ur, this message translates to:
  /// **'Bank ka naam'**
  String get settingsBankName;

  /// No description provided for @settingsAccountTitle.
  ///
  /// In ur, this message translates to:
  /// **'Account ka naam'**
  String get settingsAccountTitle;

  /// No description provided for @settingsIban.
  ///
  /// In ur, this message translates to:
  /// **'IBAN'**
  String get settingsIban;

  /// No description provided for @settingsPaymentNote.
  ///
  /// In ur, this message translates to:
  /// **'Yeh sirf bill par chhapega taake gahak khud bhej sake. App na paisay leti hai na bhejti hai, is liye koi bank account jodne ki zaroorat nahi.'**
  String get settingsPaymentNote;

  /// No description provided for @settingsQrNote.
  ///
  /// In ur, this message translates to:
  /// **'Hum apni taraf se koi payment QR nahi banate. State Bank ke qanoon ke mutabiq QR sirf licensed banks aur payment companies bana sakti hain. Agar aap ke bank ne aap ko QR diya hai to us ki tasveer yahan laga dein.'**
  String get settingsQrNote;

  /// No description provided for @settingsDataHealth.
  ///
  /// In ur, this message translates to:
  /// **'Data ki sehat'**
  String get settingsDataHealth;

  /// No description provided for @settingsDataHealthOk.
  ///
  /// In ur, this message translates to:
  /// **'Sab theek hai'**
  String get settingsDataHealthOk;

  /// No description provided for @settingsDataHealthProblem.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 masla mila} other{{count} masle mile}}'**
  String settingsDataHealthProblem(int count);

  /// No description provided for @settingsDataHealthCheck.
  ///
  /// In ur, this message translates to:
  /// **'Abhi check karein'**
  String get settingsDataHealthCheck;

  /// No description provided for @settingsAbout.
  ///
  /// In ur, this message translates to:
  /// **'App ke baare mein'**
  String get settingsAbout;

  /// No description provided for @settingsAboutBody.
  ///
  /// In ur, this message translates to:
  /// **'Sab kuch isi phone mein. Na server, na account, na internet ki zaroorat.'**
  String get settingsAboutBody;

  /// No description provided for @emptyNoResults.
  ///
  /// In ur, this message translates to:
  /// **'Kuch nahi mila'**
  String get emptyNoResults;

  /// No description provided for @emptyNoResultsHint.
  ///
  /// In ur, this message translates to:
  /// **'Doosre lafz se talash karein'**
  String get emptyNoResultsHint;

  /// No description provided for @errorTitle.
  ///
  /// In ur, this message translates to:
  /// **'Ruk gaya'**
  String get errorTitle;

  /// No description provided for @errorNothingWasSaved.
  ///
  /// In ur, this message translates to:
  /// **'Fikar na karein - kuch bhi galat save nahi hua.'**
  String get errorNothingWasSaved;

  /// Screen-reader rendering of a money cell.
  ///
  /// In ur, this message translates to:
  /// **'Rupees {amount}'**
  String a11yRupees(String amount);

  /// Screen-reader rendering of a negative money cell.
  ///
  /// In ur, this message translates to:
  /// **'{amount} baqaya'**
  String a11yOwing(String amount);

  /// Screen-reader label on a loading skeleton.
  ///
  /// In ur, this message translates to:
  /// **'Khul raha hai'**
  String get a11yLoading;

  /// Shown when the database will not open.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab khul nahi saka'**
  String get errorStartupTitle;

  /// Reassurance under the startup failure title.
  ///
  /// In ur, this message translates to:
  /// **'Kuch zaya nahi hua. App band kar ke dobara kholein. Agar phir bhi yehi masla rahe to apni aakhri backup se wapas layein.'**
  String get errorStartupBody;

  /// Shown when Android refused a permission the screen needs.
  ///
  /// In ur, this message translates to:
  /// **'Ijazat nahi mili'**
  String get permissionDeniedTitle;

  /// What to do about a refused permission.
  ///
  /// In ur, this message translates to:
  /// **'Yeh kaam karne ke liye phone ki settings mein is app ko ijazat deni hogi.'**
  String get permissionDeniedBody;

  /// Button that opens the OS app-settings page.
  ///
  /// In ur, this message translates to:
  /// **'Phone ki settings kholein'**
  String get permissionOpenSettings;

  /// Shown when every payment account has been archived.
  ///
  /// In ur, this message translates to:
  /// **'Paisay rakhne ka koi khata nahi mila. Settings mein cash khata dobara chalu karein.'**
  String get tenderNoAccount;

  /// Body of the archive-item confirmation dialog.
  ///
  /// In ur, this message translates to:
  /// **'Yeh item counter par nazar nahi aayega. Purane bill jaise the waise hi rahenge.'**
  String get itemArchiveConfirm;

  /// Street address of the shop.
  ///
  /// In ur, this message translates to:
  /// **'Pata'**
  String get settingsAddress;

  /// Whether the shop holds an STRN.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax mein registered hoon'**
  String get settingsTaxRegistered;

  /// Explains s.3(9) STA in plain words.
  ///
  /// In ur, this message translates to:
  /// **'Zyada tar kiryana dukanein registered nahi hotin - bijli ke bill mein sales tax jama ho jata hai. Agar aap ke paas STRN hai tab hi yeh chalu karein.'**
  String get settingsTaxRegisteredNote;

  /// Button on the startup failure screen that opens the restore flow.
  ///
  /// In ur, this message translates to:
  /// **'Backup se wapas layein'**
  String get errorStartupRecover;

  /// Honest note that restore is not built yet.
  ///
  /// In ur, this message translates to:
  /// **'Backup se wapas lana M5 mein aayega. Abhi ke liye app band kar ke dobara kholein.'**
  String get errorStartupNotReady;

  /// Shown once at startup when the health check found something.
  ///
  /// In ur, this message translates to:
  /// **'Data mein {count, plural, =1{1 masla} other{{count} masle}} mila. Settings mein dekh lein.'**
  String healthWarning(int count);

  /// No description provided for @stockAdjustTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock theek karein'**
  String get stockAdjustTitle;

  /// No description provided for @stockAdjustCounted.
  ///
  /// In ur, this message translates to:
  /// **'Ginti ke baad kitna hai'**
  String get stockAdjustCounted;

  /// No description provided for @stockAdjustCurrent.
  ///
  /// In ur, this message translates to:
  /// **'Abhi ledger kehta hai'**
  String get stockAdjustCurrent;

  /// No description provided for @stockAdjustReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah'**
  String get stockAdjustReason;

  /// No description provided for @stockAdjustReasonHint.
  ///
  /// In ur, this message translates to:
  /// **'Mahana ginti, toot gaya, chori'**
  String get stockAdjustReasonHint;

  /// No description provided for @stockAdjustSave.
  ///
  /// In ur, this message translates to:
  /// **'Theek karein'**
  String get stockAdjustSave;

  /// No description provided for @stockAdjustDone.
  ///
  /// In ur, this message translates to:
  /// **'Stock theek ho gaya'**
  String get stockAdjustDone;

  /// No description provided for @stockAdjustNeedsReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah likhna zaroori hai'**
  String get stockAdjustNeedsReason;

  /// No description provided for @stockAdjustWriteOff.
  ///
  /// In ur, this message translates to:
  /// **'Zaya hua maal'**
  String get stockAdjustWriteOff;

  /// No description provided for @stockAdjustRecount.
  ///
  /// In ur, this message translates to:
  /// **'Ginti'**
  String get stockAdjustRecount;

  /// No description provided for @stockLowTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kam stock'**
  String get stockLowTitle;

  /// No description provided for @stockLowNone.
  ///
  /// In ur, this message translates to:
  /// **'Sab theek hai'**
  String get stockLowNone;

  /// No description provided for @stockLowSubtitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh cheezein khatam hone wali hain'**
  String get stockLowSubtitle;

  /// No description provided for @stockLowFloor.
  ///
  /// In ur, this message translates to:
  /// **'Hadd: {floor}'**
  String stockLowFloor(String floor);

  /// No description provided for @itemWholesalePrice.
  ///
  /// In ur, this message translates to:
  /// **'Thok ki qeemat'**
  String get itemWholesalePrice;

  /// No description provided for @itemMrp.
  ///
  /// In ur, this message translates to:
  /// **'MRP (chhapi qeemat)'**
  String get itemMrp;

  /// No description provided for @itemHsCode.
  ///
  /// In ur, this message translates to:
  /// **'HS code'**
  String get itemHsCode;

  /// No description provided for @itemDescription.
  ///
  /// In ur, this message translates to:
  /// **'Tafseel'**
  String get itemDescription;

  /// No description provided for @itemTracksStock.
  ///
  /// In ur, this message translates to:
  /// **'Is ka stock rakhna hai'**
  String get itemTracksStock;

  /// No description provided for @itemTracksStockOff.
  ///
  /// In ur, this message translates to:
  /// **'Service ya kharcha — stock nahi'**
  String get itemTracksStockOff;

  /// No description provided for @itemMoreFields.
  ///
  /// In ur, this message translates to:
  /// **'Aur tafseel'**
  String get itemMoreFields;

  /// No description provided for @settingsPrinter.
  ///
  /// In ur, this message translates to:
  /// **'Printer'**
  String get settingsPrinter;

  /// No description provided for @printerTitle.
  ///
  /// In ur, this message translates to:
  /// **'Printer set karein'**
  String get printerTitle;

  /// No description provided for @printerNone.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi printer nahi chuna.'**
  String get printerNone;

  /// No description provided for @printerHowItConnects.
  ///
  /// In ur, this message translates to:
  /// **'Printer kaise juda hai'**
  String get printerHowItConnects;

  /// No description provided for @printerViaLan.
  ///
  /// In ur, this message translates to:
  /// **'Wi-Fi par (LAN)'**
  String get printerViaLan;

  /// No description provided for @printerViaBluetooth.
  ///
  /// In ur, this message translates to:
  /// **'Bluetooth'**
  String get printerViaBluetooth;

  /// No description provided for @printerViaUsb.
  ///
  /// In ur, this message translates to:
  /// **'USB taar'**
  String get printerViaUsb;

  /// No description provided for @printerNotOnThisPhone.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par nahi chal sakta'**
  String get printerNotOnThisPhone;

  /// No description provided for @printerLooking.
  ///
  /// In ur, this message translates to:
  /// **'Printer dhoond rahe hain...'**
  String get printerLooking;

  /// No description provided for @printerNoneFound.
  ///
  /// In ur, this message translates to:
  /// **'Koi printer nahi mila. Printer chalu hai? Wi-Fi ya Bluetooth juda hai?'**
  String get printerNoneFound;

  /// No description provided for @printerSearchAgain.
  ///
  /// In ur, this message translates to:
  /// **'Dobara dhoondein'**
  String get printerSearchAgain;

  /// No description provided for @printerAddress.
  ///
  /// In ur, this message translates to:
  /// **'Printer ka pata'**
  String get printerAddress;

  /// No description provided for @printerAddressHint.
  ///
  /// In ur, this message translates to:
  /// **'192.168.1.50:9100'**
  String get printerAddressHint;

  /// No description provided for @printerAddressNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Pata likhna zaroori hai.'**
  String get printerAddressNeeded;

  /// No description provided for @printerWidth.
  ///
  /// In ur, this message translates to:
  /// **'Kagaz ki chaurai'**
  String get printerWidth;

  /// ESC/POS has no query for column width and 80mm printers ship in both 42 and 48. The shopkeeper has to look at paper.
  ///
  /// In ur, this message translates to:
  /// **'Test print nikaal kar dekhein. Jo lakeer poori ek qatar mein aaye, wahi sahi hai.'**
  String get printerWidthHelp;

  /// No description provided for @printerColumns32.
  ///
  /// In ur, this message translates to:
  /// **'32 (58mm)'**
  String get printerColumns32;

  /// No description provided for @printerColumns42.
  ///
  /// In ur, this message translates to:
  /// **'42 (80mm)'**
  String get printerColumns42;

  /// No description provided for @printerColumns48.
  ///
  /// In ur, this message translates to:
  /// **'48 (80mm)'**
  String get printerColumns48;

  /// No description provided for @printerTestPrint.
  ///
  /// In ur, this message translates to:
  /// **'Test print nikaalein'**
  String get printerTestPrint;

  /// No description provided for @printerTestSent.
  ///
  /// In ur, this message translates to:
  /// **'Test print bhej diya. Kagaz dekh lein.'**
  String get printerTestSent;

  /// No description provided for @printerCopies.
  ///
  /// In ur, this message translates to:
  /// **'Kitni copy'**
  String get printerCopies;

  /// No description provided for @printerDrawer.
  ///
  /// In ur, this message translates to:
  /// **'Cash sale par draaz kholein'**
  String get printerDrawer;

  /// No description provided for @printerSave.
  ///
  /// In ur, this message translates to:
  /// **'Printer save karein'**
  String get printerSave;

  /// No description provided for @printerForget.
  ///
  /// In ur, this message translates to:
  /// **'Yeh printer hata dein'**
  String get printerForget;

  /// No description provided for @printerSaved.
  ///
  /// In ur, this message translates to:
  /// **'Printer save ho gaya.'**
  String get printerSaved;

  /// No description provided for @printerPrinting.
  ///
  /// In ur, this message translates to:
  /// **'Print ho raha hai...'**
  String get printerPrinting;

  /// No description provided for @printerDone.
  ///
  /// In ur, this message translates to:
  /// **'Print ho gaya.'**
  String get printerDone;

  /// No description provided for @printerNotSent.
  ///
  /// In ur, this message translates to:
  /// **'Kuch nahi chhapa. Dobara koshish kar sakte hain.'**
  String get printerNotSent;

  /// Paper has already moved. Never auto-retried.
  ///
  /// In ur, this message translates to:
  /// **'Adha bill chhap kar ruk gaya. Kagaz dekh kar khud faisla karein.'**
  String get printerPartial;

  /// Shown when a print job row is still `sending`: the app was killed mid-print and paper may already have moved.
  ///
  /// In ur, this message translates to:
  /// **'Is bill ka print pehle nikla tha ya nahi, pata nahi chala. Kagaz dekh lein.'**
  String get printerUnknownAsk;

  /// No description provided for @printerPrintAgain.
  ///
  /// In ur, this message translates to:
  /// **'Phir bhi print karein'**
  String get printerPrintAgain;

  /// No description provided for @printerAlreadyPrinted.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill pehle print ho chuka hai.'**
  String get printerAlreadyPrinted;

  /// No description provided for @labelTitle.
  ///
  /// In ur, this message translates to:
  /// **'Sticker chhapein'**
  String get labelTitle;

  /// No description provided for @labelCopies.
  ///
  /// In ur, this message translates to:
  /// **'Kitne sticker'**
  String get labelCopies;

  /// No description provided for @labelPrint.
  ///
  /// In ur, this message translates to:
  /// **'Sticker chhapein'**
  String get labelPrint;

  /// A label needs something a scanner can read back; without a code there is nothing to print.
  ///
  /// In ur, this message translates to:
  /// **'Is cheez ka koi code nahi. Pehle barcode ya code likhein.'**
  String get labelNoCode;

  /// No description provided for @labelNoPrinter.
  ///
  /// In ur, this message translates to:
  /// **'Pehle printer set karein.'**
  String get labelNoPrinter;

  /// No description provided for @labelSent.
  ///
  /// In ur, this message translates to:
  /// **'Sticker printer par bhej diye.'**
  String get labelSent;

  /// No description provided for @labelPreview.
  ///
  /// In ur, this message translates to:
  /// **'Sticker par yeh aayega'**
  String get labelPreview;

  /// No description provided for @historyTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock ki tafseel'**
  String get historyTitle;

  /// No description provided for @historyNone.
  ///
  /// In ur, this message translates to:
  /// **'Abhi tak koi harkat nahi'**
  String get historyNone;

  /// No description provided for @historyOpening.
  ///
  /// In ur, this message translates to:
  /// **'Shuruaati stock'**
  String get historyOpening;

  /// No description provided for @historySale.
  ///
  /// In ur, this message translates to:
  /// **'Bika'**
  String get historySale;

  /// No description provided for @historySaleReturn.
  ///
  /// In ur, this message translates to:
  /// **'Wapas aaya'**
  String get historySaleReturn;

  /// No description provided for @historyPurchase.
  ///
  /// In ur, this message translates to:
  /// **'Khareeda'**
  String get historyPurchase;

  /// No description provided for @historyAdjustment.
  ///
  /// In ur, this message translates to:
  /// **'Durusti'**
  String get historyAdjustment;

  /// No description provided for @historyWastage.
  ///
  /// In ur, this message translates to:
  /// **'Zaya'**
  String get historyWastage;

  /// No description provided for @historyOther.
  ///
  /// In ur, this message translates to:
  /// **'Aur'**
  String get historyOther;

  /// No description provided for @historyBalance.
  ///
  /// In ur, this message translates to:
  /// **'Baqi: {qty}'**
  String historyBalance(Object qty);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(lookupAppStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

AppStrings lookupAppStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppStringsEn();
    case 'ur':
      return AppStringsUr();
  }

  throw FlutterError(
    'AppStrings.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
