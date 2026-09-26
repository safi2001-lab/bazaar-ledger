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

  /// No description provided for @stockSummaryValue.
  ///
  /// In ur, this message translates to:
  /// **'Stock ki qeemat'**
  String get stockSummaryValue;

  /// No description provided for @stockSummaryItems.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezein'**
  String stockSummaryItems(Object count);

  /// No description provided for @stockSummaryLow.
  ///
  /// In ur, this message translates to:
  /// **'{count} kam'**
  String stockSummaryLow(Object count);

  /// No description provided for @stockSummaryOut.
  ///
  /// In ur, this message translates to:
  /// **'{count} khatam'**
  String stockSummaryOut(Object count);

  /// A ledger balance below zero: the shop sold something it never recorded receiving. Impossible on a shelf, and a bookkeeping error a person must fix.
  ///
  /// In ur, this message translates to:
  /// **'{count} ulta'**
  String stockSummaryNegative(Object count);

  /// No description provided for @pictureAdd.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer lagayein'**
  String get pictureAdd;

  /// No description provided for @pictureChange.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer badlein'**
  String get pictureChange;

  /// No description provided for @pictureRemove.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer hatayein'**
  String get pictureRemove;

  /// No description provided for @pictureNotAnImage.
  ///
  /// In ur, this message translates to:
  /// **'Yeh tasveer nahi hai'**
  String get pictureNotAnImage;

  /// No description provided for @scanTitle.
  ///
  /// In ur, this message translates to:
  /// **'Barcode scan karein'**
  String get scanTitle;

  /// No description provided for @scanHint.
  ///
  /// In ur, this message translates to:
  /// **'Packet ka barcode camera ke saamne rakhein'**
  String get scanHint;

  /// No description provided for @scanNoCamera.
  ///
  /// In ur, this message translates to:
  /// **'Is phone mein camera nahi hai'**
  String get scanNoCamera;

  /// No description provided for @scanDenied.
  ///
  /// In ur, this message translates to:
  /// **'Camera ki ijazat nahi mili'**
  String get scanDenied;

  /// No description provided for @scanTorch.
  ///
  /// In ur, this message translates to:
  /// **'Roshni'**
  String get scanTorch;

  /// No description provided for @scanNotFound.
  ///
  /// In ur, this message translates to:
  /// **'Yeh barcode kisi cheez par nahi hai'**
  String get scanNotFound;

  /// No description provided for @scanAddNew.
  ///
  /// In ur, this message translates to:
  /// **'Nayi cheez banayein'**
  String get scanAddNew;

  /// No description provided for @khataTitle.
  ///
  /// In ur, this message translates to:
  /// **'Khata'**
  String get khataTitle;

  /// Positive means the customer owes the shop. The khata's only question.
  ///
  /// In ur, this message translates to:
  /// **'Kitna lena hai'**
  String get khataBalance;

  /// The shop is holding the customer's money: a liability, never a negative receivable.
  ///
  /// In ur, this message translates to:
  /// **'Jama shuda'**
  String get khataAdvance;

  /// No description provided for @khataOpenBills.
  ///
  /// In ur, this message translates to:
  /// **'Khule bill'**
  String get khataOpenBills;

  /// No description provided for @khataNoBills.
  ///
  /// In ur, this message translates to:
  /// **'Koi udhaar baqi nahi'**
  String get khataNoBills;

  /// No description provided for @khataNoBillsHint.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ka poora hisaab saaf hai'**
  String get khataNoBillsHint;

  /// No description provided for @khataReceive.
  ///
  /// In ur, this message translates to:
  /// **'Paisay wasool karein'**
  String get khataReceive;

  /// No description provided for @khataDetails.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ki tafseel'**
  String get khataDetails;

  /// No description provided for @khataCreditLimitOver.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd se ziyada'**
  String get khataCreditLimitOver;

  /// No description provided for @wasooliTitle.
  ///
  /// In ur, this message translates to:
  /// **'Paisay wasool karein'**
  String get wasooliTitle;

  /// No description provided for @wasooliAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitne paisay milay'**
  String get wasooliAmount;

  /// No description provided for @wasooliMode.
  ///
  /// In ur, this message translates to:
  /// **'Kis tarah'**
  String get wasooliMode;

  /// No description provided for @wasooliReference.
  ///
  /// In ur, this message translates to:
  /// **'Reference (marzi se)'**
  String get wasooliReference;

  /// No description provided for @wasooliChequeNo.
  ///
  /// In ur, this message translates to:
  /// **'Cheque number'**
  String get wasooliChequeNo;

  /// No description provided for @wasooliChequeBank.
  ///
  /// In ur, this message translates to:
  /// **'Bank ka naam'**
  String get wasooliChequeBank;

  /// Which bills this payment clears, computed by the same function that will write it. A preview that could disagree with the write is worse than none.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill saaf honge'**
  String get wasooliSettles;

  /// No description provided for @wasooliSettlesNone.
  ///
  /// In ur, this message translates to:
  /// **'Koi khula bill nahi — yeh raqam jama ho jayegi'**
  String get wasooliSettlesNone;

  /// What no open bill absorbed. Ordinary in a shop that takes standing orders.
  ///
  /// In ur, this message translates to:
  /// **'Jama (advance)'**
  String get wasooliOnAccount;

  /// No description provided for @wasooliSave.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli save karein'**
  String get wasooliSave;

  /// No description provided for @wasooliSaved.
  ///
  /// In ur, this message translates to:
  /// **'{amount} wasool ho gaye'**
  String wasooliSaved(String amount);

  /// No description provided for @wasooliAmountRequired.
  ///
  /// In ur, this message translates to:
  /// **'Raqam likhein'**
  String get wasooliAmountRequired;

  /// No description provided for @wasooliChequeNoRequired.
  ///
  /// In ur, this message translates to:
  /// **'Cheque number likhein'**
  String get wasooliChequeNoRequired;

  /// A credit limit that blocks nothing is decoration. Shown at the tender sheet, where the shop is about to hand over goods, and overridable by name because it is their shop.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd se ziyada'**
  String get tenderOverLimit;

  /// No description provided for @tenderOverLimitDetail.
  ///
  /// In ur, this message translates to:
  /// **'Hadd {limit} hai. Is bill ke baad {after} ho jayega.'**
  String tenderOverLimitDetail(String limit, String after);

  /// No description provided for @tenderOverLimitAllow.
  ///
  /// In ur, this message translates to:
  /// **'Phir bhi udhaar dein'**
  String get tenderOverLimitAllow;

  /// No description provided for @khataRemind.
  ///
  /// In ur, this message translates to:
  /// **'Yaad dilayein'**
  String get khataRemind;

  /// No description provided for @khataRemindNoPhone.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ka number nahi hai'**
  String get khataRemindNoPhone;

  /// No description provided for @khataRemindNothingOwed.
  ///
  /// In ur, this message translates to:
  /// **'Kuch baqi nahi hai'**
  String get khataRemindNothingOwed;

  /// No description provided for @chaseTitle.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar wasooli'**
  String get chaseTitle;

  /// No description provided for @chaseEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Kisi ka udhaar baqi nahi'**
  String get chaseEmpty;

  /// No description provided for @chaseEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Sab hisaab saaf hai'**
  String get chaseEmptyHint;

  /// No description provided for @chaseTotal.
  ///
  /// In ur, this message translates to:
  /// **'Kul udhaar'**
  String get chaseTotal;

  /// Everything past the shop's normal fortnightly cycle. Deliberately excludes the current bucket, or every shop looks like it is in trouble every day.
  ///
  /// In ur, this message translates to:
  /// **'Der se baqi'**
  String get chaseOverdue;

  /// No description provided for @chaseSince.
  ///
  /// In ur, this message translates to:
  /// **'{days} din se'**
  String chaseSince(int days);

  /// No description provided for @chaseBills.
  ///
  /// In ur, this message translates to:
  /// **'{count} bill'**
  String chaseBills(int count);

  /// No description provided for @chaseAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab'**
  String get chaseAll;

  /// No description provided for @khataHistory.
  ///
  /// In ur, this message translates to:
  /// **'Purana hisaab'**
  String get khataHistory;

  /// No description provided for @khataHistoryEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi len-den nahi'**
  String get khataHistoryEmpty;

  /// No description provided for @homePurchases.
  ///
  /// In ur, this message translates to:
  /// **'Kharidari'**
  String get homePurchases;

  /// No description provided for @purchaseTitle.
  ///
  /// In ur, this message translates to:
  /// **'Nayi kharidari'**
  String get purchaseTitle;

  /// No description provided for @purchaseSupplier.
  ///
  /// In ur, this message translates to:
  /// **'Supplier chunein'**
  String get purchaseSupplier;

  /// No description provided for @purchaseSupplierRequired.
  ///
  /// In ur, this message translates to:
  /// **'Supplier chunna zaroori hai'**
  String get purchaseSupplierRequired;

  /// No description provided for @purchaseAddItem.
  ///
  /// In ur, this message translates to:
  /// **'Cheez shamil karein'**
  String get purchaseAddItem;

  /// No description provided for @purchaseNoLines.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi cheez nahi'**
  String get purchaseNoLines;

  /// No description provided for @purchaseNoLinesHint.
  ///
  /// In ur, this message translates to:
  /// **'Jo maal aaya hai woh shamil karein'**
  String get purchaseNoLinesHint;

  /// No description provided for @purchaseCost.
  ///
  /// In ur, this message translates to:
  /// **'Kharid qeemat'**
  String get purchaseCost;

  /// Delivery, labour, the rickshaw. Apportioned across the lines by value, because a margin computed against the invoice alone has never paid for delivery.
  ///
  /// In ur, this message translates to:
  /// **'Kiraya aur mazdoori'**
  String get purchaseFreight;

  /// No description provided for @purchasePaid.
  ///
  /// In ur, this message translates to:
  /// **'Abhi diye'**
  String get purchasePaid;

  /// No description provided for @purchaseBillNo.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ka bill number'**
  String get purchaseBillNo;

  /// No description provided for @purchaseGoods.
  ///
  /// In ur, this message translates to:
  /// **'Maal'**
  String get purchaseGoods;

  /// No description provided for @purchaseTotal.
  ///
  /// In ur, this message translates to:
  /// **'Kul'**
  String get purchaseTotal;

  /// No description provided for @purchaseOwing.
  ///
  /// In ur, this message translates to:
  /// **'Baqi'**
  String get purchaseOwing;

  /// No description provided for @purchaseSave.
  ///
  /// In ur, this message translates to:
  /// **'Kharidari save karein'**
  String get purchaseSave;

  /// No description provided for @purchaseSaved.
  ///
  /// In ur, this message translates to:
  /// **'Kharidari {docNo} save ho gayi'**
  String purchaseSaved(String docNo);

  /// No description provided for @purchaseNewAverage.
  ///
  /// In ur, this message translates to:
  /// **'Nayi lagat {rate}'**
  String purchaseNewAverage(String rate);

  /// No description provided for @purchasePaidTooMuch.
  ///
  /// In ur, this message translates to:
  /// **'Bill se ziyada nahi de sakte'**
  String get purchasePaidTooMuch;

  /// No description provided for @purchasesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kharidari'**
  String get purchasesTitle;

  /// No description provided for @purchasesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi kharidari nahi'**
  String get purchasesEmpty;

  /// No description provided for @purchasesEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Jo maal aaye us ka bill yahan likhein'**
  String get purchasesEmptyHint;

  /// No description provided for @voidTitle.
  ///
  /// In ur, this message translates to:
  /// **'Bill mansookh karein'**
  String get voidTitle;

  /// No description provided for @voidAction.
  ///
  /// In ur, this message translates to:
  /// **'Bill mansookh'**
  String get voidAction;

  /// No description provided for @voidReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah'**
  String get voidReason;

  /// No description provided for @voidReasonRequired.
  ///
  /// In ur, this message translates to:
  /// **'Wajah likhna zaroori hai'**
  String get voidReasonRequired;

  /// No description provided for @voidConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Haan, mansookh karein'**
  String get voidConfirm;

  /// Said plainly, because a shopkeeper who thinks a bill vanished will be surprised to find it in a report. Nothing is deleted; the opposite is written.
  ///
  /// In ur, this message translates to:
  /// **'Bill mit-ta nahi. Ulta ijraa likha jayega aur maal wapas shumar hoga.'**
  String get voidExplain;

  /// No description provided for @voidDone.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} mansookh ho gaya'**
  String voidDone(String docNo);

  /// No description provided for @returnTitle.
  ///
  /// In ur, this message translates to:
  /// **'Maal wapas'**
  String get returnTitle;

  /// No description provided for @returnAction.
  ///
  /// In ur, this message translates to:
  /// **'Wapas lein'**
  String get returnAction;

  /// No description provided for @returnNothingLeft.
  ///
  /// In ur, this message translates to:
  /// **'Is bill se sab kuch wapas ho chuka'**
  String get returnNothingLeft;

  /// No description provided for @returnReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah'**
  String get returnReason;

  /// No description provided for @returnReasonRequired.
  ///
  /// In ur, this message translates to:
  /// **'Wajah likhna zaroori hai'**
  String get returnReasonRequired;

  /// No description provided for @returnPickSomething.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ek cheez chunein'**
  String get returnPickSomething;

  /// No description provided for @returnRefundNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi wapas diye'**
  String get returnRefundNow;

  /// No description provided for @returnLeft.
  ///
  /// In ur, this message translates to:
  /// **'{qty} baqi'**
  String returnLeft(String qty);

  /// No description provided for @returnTotal.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi ki raqam'**
  String get returnTotal;

  /// No description provided for @returnSave.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi save karein'**
  String get returnSave;

  /// No description provided for @returnDone.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} save ho gaya'**
  String returnDone(String docNo);

  /// No description provided for @returnOnAccount.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ke khate mein jama'**
  String get returnOnAccount;

  /// No description provided for @homeExpenses.
  ///
  /// In ur, this message translates to:
  /// **'Kharcha'**
  String get homeExpenses;

  /// No description provided for @expensesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kharchay'**
  String get expensesTitle;

  /// No description provided for @expensesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi kharcha nahi'**
  String get expensesEmpty;

  /// No description provided for @expensesEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Kiraya, bijli, tankhwah — jo paisa dukaan se bahar gaya yahan likhein'**
  String get expensesEmptyHint;

  /// No description provided for @expenseNew.
  ///
  /// In ur, this message translates to:
  /// **'Naya kharcha'**
  String get expenseNew;

  /// No description provided for @expenseHead.
  ///
  /// In ur, this message translates to:
  /// **'Kis mad mein'**
  String get expenseHead;

  /// No description provided for @expenseHeadRent.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ka kiraya'**
  String get expenseHeadRent;

  /// No description provided for @expenseHeadSalaries.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah'**
  String get expenseHeadSalaries;

  /// No description provided for @expenseHeadUtilities.
  ///
  /// In ur, this message translates to:
  /// **'Bijli, gas, pani'**
  String get expenseHeadUtilities;

  /// No description provided for @expenseHeadFreight.
  ///
  /// In ur, this message translates to:
  /// **'Maal bardari'**
  String get expenseHeadFreight;

  /// No description provided for @expenseHeadMisc.
  ///
  /// In ur, this message translates to:
  /// **'Mutafarriq'**
  String get expenseHeadMisc;

  /// No description provided for @expenseAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam'**
  String get expenseAmount;

  /// No description provided for @expenseNote.
  ///
  /// In ur, this message translates to:
  /// **'Kis cheez ke liye'**
  String get expenseNote;

  /// No description provided for @expenseNoteRequired.
  ///
  /// In ur, this message translates to:
  /// **'Likhein yeh kharcha kis cheez ka tha'**
  String get expenseNoteRequired;

  /// No description provided for @expensePaidNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi diye'**
  String get expensePaidNow;

  /// No description provided for @expensePayLater.
  ///
  /// In ur, this message translates to:
  /// **'Baad mein dena hai'**
  String get expensePayLater;

  /// No description provided for @expensePaidFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kahan se diye'**
  String get expensePaidFrom;

  /// No description provided for @expensePayee.
  ///
  /// In ur, this message translates to:
  /// **'Kis ko dena hai'**
  String get expensePayee;

  /// No description provided for @expensePayeeRequired.
  ///
  /// In ur, this message translates to:
  /// **'Batayein yeh kis ko dena hai'**
  String get expensePayeeRequired;

  /// No description provided for @expenseSave.
  ///
  /// In ur, this message translates to:
  /// **'Kharcha save karein'**
  String get expenseSave;

  /// No description provided for @expenseSaved.
  ///
  /// In ur, this message translates to:
  /// **'Kharcha {docNo} save ho gaya'**
  String expenseSaved(String docNo);

  /// No description provided for @expenseOwedTo.
  ///
  /// In ur, this message translates to:
  /// **'{name} ko dena hai'**
  String expenseOwedTo(String name);

  /// No description provided for @partyWeOwe.
  ///
  /// In ur, this message translates to:
  /// **'{amount} dena hai'**
  String partyWeOwe(String amount);

  /// No description provided for @khataPayable.
  ///
  /// In ur, this message translates to:
  /// **'Kitna dena hai'**
  String get khataPayable;

  /// No description provided for @khataPay.
  ///
  /// In ur, this message translates to:
  /// **'Paisay dein'**
  String get khataPay;

  /// No description provided for @khataOpenPayables.
  ///
  /// In ur, this message translates to:
  /// **'Jin ka dena baqi hai'**
  String get khataOpenPayables;

  /// No description provided for @khataNoPayables.
  ///
  /// In ur, this message translates to:
  /// **'Is supplier ka sab chuka diya'**
  String get khataNoPayables;

  /// No description provided for @payTitle.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ko paisay dein'**
  String get payTitle;

  /// No description provided for @payAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitne diye'**
  String get payAmount;

  /// No description provided for @paySettles.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill chuk jayenge'**
  String get paySettles;

  /// No description provided for @payTooMuch.
  ///
  /// In ur, this message translates to:
  /// **'Sirf {amount} dena hai'**
  String payTooMuch(String amount);

  /// No description provided for @paySave.
  ///
  /// In ur, this message translates to:
  /// **'Payment save karein'**
  String get paySave;

  /// No description provided for @paySaved.
  ///
  /// In ur, this message translates to:
  /// **'{amount} de diye'**
  String paySaved(String amount);

  /// No description provided for @backupTitle.
  ///
  /// In ur, this message translates to:
  /// **'Backup'**
  String get backupTitle;

  /// No description provided for @backupExplain.
  ///
  /// In ur, this message translates to:
  /// **'Poora hisaab ek file mein band ho jata hai jo sirf aap ke password se khulti hai. Isay WhatsApp par khud ko, Google Drive ya kisi aur phone par rakh lein. Phone gum ho jaye to isi se sab wapas aayega.'**
  String get backupExplain;

  /// No description provided for @backupLast.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri backup: {when}'**
  String backupLast(String when);

  /// No description provided for @backupNever.
  ///
  /// In ur, this message translates to:
  /// **'Abhi tak koi backup nahi banaya'**
  String get backupNever;

  /// No description provided for @backupPassphrase.
  ///
  /// In ur, this message translates to:
  /// **'Backup ka password'**
  String get backupPassphrase;

  /// No description provided for @backupPassphraseAgain.
  ///
  /// In ur, this message translates to:
  /// **'Password dobara likhein'**
  String get backupPassphraseAgain;

  /// No description provided for @backupPassphraseHint.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam 8 huroof. Yeh password bhool gaye to backup kabhi nahi khulega — kahin likh kar rakhein.'**
  String get backupPassphraseHint;

  /// No description provided for @backupPassphraseShort.
  ///
  /// In ur, this message translates to:
  /// **'Password kam az kam 8 huroof ka ho'**
  String get backupPassphraseShort;

  /// No description provided for @backupPassphraseMismatch.
  ///
  /// In ur, this message translates to:
  /// **'Dono password ek jaise nahi'**
  String get backupPassphraseMismatch;

  /// No description provided for @backupMake.
  ///
  /// In ur, this message translates to:
  /// **'Backup banayein'**
  String get backupMake;

  /// No description provided for @backupMade.
  ///
  /// In ur, this message translates to:
  /// **'Backup ban gaya — ab isay mehfooz jagah bhejein'**
  String get backupMade;

  /// No description provided for @backupRestore.
  ///
  /// In ur, this message translates to:
  /// **'Backup se wapas layein'**
  String get backupRestore;

  /// No description provided for @restoreTitle.
  ///
  /// In ur, this message translates to:
  /// **'Backup se wapas layein'**
  String get restoreTitle;

  /// No description provided for @restorePick.
  ///
  /// In ur, this message translates to:
  /// **'Backup file chunein'**
  String get restorePick;

  /// No description provided for @restoreMadeOn.
  ///
  /// In ur, this message translates to:
  /// **'Yeh backup {when} ko bana tha'**
  String restoreMadeOn(String when);

  /// No description provided for @restoreOpen.
  ///
  /// In ur, this message translates to:
  /// **'Backup kholein'**
  String get restoreOpen;

  /// No description provided for @restoreFound.
  ///
  /// In ur, this message translates to:
  /// **'Is backup mein'**
  String get restoreFound;

  /// No description provided for @restoreCounts.
  ///
  /// In ur, this message translates to:
  /// **'{bills} bill · {parties} gahak/supplier · {items} cheezein'**
  String restoreCounts(String bills, String parties, String items);

  /// No description provided for @restoreLastEntry.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri entry: {date}'**
  String restoreLastEntry(String date);

  /// No description provided for @restoreWarning.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par jo hisaab abhi hai us ki jagah yeh aa jayega. Mojooda hisaab mitaya nahi jayega, alag rakh diya jayega.'**
  String get restoreWarning;

  /// No description provided for @restoreConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Haan, wapas layein'**
  String get restoreConfirm;

  /// No description provided for @restoreRestarting.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab wapas aa raha hai…'**
  String get restoreRestarting;

  /// No description provided for @setupRestore.
  ///
  /// In ur, this message translates to:
  /// **'Pehle se hisaab hai? Backup se wapas layein'**
  String get setupRestore;

  /// No description provided for @partyArchive.
  ///
  /// In ur, this message translates to:
  /// **'Khate se hatayein'**
  String get partyArchive;

  /// No description provided for @partyArchiveConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh naam khate ki list mein nazar nahi aayega. Purana hisaab jaisa tha waisa rahega, aur Settings mein \'Hatayi hui cheezein\' se wapas laya ja sakta hai.'**
  String get partyArchiveConfirm;

  /// No description provided for @partyArchived.
  ///
  /// In ur, this message translates to:
  /// **'Khate se hata diya gaya'**
  String get partyArchived;

  /// No description provided for @recycleTitle.
  ///
  /// In ur, this message translates to:
  /// **'Hatayi hui cheezein'**
  String get recycleTitle;

  /// No description provided for @recycleItems.
  ///
  /// In ur, this message translates to:
  /// **'Cheezein'**
  String get recycleItems;

  /// No description provided for @recycleParties.
  ///
  /// In ur, this message translates to:
  /// **'Gahak aur supplier'**
  String get recycleParties;

  /// No description provided for @recycleEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Kuch hataya nahi gaya'**
  String get recycleEmpty;

  /// No description provided for @recycleRestore.
  ///
  /// In ur, this message translates to:
  /// **'Wapas layein'**
  String get recycleRestore;

  /// No description provided for @recycleRestored.
  ///
  /// In ur, this message translates to:
  /// **'{name} wapas aa gaya'**
  String recycleRestored(String name);

  /// No description provided for @purchaseReturnTitle.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ko maal wapas'**
  String get purchaseReturnTitle;

  /// No description provided for @purchaseReturnRefund.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ne abhi wapas diye'**
  String get purchaseReturnRefund;

  /// No description provided for @chequeDue.
  ///
  /// In ur, this message translates to:
  /// **'Kab jama ho sakta hai'**
  String get chequeDue;

  /// No description provided for @chequeDueToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj'**
  String get chequeDueToday;

  /// No description provided for @chequeDueInDays.
  ///
  /// In ur, this message translates to:
  /// **'{days} din baad'**
  String chequeDueInDays(String days);

  /// No description provided for @chequeDuePick.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh chunein'**
  String get chequeDuePick;

  /// No description provided for @chequeDueOn.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh: {date}'**
  String chequeDueOn(String date);

  /// No description provided for @chequeNeedsCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Cheque sirf naam wale gahak se lein — bounce hua to kis se mangenge?'**
  String get chequeNeedsCustomer;

  /// No description provided for @homeCheques.
  ///
  /// In ur, this message translates to:
  /// **'Cheque'**
  String get homeCheques;

  /// No description provided for @chequesInHand.
  ///
  /// In ur, this message translates to:
  /// **'Haath mein'**
  String get chequesInHand;

  /// No description provided for @chequesBounced.
  ///
  /// In ur, this message translates to:
  /// **'Bounce hue'**
  String get chequesBounced;

  /// No description provided for @chequesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Koi cheque haath mein nahi'**
  String get chequesEmpty;

  /// No description provided for @chequesEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli ya bill par cheque lein to yahan nazar aayega'**
  String get chequesEmptyHint;

  /// No description provided for @chequeDueTodayChip.
  ///
  /// In ur, this message translates to:
  /// **'Aaj jama karein'**
  String get chequeDueTodayChip;

  /// No description provided for @chequeDueInChip.
  ///
  /// In ur, this message translates to:
  /// **'{days} din baqi'**
  String chequeDueInChip(String days);

  /// No description provided for @chequeOverdueChip.
  ///
  /// In ur, this message translates to:
  /// **'{days} din guzar gaye'**
  String chequeOverdueChip(String days);

  /// No description provided for @chequeNoDate.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh nahi'**
  String get chequeNoDate;

  /// No description provided for @chequeAtBank.
  ///
  /// In ur, this message translates to:
  /// **'Bank mein'**
  String get chequeAtBank;

  /// No description provided for @chequeDeposit.
  ///
  /// In ur, this message translates to:
  /// **'Bank mein lagaya'**
  String get chequeDeposit;

  /// No description provided for @chequeClear.
  ///
  /// In ur, this message translates to:
  /// **'Clear ho gaya'**
  String get chequeClear;

  /// No description provided for @chequeBounce.
  ///
  /// In ur, this message translates to:
  /// **'Bounce ho gaya'**
  String get chequeBounce;

  /// No description provided for @chequeClearInto.
  ///
  /// In ur, this message translates to:
  /// **'Kis account mein aaya'**
  String get chequeClearInto;

  /// No description provided for @chequeBounceReason.
  ///
  /// In ur, this message translates to:
  /// **'Bank ne kya likha (marzi se)'**
  String get chequeBounceReason;

  /// No description provided for @chequeBounceWarning.
  ///
  /// In ur, this message translates to:
  /// **'{amount} phir se {name} ke khate mein chala jayega.'**
  String chequeBounceWarning(String amount, String name);

  /// No description provided for @chequeNoticeBy.
  ///
  /// In ur, this message translates to:
  /// **'489-F notice {date} tak bhejein'**
  String chequeNoticeBy(String date);

  /// No description provided for @chequeBouncedOn.
  ///
  /// In ur, this message translates to:
  /// **'Bounce: {date}'**
  String chequeBouncedOn(String date);

  /// No description provided for @chequeNotYet.
  ///
  /// In ur, this message translates to:
  /// **'Bank ise {date} se pehle nahi lega'**
  String chequeNotYet(String date);

  /// No description provided for @homeChequesDue.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheque bank le jane ka din aa gaya} other{{count} cheque bank le jane ka din aa gaya}}'**
  String homeChequesDue(int count);

  /// No description provided for @chequeNoticeTitle.
  ///
  /// In ur, this message translates to:
  /// **'489-F notice'**
  String get chequeNoticeTitle;

  /// No description provided for @chequeNoticeHint.
  ///
  /// In ur, this message translates to:
  /// **'Yeh notice aap ke hisaab se bana hai. Bhejne se pehle wakeel ko zaroor dikhayein.'**
  String get chequeNoticeHint;

  /// No description provided for @chequeNoticeShare.
  ///
  /// In ur, this message translates to:
  /// **'Notice PDF share karein'**
  String get chequeNoticeShare;

  /// No description provided for @chequeNoticeLate.
  ///
  /// In ur, this message translates to:
  /// **'Notice ki muddat {date} ko guzar gayi'**
  String chequeNoticeLate(String date);

  /// No description provided for @tenderChequeBounced.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ka cheque bounce ho chuka hai'**
  String get tenderChequeBounced;

  /// No description provided for @tenderChequeBouncedDetail.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheque wapas aaya} other{{count} cheque wapas aaye}}, aur {owed} ab bhi baqi hain. Naqad lein, ya soch kar udhaar dein.'**
  String tenderChequeBouncedDetail(int count, String owed);

  /// No description provided for @tenderChequeBouncedAllow.
  ///
  /// In ur, this message translates to:
  /// **'Phir bhi dein'**
  String get tenderChequeBouncedAllow;

  /// No description provided for @khataChequeBounced.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheque bounce hua} other{{count} cheque bounce hue}}'**
  String khataChequeBounced(int count);

  /// No description provided for @chequeBounceFee.
  ///
  /// In ur, this message translates to:
  /// **'Bank ki fee, agar kaati (marzi se)'**
  String get chequeBounceFee;

  /// No description provided for @chequeBounceFeeFrom.
  ///
  /// In ur, this message translates to:
  /// **'Fee kis account se gayi'**
  String get chequeBounceFeeFrom;

  /// No description provided for @chequeBounceFeeNote.
  ///
  /// In ur, this message translates to:
  /// **'Cheque {chequeNo} ({name}) bounce ki bank fee'**
  String chequeBounceFeeNote(String chequeNo, String name);

  /// No description provided for @chequeBounceFeeFailed.
  ///
  /// In ur, this message translates to:
  /// **'Bounce save ho gaya, lekin bank fee save nahi hui: {error}'**
  String chequeBounceFeeFailed(String error);

  /// No description provided for @payByCheque.
  ///
  /// In ur, this message translates to:
  /// **'Cheque se diya'**
  String get payByCheque;

  /// No description provided for @payChequeDrawnOn.
  ///
  /// In ur, this message translates to:
  /// **'Kis bank account ka cheque'**
  String get payChequeDrawnOn;

  /// No description provided for @chequesIssued.
  ///
  /// In ur, this message translates to:
  /// **'Humare diye hue cheque'**
  String get chequesIssued;

  /// No description provided for @chequeIssuedPresentable.
  ///
  /// In ur, this message translates to:
  /// **'Pesh ho sakta hai'**
  String get chequeIssuedPresentable;

  /// No description provided for @chequeIssuedPaid.
  ///
  /// In ur, this message translates to:
  /// **'Bank ne ada kar diya'**
  String get chequeIssuedPaid;

  /// No description provided for @chequeIssuedBounceWarning.
  ///
  /// In ur, this message translates to:
  /// **'{amount} phir se {name} ko dene honge.'**
  String chequeIssuedBounceWarning(String amount, String name);

  /// No description provided for @homeChequesIssuedDue.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} ke apne cheque {days} din mein pesh ho sakte hain — bank mein paisay rakhein'**
  String homeChequesIssuedDue(String amount, String days);

  /// No description provided for @partyPriceTier.
  ///
  /// In ur, this message translates to:
  /// **'Kis rate par bechna hai'**
  String get partyPriceTier;

  /// No description provided for @partyTierRetail.
  ///
  /// In ur, this message translates to:
  /// **'Parchoon (retail)'**
  String get partyTierRetail;

  /// No description provided for @partyTierWholesale.
  ///
  /// In ur, this message translates to:
  /// **'Thok (wholesale)'**
  String get partyTierWholesale;

  /// No description provided for @partyDiscount.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez par discount % (marzi se)'**
  String get partyDiscount;

  /// No description provided for @partyDiscountInvalid.
  ///
  /// In ur, this message translates to:
  /// **'0 se 100 ke darmiyan likhein'**
  String get partyDiscountInvalid;

  /// No description provided for @partyAddress.
  ///
  /// In ur, this message translates to:
  /// **'Pata'**
  String get partyAddress;

  /// No description provided for @partyCity.
  ///
  /// In ur, this message translates to:
  /// **'Shehar'**
  String get partyCity;

  /// No description provided for @partyCnic.
  ///
  /// In ur, this message translates to:
  /// **'CNIC (marzi se)'**
  String get partyCnic;

  /// No description provided for @homeQuotations.
  ///
  /// In ur, this message translates to:
  /// **'Quotation'**
  String get homeQuotations;

  /// No description provided for @quotationsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Quotations'**
  String get quotationsTitle;

  /// No description provided for @quotationsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi quotation nahi'**
  String get quotationsEmpty;

  /// No description provided for @quotationsEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Bill ke payment sheet par \"Quotation banayein\" dabayein'**
  String get quotationsEmptyHint;

  /// No description provided for @quotationMake.
  ///
  /// In ur, this message translates to:
  /// **'Quotation banayein'**
  String get quotationMake;

  /// No description provided for @quotationSaved.
  ///
  /// In ur, this message translates to:
  /// **'Quotation {docNo} ban gayi'**
  String quotationSaved(String docNo);

  /// No description provided for @quotationBilledAs.
  ///
  /// In ur, this message translates to:
  /// **'Bill {docNo} ban gaya'**
  String quotationBilledAs(String docNo);

  /// No description provided for @quotationExpired.
  ///
  /// In ur, this message translates to:
  /// **'Muddat guzar gayi'**
  String get quotationExpired;

  /// No description provided for @quotationOpen.
  ///
  /// In ur, this message translates to:
  /// **'Khuli hai'**
  String get quotationOpen;

  /// No description provided for @quotationValidUntil.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak'**
  String quotationValidUntil(String date);

  /// No description provided for @quotationSharePdf.
  ///
  /// In ur, this message translates to:
  /// **'PDF bhejein'**
  String get quotationSharePdf;

  /// No description provided for @quotationBill.
  ///
  /// In ur, this message translates to:
  /// **'Is se bill banayein'**
  String get quotationBill;

  /// No description provided for @quotationCounterBusy.
  ///
  /// In ur, this message translates to:
  /// **'Counter par pehle se ek bill chal raha hai. Pehle usay mukammal ya khali karein.'**
  String get quotationCounterBusy;

  /// No description provided for @quotationItemGone.
  ///
  /// In ur, this message translates to:
  /// **'Is quotation ki ek cheez ab list mein nahi. Wapas la kar dobara koshish karein.'**
  String get quotationItemGone;

  /// No description provided for @homeChallans.
  ///
  /// In ur, this message translates to:
  /// **'Challan'**
  String get homeChallans;

  /// No description provided for @challansTitle.
  ///
  /// In ur, this message translates to:
  /// **'Delivery challan'**
  String get challansTitle;

  /// No description provided for @challansEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi challan nahi'**
  String get challansEmpty;

  /// No description provided for @challansEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Maal bill se pehle bhejna ho to payment sheet par \"Challan banayein\" dabayein'**
  String get challansEmptyHint;

  /// No description provided for @challanMake.
  ///
  /// In ur, this message translates to:
  /// **'Challan banayein'**
  String get challanMake;

  /// No description provided for @challanSaved.
  ///
  /// In ur, this message translates to:
  /// **'Challan {docNo} ban gaya, maal nikal gaya'**
  String challanSaved(String docNo);

  /// No description provided for @challanNeedsCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Challan par gahak ka naam zaroori hai. Pehle gahak chunein.'**
  String get challanNeedsCustomer;

  /// No description provided for @challanUnbilled.
  ///
  /// In ur, this message translates to:
  /// **'Bill baqi hai'**
  String get challanUnbilled;

  /// No description provided for @challanCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Maal wapas aa gaya'**
  String get challanCancelled;

  /// No description provided for @challanCancel.
  ///
  /// In ur, this message translates to:
  /// **'Maal wapas aa gaya'**
  String get challanCancel;

  /// No description provided for @challanCancelReason.
  ///
  /// In ur, this message translates to:
  /// **'Challan wapas'**
  String get challanCancelReason;

  /// No description provided for @challanCancelConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Challan {docNo} ka saara maal wapas shelf par aa jaye ga. Pakka?'**
  String challanCancelConfirm(String docNo);

  /// No description provided for @chargeTitle.
  ///
  /// In ur, this message translates to:
  /// **'Khate mein charge dalein'**
  String get chargeTitle;

  /// No description provided for @chargeAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitne ka charge'**
  String get chargeAmount;

  /// No description provided for @chargeNote.
  ///
  /// In ur, this message translates to:
  /// **'Kis cheez ka (zaroori)'**
  String get chargeNote;

  /// No description provided for @chargeSave.
  ///
  /// In ur, this message translates to:
  /// **'Khate mein dalein'**
  String get chargeSave;

  /// No description provided for @chargeSaved.
  ///
  /// In ur, this message translates to:
  /// **'{amount} khate mein daal diya'**
  String chargeSaved(String amount);

  /// No description provided for @chargeNeedsAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam likhein'**
  String get chargeNeedsAmount;

  /// No description provided for @chargeNeedsNote.
  ///
  /// In ur, this message translates to:
  /// **'Likhein kis cheez ka charge hai, warna gahak nahi dega'**
  String get chargeNeedsNote;

  /// No description provided for @chargeBounceFee.
  ///
  /// In ur, this message translates to:
  /// **'Yeh fee {name} ke khate mein bhi dalein'**
  String chargeBounceFee(String name);

  /// No description provided for @chargeBounceFeeNote.
  ///
  /// In ur, this message translates to:
  /// **'Cheque {chequeNo} bounce ki bank fee'**
  String chargeBounceFeeNote(String chequeNo);

  /// No description provided for @homeReports.
  ///
  /// In ur, this message translates to:
  /// **'Report'**
  String get homeReports;

  /// No description provided for @reportsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Report'**
  String get reportsTitle;

  /// No description provided for @reportProfitAndLoss.
  ///
  /// In ur, this message translates to:
  /// **'Nafa nuqsan'**
  String get reportProfitAndLoss;

  /// No description provided for @reportProfitAndLossHint.
  ///
  /// In ur, this message translates to:
  /// **'Bikri, maal ki laagat, kharchay aur asal nafa'**
  String get reportProfitAndLossHint;

  /// No description provided for @reportSalesByItem.
  ///
  /// In ur, this message translates to:
  /// **'Cheez-war bikri'**
  String get reportSalesByItem;

  /// No description provided for @reportSalesByItemHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsi cheez kitni biki aur kitna nafa diya'**
  String get reportSalesByItemHint;

  /// No description provided for @reportExpenses.
  ///
  /// In ur, this message translates to:
  /// **'Kharchay'**
  String get reportExpenses;

  /// No description provided for @reportExpensesHint.
  ///
  /// In ur, this message translates to:
  /// **'Kiraya, bijli, tankhwa: kahan kitna gaya'**
  String get reportExpensesHint;

  /// No description provided for @reportCashBook.
  ///
  /// In ur, this message translates to:
  /// **'Cash book'**
  String get reportCashBook;

  /// No description provided for @reportCashBookHint.
  ///
  /// In ur, this message translates to:
  /// **'Galle mein kya aaya, kya gaya, kitna hona chahiye'**
  String get reportCashBookHint;

  /// No description provided for @reportDayBook.
  ///
  /// In ur, this message translates to:
  /// **'Roznamcha'**
  String get reportDayBook;

  /// No description provided for @reportDayBookHint.
  ///
  /// In ur, this message translates to:
  /// **'Khaton mein har entry, jis tarteeb se hui'**
  String get reportDayBookHint;

  /// No description provided for @reportStockValue.
  ///
  /// In ur, this message translates to:
  /// **'Stock ki qeemat'**
  String get reportStockValue;

  /// No description provided for @reportStockValueHint.
  ///
  /// In ur, this message translates to:
  /// **'Shelf par kitne ka maal hai'**
  String get reportStockValueHint;

  /// No description provided for @reportToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj'**
  String get reportToday;

  /// No description provided for @reportThisMonth.
  ///
  /// In ur, this message translates to:
  /// **'Is mahina'**
  String get reportThisMonth;

  /// No description provided for @reportLastMonth.
  ///
  /// In ur, this message translates to:
  /// **'Pichla mahina'**
  String get reportLastMonth;

  /// No description provided for @reportThisYear.
  ///
  /// In ur, this message translates to:
  /// **'Is saal'**
  String get reportThisYear;

  /// No description provided for @reportAsOfNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi tak'**
  String get reportAsOfNow;

  /// No description provided for @reportShareCsv.
  ///
  /// In ur, this message translates to:
  /// **'CSV bhejein'**
  String get reportShareCsv;

  /// No description provided for @reportSalesByDay.
  ///
  /// In ur, this message translates to:
  /// **'Roz ki bikri'**
  String get reportSalesByDay;

  /// No description provided for @reportSalesByDayHint.
  ///
  /// In ur, this message translates to:
  /// **'Har din kitne bill, kitni bikri, kitna udhaar'**
  String get reportSalesByDayHint;

  /// No description provided for @reportReceivables.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar kitna purana'**
  String get reportReceivables;

  /// No description provided for @reportReceivablesHint.
  ///
  /// In ur, this message translates to:
  /// **'Kis par kitna baqi hai, aur kab se'**
  String get reportReceivablesHint;

  /// No description provided for @reportSharePdf.
  ///
  /// In ur, this message translates to:
  /// **'PDF bhejein'**
  String get reportSharePdf;

  /// No description provided for @chequeDone.
  ///
  /// In ur, this message translates to:
  /// **'Ho gaya'**
  String get chequeDone;
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
