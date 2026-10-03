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

  /// No description provided for @reportPayables.
  ///
  /// In ur, this message translates to:
  /// **'Suppliers ka baqi'**
  String get reportPayables;

  /// No description provided for @reportPayablesHint.
  ///
  /// In ur, this message translates to:
  /// **'Kis supplier ka kitna dena hai, aur kab se'**
  String get reportPayablesHint;

  /// No description provided for @usersTitle.
  ///
  /// In ur, this message translates to:
  /// **'Staff aur PIN'**
  String get usersTitle;

  /// No description provided for @usersMyPin.
  ///
  /// In ur, this message translates to:
  /// **'Mera PIN rakhein'**
  String get usersMyPin;

  /// No description provided for @usersAdd.
  ///
  /// In ur, this message translates to:
  /// **'Staff shamil karein'**
  String get usersAdd;

  /// No description provided for @usersName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get usersName;

  /// No description provided for @usersPin.
  ///
  /// In ur, this message translates to:
  /// **'PIN (4 se 6 hindsay)'**
  String get usersPin;

  /// No description provided for @usersPinAgain.
  ///
  /// In ur, this message translates to:
  /// **'PIN dobara'**
  String get usersPinAgain;

  /// No description provided for @usersPinMismatch.
  ///
  /// In ur, this message translates to:
  /// **'Dono PIN ek jaisay nahi'**
  String get usersPinMismatch;

  /// No description provided for @usersPinInvalid.
  ///
  /// In ur, this message translates to:
  /// **'PIN 4 se 6 hindson ka ho'**
  String get usersPinInvalid;

  /// No description provided for @usersPinSaved.
  ///
  /// In ur, this message translates to:
  /// **'PIN rakh diya'**
  String get usersPinSaved;

  /// No description provided for @usersNoPin.
  ///
  /// In ur, this message translates to:
  /// **'PIN nahi'**
  String get usersNoPin;

  /// No description provided for @usersInactive.
  ///
  /// In ur, this message translates to:
  /// **'Staff mein nahi'**
  String get usersInactive;

  /// No description provided for @usersRemove.
  ///
  /// In ur, this message translates to:
  /// **'Staff se hatayein'**
  String get usersRemove;

  /// No description provided for @usersLetBack.
  ///
  /// In ur, this message translates to:
  /// **'Wapas shamil karein'**
  String get usersLetBack;

  /// No description provided for @usersNewPin.
  ///
  /// In ur, this message translates to:
  /// **'Naya PIN'**
  String get usersNewPin;

  /// No description provided for @usersRole.
  ///
  /// In ur, this message translates to:
  /// **'Kaam'**
  String get usersRole;

  /// No description provided for @usersOwnerPinFirst.
  ///
  /// In ur, this message translates to:
  /// **'Pehle apna PIN rakhein, taake staff aap ki screens na khol sakay.'**
  String get usersOwnerPinFirst;

  /// No description provided for @roleOwner.
  ///
  /// In ur, this message translates to:
  /// **'Malik'**
  String get roleOwner;

  /// No description provided for @roleManager.
  ///
  /// In ur, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleAccountant.
  ///
  /// In ur, this message translates to:
  /// **'Munshi'**
  String get roleAccountant;

  /// No description provided for @roleCashier.
  ///
  /// In ur, this message translates to:
  /// **'Cashier'**
  String get roleCashier;

  /// No description provided for @signInTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kaun hai?'**
  String get signInTitle;

  /// No description provided for @signInPin.
  ///
  /// In ur, this message translates to:
  /// **'PIN'**
  String get signInPin;

  /// No description provided for @signInOpen.
  ///
  /// In ur, this message translates to:
  /// **'Kholein'**
  String get signInOpen;

  /// No description provided for @signInWrong.
  ///
  /// In ur, this message translates to:
  /// **'Ghalat PIN'**
  String get signInWrong;

  /// No description provided for @homeLock.
  ///
  /// In ur, this message translates to:
  /// **'Taala lagayein'**
  String get homeLock;

  /// No description provided for @homeSignedInAs.
  ///
  /// In ur, this message translates to:
  /// **'{name} ({role})'**
  String homeSignedInAs(String name, String role);

  /// No description provided for @homeDayClose.
  ///
  /// In ur, this message translates to:
  /// **'Din band'**
  String get homeDayClose;

  /// No description provided for @dayCloseTitle.
  ///
  /// In ur, this message translates to:
  /// **'Din band karein'**
  String get dayCloseTitle;

  /// No description provided for @dayCloseExpected.
  ///
  /// In ur, this message translates to:
  /// **'Khaton ke hisaab se galle mein'**
  String get dayCloseExpected;

  /// No description provided for @dayCloseCounted.
  ///
  /// In ur, this message translates to:
  /// **'Gin kar kitna nikla'**
  String get dayCloseCounted;

  /// No description provided for @dayCloseNote.
  ///
  /// In ur, this message translates to:
  /// **'Farq ki wajah (marzi se)'**
  String get dayCloseNote;

  /// No description provided for @dayCloseSave.
  ///
  /// In ur, this message translates to:
  /// **'Din band karein'**
  String get dayCloseSave;

  /// No description provided for @dayCloseMatches.
  ///
  /// In ur, this message translates to:
  /// **'Galla khaton se barabar hai'**
  String get dayCloseMatches;

  /// No description provided for @dayCloseShort.
  ///
  /// In ur, this message translates to:
  /// **'{amount} kam hai'**
  String dayCloseShort(String amount);

  /// No description provided for @dayCloseOver.
  ///
  /// In ur, this message translates to:
  /// **'{amount} zyada hai'**
  String dayCloseOver(String amount);

  /// No description provided for @dayCloseDone.
  ///
  /// In ur, this message translates to:
  /// **'Din band ho gaya'**
  String get dayCloseDone;

  /// No description provided for @dayCloseLast.
  ///
  /// In ur, this message translates to:
  /// **'Pichli dafa: {when}, {name}'**
  String dayCloseLast(String when, String name);

  /// No description provided for @auditTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kaun ne kya kiya'**
  String get auditTitle;

  /// No description provided for @auditEveryone.
  ///
  /// In ur, this message translates to:
  /// **'Sab'**
  String get auditEveryone;

  /// No description provided for @auditEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi kuch nahi hua'**
  String get auditEmpty;

  /// No description provided for @reportTrialBalance.
  ///
  /// In ur, this message translates to:
  /// **'Trial balance'**
  String get reportTrialBalance;

  /// No description provided for @reportTrialBalanceHint.
  ///
  /// In ur, this message translates to:
  /// **'Har khata apni taraf, dono taraf barabar'**
  String get reportTrialBalanceHint;

  /// No description provided for @reportBalanceSheet.
  ///
  /// In ur, this message translates to:
  /// **'Balance sheet'**
  String get reportBalanceSheet;

  /// No description provided for @reportBalanceSheetHint.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke paas kya hai, kis ka dena hai, malik ka kya hai'**
  String get reportBalanceSheetHint;

  /// No description provided for @homeAccounts.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab kitaab'**
  String get homeAccounts;

  /// No description provided for @accountsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab kitaab'**
  String get accountsTitle;

  /// No description provided for @accountsWriteVoucher.
  ///
  /// In ur, this message translates to:
  /// **'Voucher likhein'**
  String get accountsWriteVoucher;

  /// No description provided for @accountTypeAsset.
  ///
  /// In ur, this message translates to:
  /// **'Jo dukaan ke paas hai'**
  String get accountTypeAsset;

  /// No description provided for @accountTypeLiability.
  ///
  /// In ur, this message translates to:
  /// **'Jo dena hai'**
  String get accountTypeLiability;

  /// No description provided for @accountTypeEquity.
  ///
  /// In ur, this message translates to:
  /// **'Malik ka'**
  String get accountTypeEquity;

  /// No description provided for @accountTypeIncome.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani'**
  String get accountTypeIncome;

  /// No description provided for @accountTypeExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharchay'**
  String get accountTypeExpense;

  /// No description provided for @accountLedgerEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Is khate mein abhi kuch nahi'**
  String get accountLedgerEmpty;

  /// No description provided for @journalTitle.
  ///
  /// In ur, this message translates to:
  /// **'Journal voucher'**
  String get journalTitle;

  /// No description provided for @journalNarration.
  ///
  /// In ur, this message translates to:
  /// **'Kis liye (zaroori)'**
  String get journalNarration;

  /// No description provided for @journalDebit.
  ///
  /// In ur, this message translates to:
  /// **'Debit'**
  String get journalDebit;

  /// No description provided for @journalCredit.
  ///
  /// In ur, this message translates to:
  /// **'Credit'**
  String get journalCredit;

  /// No description provided for @journalAddLine.
  ///
  /// In ur, this message translates to:
  /// **'Aur line'**
  String get journalAddLine;

  /// No description provided for @journalSave.
  ///
  /// In ur, this message translates to:
  /// **'Voucher save karein'**
  String get journalSave;

  /// No description provided for @journalSaved.
  ///
  /// In ur, this message translates to:
  /// **'Voucher {entryNo} save ho gaya'**
  String journalSaved(String entryNo);

  /// No description provided for @journalDifference.
  ///
  /// In ur, this message translates to:
  /// **'Farq: {amount}'**
  String journalDifference(String amount);

  /// No description provided for @journalBalanced.
  ///
  /// In ur, this message translates to:
  /// **'Dono taraf barabar'**
  String get journalBalanced;

  /// No description provided for @journalPickAccount.
  ///
  /// In ur, this message translates to:
  /// **'Khata chunein'**
  String get journalPickAccount;

  /// No description provided for @firmsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Dukaanein aur firms'**
  String get firmsTitle;

  /// No description provided for @firmsAdd.
  ///
  /// In ur, this message translates to:
  /// **'Nayi firm'**
  String get firmsAdd;

  /// No description provided for @firmsName.
  ///
  /// In ur, this message translates to:
  /// **'Firm ka naam'**
  String get firmsName;

  /// No description provided for @firmsOwner.
  ///
  /// In ur, this message translates to:
  /// **'Malik ka naam'**
  String get firmsOwner;

  /// No description provided for @firmsCity.
  ///
  /// In ur, this message translates to:
  /// **'Shehar'**
  String get firmsCity;

  /// No description provided for @firmsOpen.
  ///
  /// In ur, this message translates to:
  /// **'Kholein'**
  String get firmsOpen;

  /// No description provided for @firmsCurrent.
  ///
  /// In ur, this message translates to:
  /// **'Khuli hui'**
  String get firmsCurrent;

  /// No description provided for @firmsAdded.
  ///
  /// In ur, this message translates to:
  /// **'{name} ban gayi'**
  String firmsAdded(String name);

  /// No description provided for @firmsSwitched.
  ///
  /// In ur, this message translates to:
  /// **'Ab {name} khuli hai'**
  String firmsSwitched(String name);

  /// No description provided for @posScannedExpired.
  ///
  /// In ur, this message translates to:
  /// **'Batch {batch} ki expiry {date} guzar chuki hai. Yeh na bechein.'**
  String posScannedExpired(String batch, String date);

  /// No description provided for @posSerialAlreadyOnBill.
  ///
  /// In ur, this message translates to:
  /// **'{serial} pehle se bill par hai'**
  String posSerialAlreadyOnBill(String serial);

  /// No description provided for @posScanTheSerial.
  ///
  /// In ur, this message translates to:
  /// **'Yeh cheez serial / IMEI se bikti hai. Uska number scan ya type karein.'**
  String get posScanTheSerial;

  /// No description provided for @reportExpiry.
  ///
  /// In ur, this message translates to:
  /// **'Expiry'**
  String get reportExpiry;

  /// No description provided for @reportExpiryHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsa batch guzar gaya, kaunsa guzarne wala hai'**
  String get reportExpiryHint;

  /// No description provided for @itemTracksBatch.
  ///
  /// In ur, this message translates to:
  /// **'Batch aur expiry se'**
  String get itemTracksBatch;

  /// No description provided for @itemTracksSerial.
  ///
  /// In ur, this message translates to:
  /// **'Serial / IMEI se'**
  String get itemTracksSerial;

  /// No description provided for @purchaseBatch.
  ///
  /// In ur, this message translates to:
  /// **'Batch no.'**
  String get purchaseBatch;

  /// No description provided for @purchaseExpiry.
  ///
  /// In ur, this message translates to:
  /// **'Expiry'**
  String get purchaseExpiry;

  /// No description provided for @purchaseSerials.
  ///
  /// In ur, this message translates to:
  /// **'Serial / IMEI (har line mein ek)'**
  String get purchaseSerials;

  /// No description provided for @purchaseSerialCount.
  ///
  /// In ur, this message translates to:
  /// **'{count} number'**
  String purchaseSerialCount(int count);

  /// No description provided for @purchaseSerialsNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Har piece ka serial / IMEI likhein'**
  String get purchaseSerialsNeeded;

  /// No description provided for @purchaseBatchNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Batch no. likhein, aur expiry YYYY-MM-DD mein'**
  String get purchaseBatchNeeded;

  /// No description provided for @placesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Maal kahan hai'**
  String get placesTitle;

  /// No description provided for @placesMain.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan'**
  String get placesMain;

  /// No description provided for @placesBatches.
  ///
  /// In ur, this message translates to:
  /// **'Batch'**
  String get placesBatches;

  /// No description provided for @placesSerials.
  ///
  /// In ur, this message translates to:
  /// **'Serial / IMEI'**
  String get placesSerials;

  /// No description provided for @placesMove.
  ///
  /// In ur, this message translates to:
  /// **'Maal bhejein'**
  String get placesMove;

  /// No description provided for @placesTo.
  ///
  /// In ur, this message translates to:
  /// **'Kahan (masalan GODOWN)'**
  String get placesTo;

  /// No description provided for @placesMoveButton.
  ///
  /// In ur, this message translates to:
  /// **'Bhej dein'**
  String get placesMoveButton;

  /// No description provided for @placesMoved.
  ///
  /// In ur, this message translates to:
  /// **'Maal bhej diya'**
  String get placesMoved;

  /// No description provided for @partyTaxRegistered.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax mein registered'**
  String get partyTaxRegistered;

  /// No description provided for @partyOnAtl.
  ///
  /// In ur, this message translates to:
  /// **'Active taxpayer list (ATL) par hai'**
  String get partyOnAtl;

  /// No description provided for @taxTitle.
  ///
  /// In ur, this message translates to:
  /// **'Tax'**
  String get taxTitle;

  /// No description provided for @taxNeverSent.
  ///
  /// In ur, this message translates to:
  /// **'Sab hisaab isi phone par hota hai, kahin bheja nahi jata. Return khud ya accountant se IRIS par file karein.'**
  String get taxNeverSent;

  /// No description provided for @taxRegistered.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan sales tax mein registered hai'**
  String get taxRegistered;

  /// No description provided for @taxRegisteredHint.
  ///
  /// In ur, this message translates to:
  /// **'Registered dukaan bill par 18% sales tax lagati hai; ghair registered koi tax nahi lagati'**
  String get taxRegisteredHint;

  /// No description provided for @taxPricesInclude.
  ///
  /// In ur, this message translates to:
  /// **'Qeematon mein tax shamil hai'**
  String get taxPricesInclude;

  /// No description provided for @taxTajirDost.
  ///
  /// In ur, this message translates to:
  /// **'Tajir Dost 1%'**
  String get taxTajirDost;

  /// No description provided for @taxTurnoverThisMonth.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine ki bikri'**
  String get taxTurnoverThisMonth;

  /// No description provided for @taxFixedAtOnePercent.
  ///
  /// In ur, this message translates to:
  /// **'1% fixed tax'**
  String get taxFixedAtOnePercent;

  /// No description provided for @taxUtilityWht.
  ///
  /// In ur, this message translates to:
  /// **'Bijli ke bill par kata hua tax'**
  String get taxUtilityWht;

  /// No description provided for @taxToPay.
  ///
  /// In ur, this message translates to:
  /// **'Dena hai'**
  String get taxToPay;

  /// No description provided for @reportSalesTax.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax'**
  String get reportSalesTax;

  /// No description provided for @reportSalesTaxHint.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine kitna sales tax aur further tax dena hai'**
  String get reportSalesTaxHint;

  /// No description provided for @reportTajirDost.
  ///
  /// In ur, this message translates to:
  /// **'Tajir Dost 1%'**
  String get reportTajirDost;

  /// No description provided for @reportTajirDostHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine ki bikri ka 1%'**
  String get reportTajirDostHint;

  /// No description provided for @paySection73.
  ///
  /// In ur, this message translates to:
  /// **'Section 73: Rs 50,000 se zyada naqad adaygi par is maal ka input tax nahi milega. Bank ya cheque se dein.'**
  String get paySection73;

  /// No description provided for @syncTitle.
  ///
  /// In ur, this message translates to:
  /// **'Wi-fi par counters'**
  String get syncTitle;

  /// No description provided for @syncStaysInShop.
  ///
  /// In ur, this message translates to:
  /// **'Counters dukaan ke apne wi-fi par milte hain. Internet par kuch nahin jata.'**
  String get syncStaysInShop;

  /// No description provided for @syncHostSwitch.
  ///
  /// In ur, this message translates to:
  /// **'Counters ko is phone se milne dein'**
  String get syncHostSwitch;

  /// No description provided for @syncHostHint.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone master hai. Isay dukaan ke wi-fi par khula rakhein.'**
  String get syncHostHint;

  /// No description provided for @syncAddress.
  ///
  /// In ur, this message translates to:
  /// **'Counters ke liye pata'**
  String get syncAddress;

  /// No description provided for @syncNoAddress.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone kisi wi-fi par nahin'**
  String get syncNoAddress;

  /// No description provided for @syncLetJoin.
  ///
  /// In ur, this message translates to:
  /// **'Naya counter jorein'**
  String get syncLetJoin;

  /// No description provided for @syncJoinCode.
  ///
  /// In ur, this message translates to:
  /// **'Yeh code counter par likhein'**
  String get syncJoinCode;

  /// No description provided for @syncDevices.
  ///
  /// In ur, this message translates to:
  /// **'Is dukaan ke phone'**
  String get syncDevices;

  /// No description provided for @syncMasterRole.
  ///
  /// In ur, this message translates to:
  /// **'Master'**
  String get syncMasterRole;

  /// No description provided for @syncCounterRole.
  ///
  /// In ur, this message translates to:
  /// **'Counter · bill {prefix}'**
  String syncCounterRole(String prefix);

  /// No description provided for @syncThisPhone.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone'**
  String get syncThisPhone;

  /// No description provided for @syncLastSynced.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri sync {when}'**
  String syncLastSynced(String when);

  /// No description provided for @syncNever.
  ///
  /// In ur, this message translates to:
  /// **'Abhi sync nahin hua'**
  String get syncNever;

  /// No description provided for @syncNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi sync karein'**
  String get syncNow;

  /// No description provided for @syncDone.
  ///
  /// In ur, this message translates to:
  /// **'{sent} bheje, {received} aaye'**
  String syncDone(String sent, String received);

  /// No description provided for @syncConflicts.
  ///
  /// In ur, this message translates to:
  /// **'{count} takraao nishaan wale naam se rakhe gaye'**
  String syncConflicts(String count);

  /// No description provided for @syncCounterOf.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone {host} wale master ka counter hai. Har aadhe minute mein khud sync hota hai.'**
  String syncCounterOf(String host);

  /// No description provided for @syncJoinTitle.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke master phone se jurein'**
  String get syncJoinTitle;

  /// No description provided for @syncJoinHint.
  ///
  /// In ur, this message translates to:
  /// **'Master par: Settings, Wi-fi par counters, Naya counter jorein. Dono phone ek hi wi-fi par hon.'**
  String get syncJoinHint;

  /// No description provided for @syncMasterAddress.
  ///
  /// In ur, this message translates to:
  /// **'Master ka pata'**
  String get syncMasterAddress;

  /// No description provided for @syncCode.
  ///
  /// In ur, this message translates to:
  /// **'Master par dikhaya code'**
  String get syncCode;

  /// No description provided for @syncCounterName.
  ///
  /// In ur, this message translates to:
  /// **'Is counter ka naam'**
  String get syncCounterName;

  /// No description provided for @syncCounterNameHint.
  ///
  /// In ur, this message translates to:
  /// **'maslan Counter 2'**
  String get syncCounterNameHint;

  /// No description provided for @syncJoin.
  ///
  /// In ur, this message translates to:
  /// **'Jurein'**
  String get syncJoin;

  /// No description provided for @importTitle.
  ///
  /// In ur, this message translates to:
  /// **'Excel se laayein'**
  String get importTitle;

  /// No description provided for @importHint.
  ///
  /// In ur, this message translates to:
  /// **'Apni purani list .xlsx, .xls ya .csv mein chunein. Pehli line mein columns ke naam hon, maslan Name, Sale price, Stock.'**
  String get importHint;

  /// No description provided for @importItems.
  ///
  /// In ur, this message translates to:
  /// **'Maal'**
  String get importItems;

  /// No description provided for @importParties.
  ///
  /// In ur, this message translates to:
  /// **'Khata'**
  String get importParties;

  /// No description provided for @importPick.
  ///
  /// In ur, this message translates to:
  /// **'File chunein'**
  String get importPick;

  /// No description provided for @importReady.
  ///
  /// In ur, this message translates to:
  /// **'{count} line tayyar'**
  String importReady(String count);

  /// No description provided for @importProblems.
  ///
  /// In ur, this message translates to:
  /// **'{count} line nahin aa sakti'**
  String importProblems(String count);

  /// No description provided for @importRun.
  ///
  /// In ur, this message translates to:
  /// **'{count} laayein'**
  String importRun(String count);

  /// No description provided for @importDone.
  ///
  /// In ur, this message translates to:
  /// **'{added} aa gaye, {skipped} chhor diye'**
  String importDone(String added, String skipped);

  /// No description provided for @importColumns.
  ///
  /// In ur, this message translates to:
  /// **'Columns: {columns}'**
  String importColumns(String columns);

  /// No description provided for @settingsBooksEncrypted.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par hisaab encrypted hai'**
  String get settingsBooksEncrypted;

  /// No description provided for @settingsBooksPlain.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par hisaab encrypted nahin: phone ka keystore key nahin rakh saka'**
  String get settingsBooksPlain;

  /// No description provided for @settingsCrashes.
  ///
  /// In ur, this message translates to:
  /// **'App is phone par {count} dafa kisi ghalti par ruki'**
  String settingsCrashes(String count);

  /// No description provided for @settingsCrashesClear.
  ///
  /// In ur, this message translates to:
  /// **'Saaf karein'**
  String get settingsCrashesClear;

  /// No description provided for @itemVipPrice.
  ///
  /// In ur, this message translates to:
  /// **'VIP qeemat'**
  String get itemVipPrice;

  /// No description provided for @partyTierVip.
  ///
  /// In ur, this message translates to:
  /// **'VIP'**
  String get partyTierVip;

  /// No description provided for @posScaleUnknown.
  ///
  /// In ur, this message translates to:
  /// **'Scale label par PLU {plu} kisi maal ka code nahin'**
  String posScaleUnknown(String plu);

  /// No description provided for @posScaleNoPrice.
  ///
  /// In ur, this message translates to:
  /// **'{name} ki qeemat nahin, is liye scale ki qeemat se wazan nahin nikal sakta'**
  String posScaleNoPrice(String name);

  /// No description provided for @scaleTitle.
  ///
  /// In ur, this message translates to:
  /// **'Tarazu ke labels'**
  String get scaleTitle;

  /// No description provided for @scaleHint.
  ///
  /// In ur, this message translates to:
  /// **'Tarazu jo barcode chhapta hai us mein maal ka PLU aur wazan ya qeemat hoti hai. Maal ka code wahi rakhein jo tarazu mein PLU hai.'**
  String get scaleHint;

  /// No description provided for @scaleWeightPrefixes.
  ///
  /// In ur, this message translates to:
  /// **'Wazan wale prefix (maslan 21, 22)'**
  String get scaleWeightPrefixes;

  /// No description provided for @scalePricePrefixes.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat wale prefix (maslan 23, 24)'**
  String get scalePricePrefixes;

  /// No description provided for @scalePluDigits.
  ///
  /// In ur, this message translates to:
  /// **'PLU ke hindse'**
  String get scalePluDigits;

  /// No description provided for @scalePriceInPaisa.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat paison mein chhapti hai'**
  String get scalePriceInPaisa;

  /// No description provided for @scaleSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get scaleSave;

  /// No description provided for @scaleSaved.
  ///
  /// In ur, this message translates to:
  /// **'Tarazu ke labels save ho gaye'**
  String get scaleSaved;

  /// No description provided for @recipesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Banana (recipe)'**
  String get recipesTitle;

  /// No description provided for @recipesNew.
  ///
  /// In ur, this message translates to:
  /// **'Nayi recipe'**
  String get recipesNew;

  /// No description provided for @recipesEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi recipe nahin. Jo cheez aap khud banate hain, us ki recipe likhein.'**
  String get recipesEmpty;

  /// No description provided for @recipesMakes.
  ///
  /// In ur, this message translates to:
  /// **'Ek batch: {qty} {unit} {name}'**
  String recipesMakes(String qty, String unit, String name);

  /// No description provided for @recipesMake.
  ///
  /// In ur, this message translates to:
  /// **'Banayein'**
  String get recipesMake;

  /// No description provided for @recipesRuns.
  ///
  /// In ur, this message translates to:
  /// **'Kitne batch'**
  String get recipesRuns;

  /// No description provided for @recipesMade.
  ///
  /// In ur, this message translates to:
  /// **'{no}: {qty} {name} ban gaye'**
  String recipesMade(String no, String qty, String name);

  /// No description provided for @recipesName.
  ///
  /// In ur, this message translates to:
  /// **'Recipe ka naam'**
  String get recipesName;

  /// No description provided for @recipesOutput.
  ///
  /// In ur, this message translates to:
  /// **'Kya banta hai'**
  String get recipesOutput;

  /// No description provided for @recipesPickItem.
  ///
  /// In ur, this message translates to:
  /// **'Maal chunein'**
  String get recipesPickItem;

  /// No description provided for @recipesBatchMakes.
  ///
  /// In ur, this message translates to:
  /// **'Ek batch mein kitna'**
  String get recipesBatchMakes;

  /// No description provided for @recipesOverhead.
  ///
  /// In ur, this message translates to:
  /// **'Mazdoori aur packing (Rs)'**
  String get recipesOverhead;

  /// No description provided for @recipesComponents.
  ///
  /// In ur, this message translates to:
  /// **'Kya lagta hai (ek batch mein)'**
  String get recipesComponents;

  /// No description provided for @recipesPerBatch.
  ///
  /// In ur, this message translates to:
  /// **'Ek batch mein'**
  String get recipesPerBatch;

  /// No description provided for @recipesAddComponent.
  ///
  /// In ur, this message translates to:
  /// **'Aur cheez'**
  String get recipesAddComponent;

  /// No description provided for @recipesSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get recipesSave;

  /// No description provided for @vansTitle.
  ///
  /// In ur, this message translates to:
  /// **'Gaariyan (van)'**
  String get vansTitle;

  /// No description provided for @vansNew.
  ///
  /// In ur, this message translates to:
  /// **'Nayi gaari'**
  String get vansNew;

  /// No description provided for @vansName.
  ///
  /// In ur, this message translates to:
  /// **'Gaari ka naam'**
  String get vansName;

  /// No description provided for @vansAdd.
  ///
  /// In ur, this message translates to:
  /// **'Jorein'**
  String get vansAdd;

  /// No description provided for @vansEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi gaari nahin'**
  String get vansEmpty;

  /// No description provided for @vansThisPhone.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone kahan se bechta hai'**
  String get vansThisPhone;

  /// No description provided for @vansShopFloor.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan'**
  String get vansShopFloor;

  /// No description provided for @vansToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj {count} bill, cash:'**
  String vansToday(String count);

  /// No description provided for @vansSettled.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab ho gaya: {amount} jama'**
  String vansSettled(String amount);

  /// No description provided for @vansLoad.
  ///
  /// In ur, this message translates to:
  /// **'Maal laadein'**
  String get vansLoad;

  /// No description provided for @vansSettle.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab karein'**
  String get vansSettle;

  /// No description provided for @vansOnBoard.
  ///
  /// In ur, this message translates to:
  /// **'Gaari mein maal'**
  String get vansOnBoard;

  /// No description provided for @vansQty.
  ///
  /// In ur, this message translates to:
  /// **'Kitna'**
  String get vansQty;

  /// No description provided for @vansExpected.
  ///
  /// In ur, this message translates to:
  /// **'Rider ke paas hona chahiye'**
  String get vansExpected;

  /// No description provided for @vansCounted.
  ///
  /// In ur, this message translates to:
  /// **'Rider ne diya (Rs)'**
  String get vansCounted;

  /// No description provided for @vansReturnUnsold.
  ///
  /// In ur, this message translates to:
  /// **'Bacha hua maal dukaan wapas'**
  String get vansReturnUnsold;

  /// No description provided for @vansSettledEven.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab barabar'**
  String get vansSettledEven;

  /// No description provided for @vansSettledShort.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab ho gaya, {amount} kam'**
  String vansSettledShort(String amount);

  /// No description provided for @vansSettledOver.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab ho gaya, {amount} zyada'**
  String vansSettledOver(String amount);

  /// No description provided for @fbrTitle.
  ///
  /// In ur, this message translates to:
  /// **'FBR digital invoicing'**
  String get fbrTitle;

  /// No description provided for @fbrWhatIsSent.
  ///
  /// In ur, this message translates to:
  /// **'Chalu karne par har bill (maal, qeemat, tax, kharidar ka NTN) FBR ko jata hai. Band ho to kuch nahin jata.'**
  String get fbrWhatIsSent;

  /// No description provided for @fbrReport.
  ///
  /// In ur, this message translates to:
  /// **'Har bill FBR ko bhejein'**
  String get fbrReport;

  /// No description provided for @fbrSandbox.
  ///
  /// In ur, this message translates to:
  /// **'FBR ka test gateway (sandbox)'**
  String get fbrSandbox;

  /// No description provided for @fbrToken.
  ///
  /// In ur, this message translates to:
  /// **'PRAL ka token'**
  String get fbrToken;

  /// No description provided for @fbrBaseUrl.
  ///
  /// In ur, this message translates to:
  /// **'Integrator ka pata (khali = FBR)'**
  String get fbrBaseUrl;

  /// No description provided for @fbrSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get fbrSave;

  /// No description provided for @fbrSaved.
  ///
  /// In ur, this message translates to:
  /// **'FBR ki setting save ho gayi'**
  String get fbrSaved;

  /// No description provided for @fbrBills.
  ///
  /// In ur, this message translates to:
  /// **'FBR ko bheje bill'**
  String get fbrBills;

  /// No description provided for @fbrSendNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi bhejein'**
  String get fbrSendNow;

  /// No description provided for @fbrSent.
  ///
  /// In ur, this message translates to:
  /// **'{posted} qabool, {rejected} wapas, {waiting} intezar mein'**
  String fbrSent(String posted, String rejected, String waiting);

  /// No description provided for @fbrPosted.
  ///
  /// In ur, this message translates to:
  /// **'Qabool'**
  String get fbrPosted;

  /// No description provided for @fbrRejected.
  ///
  /// In ur, this message translates to:
  /// **'Wapas'**
  String get fbrRejected;

  /// No description provided for @fbrPending.
  ///
  /// In ur, this message translates to:
  /// **'Intezar'**
  String get fbrPending;

  /// No description provided for @fbrLate.
  ///
  /// In ur, this message translates to:
  /// **'72 ghante guzar gaye; credit note banayein'**
  String get fbrLate;

  /// No description provided for @fbrRetry.
  ///
  /// In ur, this message translates to:
  /// **'Dobara bhejein'**
  String get fbrRetry;

  /// No description provided for @driveTitle.
  ///
  /// In ur, this message translates to:
  /// **'Google Drive par roz backup'**
  String get driveTitle;

  /// No description provided for @driveExplain.
  ///
  /// In ur, this message translates to:
  /// **'Roz jab app khulti hai, hisaab upar wale password se band ho kar aap ki apni Google Drive ke app folder mein chala jata hai. Aakhri 7 rakhe jate hain. Naye phone par wahi Google account aur yehi password chahiye.'**
  String get driveExplain;

  /// No description provided for @driveTurnOn.
  ///
  /// In ur, this message translates to:
  /// **'Drive backup chalu karein'**
  String get driveTurnOn;

  /// No description provided for @driveTurnOff.
  ///
  /// In ur, this message translates to:
  /// **'Drive backup band karein'**
  String get driveTurnOff;

  /// No description provided for @driveOn.
  ///
  /// In ur, this message translates to:
  /// **'Drive backup chalu hai'**
  String get driveOn;

  /// No description provided for @driveLast.
  ///
  /// In ur, this message translates to:
  /// **'Drive par aakhri backup: {when}'**
  String driveLast(String when);

  /// No description provided for @driveFailed.
  ///
  /// In ur, this message translates to:
  /// **'Drive tak nahi pohncha: {reason}'**
  String driveFailed(String reason);

  /// No description provided for @driveNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi Drive par bhejein'**
  String get driveNow;

  /// No description provided for @driveRestore.
  ///
  /// In ur, this message translates to:
  /// **'Google Drive se wapas layein'**
  String get driveRestore;

  /// No description provided for @driveNone.
  ///
  /// In ur, this message translates to:
  /// **'Drive par koi backup nahi mila'**
  String get driveNone;

  /// No description provided for @drivePick.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsi backup wapas layein?'**
  String get drivePick;

  /// No description provided for @planTitle.
  ///
  /// In ur, this message translates to:
  /// **'Plan'**
  String get planTitle;

  /// No description provided for @planCurrent.
  ///
  /// In ur, this message translates to:
  /// **'Aap ka plan: {plan}'**
  String planCurrent(String plan);

  /// No description provided for @planPerYear.
  ///
  /// In ur, this message translates to:
  /// **'{price} / saal'**
  String planPerYear(String price);

  /// No description provided for @planBuy.
  ///
  /// In ur, this message translates to:
  /// **'Yeh plan lein'**
  String get planBuy;

  /// No description provided for @planIsYours.
  ///
  /// In ur, this message translates to:
  /// **'Yeh aap ka plan hai'**
  String get planIsYours;

  /// No description provided for @planRestore.
  ///
  /// In ur, this message translates to:
  /// **'Pehle se khareeda hai? Wapas layein'**
  String get planRestore;

  /// No description provided for @planNoBilling.
  ///
  /// In ur, this message translates to:
  /// **'Is build mein plan khareedne ka intezam nahi. Play Store wali app se khareedein.'**
  String get planNoBilling;

  /// No description provided for @planNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Iske liye {plan} plan chahiye'**
  String planNeeded(String plan);

  /// No description provided for @planTestTitle.
  ///
  /// In ur, this message translates to:
  /// **'Sirf test ke liye: plan chunein'**
  String get planTestTitle;

  /// No description provided for @planTestNote.
  ///
  /// In ur, this message translates to:
  /// **'Yeh sirf test build mein hai, asal app mein nahi. Koi paisa nahi lagta.'**
  String get planTestNote;

  /// No description provided for @planTestReal.
  ///
  /// In ur, this message translates to:
  /// **'Jo khareeda hai'**
  String get planTestReal;

  /// No description provided for @planTestActive.
  ///
  /// In ur, this message translates to:
  /// **'Test plan chal raha hai: {plan}'**
  String planTestActive(String plan);

  /// No description provided for @planFreeIncludes.
  ///
  /// In ur, this message translates to:
  /// **'Hamesha muft: bill, khata, stock, cash book, printing, WhatsApp aur hath se backup.'**
  String get planFreeIncludes;

  /// No description provided for @planFeatNoWatermark.
  ///
  /// In ur, this message translates to:
  /// **'Bill par \'Bazaar Ledger\' ki line nahi'**
  String get planFeatNoWatermark;

  /// No description provided for @planFeatAutoDriveBackup.
  ///
  /// In ur, this message translates to:
  /// **'Roz Google Drive backup'**
  String get planFeatAutoDriveBackup;

  /// No description provided for @planFeatCheques.
  ///
  /// In ur, this message translates to:
  /// **'Post-dated cheque'**
  String get planFeatCheques;

  /// No description provided for @planFeatPriceLists.
  ///
  /// In ur, this message translates to:
  /// **'Wholesale aur VIP rate'**
  String get planFeatPriceLists;

  /// No description provided for @planFeatAccountingReports.
  ///
  /// In ur, this message translates to:
  /// **'Munafa-nuqsan, balance sheet aur tax reports'**
  String get planFeatAccountingReports;

  /// No description provided for @planFeatTracking.
  ///
  /// In ur, this message translates to:
  /// **'Batch, expiry aur serial/IMEI'**
  String get planFeatTracking;

  /// No description provided for @planFeatScaleLabels.
  ///
  /// In ur, this message translates to:
  /// **'Tarazu ke labels'**
  String get planFeatScaleLabels;

  /// No description provided for @planFeatGodowns.
  ///
  /// In ur, this message translates to:
  /// **'Godown aur stock transfer'**
  String get planFeatGodowns;

  /// No description provided for @planFeatLanSync.
  ///
  /// In ur, this message translates to:
  /// **'Wi-fi par kai counter'**
  String get planFeatLanSync;

  /// No description provided for @planFeatFbr.
  ///
  /// In ur, this message translates to:
  /// **'FBR ko bill live bhejna'**
  String get planFeatFbr;

  /// No description provided for @planFeatManufacturing.
  ///
  /// In ur, this message translates to:
  /// **'Recipe aur maal banana'**
  String get planFeatManufacturing;

  /// No description provided for @planFeatVans.
  ///
  /// In ur, this message translates to:
  /// **'Gaari (van) sales'**
  String get planFeatVans;

  /// No description provided for @planFirms.
  ///
  /// In ur, this message translates to:
  /// **'{count} firms tak'**
  String planFirms(int count);

  /// No description provided for @planFirmsUnlimited.
  ///
  /// In ur, this message translates to:
  /// **'Jitni chahein firms'**
  String get planFirmsUnlimited;

  /// No description provided for @planUsers.
  ///
  /// In ur, this message translates to:
  /// **'{count} log, apne PIN ke sath'**
  String planUsers(int count);

  /// No description provided for @planUsersUnlimited.
  ///
  /// In ur, this message translates to:
  /// **'Jitne chahein log'**
  String get planUsersUnlimited;

  /// No description provided for @syncFind.
  ///
  /// In ur, this message translates to:
  /// **'Wi-fi par master dhoondein'**
  String get syncFind;

  /// No description provided for @syncFindNone.
  ///
  /// In ur, this message translates to:
  /// **'Koi master nahi mila. Dono phone ek hi wi-fi par hon, ya address khud likhein.'**
  String get syncFindNone;

  /// No description provided for @reportPurchaseRegister.
  ///
  /// In ur, this message translates to:
  /// **'Khareed register'**
  String get reportPurchaseRegister;

  /// No description provided for @reportPurchaseRegisterHint.
  ///
  /// In ur, this message translates to:
  /// **'Har khareed ka bill, supplier ka NTN aur tax'**
  String get reportPurchaseRegisterHint;

  /// No description provided for @statementShare.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab ka statement (PDF)'**
  String get statementShare;

  /// No description provided for @statementThisMonth.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine'**
  String get statementThisMonth;

  /// No description provided for @statementLastMonth.
  ///
  /// In ur, this message translates to:
  /// **'Pichhle mahine'**
  String get statementLastMonth;

  /// No description provided for @statementThisYear.
  ///
  /// In ur, this message translates to:
  /// **'Is saal'**
  String get statementThisYear;

  /// No description provided for @statementAll.
  ///
  /// In ur, this message translates to:
  /// **'Shuru se ab tak'**
  String get statementAll;

  /// No description provided for @chargeCancel.
  ///
  /// In ur, this message translates to:
  /// **'Yeh charge wapas lein'**
  String get chargeCancel;

  /// No description provided for @chargeCancelConfirm.
  ///
  /// In ur, this message translates to:
  /// **'{no} wapas lena hai? Khata se hat jayega.'**
  String chargeCancelConfirm(String no);

  /// No description provided for @chargeCancelReason.
  ///
  /// In ur, this message translates to:
  /// **'Charge wapas liya'**
  String get chargeCancelReason;

  /// No description provided for @chargeCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Charge wapas ho gaya'**
  String get chargeCancelled;

  /// No description provided for @challanBillAll.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ke {count} aur challan bhi isi bill mein'**
  String challanBillAll(int count);

  /// No description provided for @accountsAdd.
  ///
  /// In ur, this message translates to:
  /// **'Naya account'**
  String get accountsAdd;

  /// No description provided for @accountsAddName.
  ///
  /// In ur, this message translates to:
  /// **'Account ka naam'**
  String get accountsAddName;

  /// No description provided for @accountsTypeAsset.
  ///
  /// In ur, this message translates to:
  /// **'Asaasa (asset)'**
  String get accountsTypeAsset;

  /// No description provided for @accountsTypeLiability.
  ///
  /// In ur, this message translates to:
  /// **'Qarz (liability)'**
  String get accountsTypeLiability;

  /// No description provided for @accountsTypeEquity.
  ///
  /// In ur, this message translates to:
  /// **'Malik ka (equity)'**
  String get accountsTypeEquity;

  /// No description provided for @accountsTypeIncome.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani'**
  String get accountsTypeIncome;

  /// No description provided for @accountsTypeExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharcha'**
  String get accountsTypeExpense;

  /// No description provided for @accountsCloseYear.
  ///
  /// In ur, this message translates to:
  /// **'Saal band karein'**
  String get accountsCloseYear;

  /// No description provided for @accountsCloseYearConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Saal {year} ka munafa retained earnings mein chala jayega. Band karein?'**
  String accountsCloseYearConfirm(String year);

  /// No description provided for @accountsYearClosed.
  ///
  /// In ur, this message translates to:
  /// **'Saal band ho gaya ({no})'**
  String accountsYearClosed(String no);

  /// No description provided for @vansSettleYesterday.
  ///
  /// In ur, this message translates to:
  /// **'Kal ka hisaab (aaj nahi)'**
  String get vansSettleYesterday;

  /// No description provided for @syncClashHint.
  ///
  /// In ur, this message translates to:
  /// **'Do counters par ek hi code ya barcode se do cheezen ban gayin. Dono rakhi gayin, doosri ke naam par ~ nishaan hai. Theek kar ke \'Ho gaya\' dabayein.'**
  String get syncClashHint;

  /// No description provided for @syncClashDone.
  ///
  /// In ur, this message translates to:
  /// **'Ho gaya'**
  String get syncClashDone;

  /// No description provided for @chequeDone.
  ///
  /// In ur, this message translates to:
  /// **'Ho gaya'**
  String get chequeDone;

  /// Offered in the customer picker when the typed name matches nobody.
  ///
  /// In ur, this message translates to:
  /// **'\'{name}\' ko naya gahak banayein'**
  String quickAddCustomer(String name);

  /// Offered in the supplier picker on a purchase when the typed name matches nobody.
  ///
  /// In ur, this message translates to:
  /// **'\'{name}\' ko naya supplier banayein'**
  String quickAddSupplier(String name);

  /// Offered at the counter and on a purchase when an item search finds nothing.
  ///
  /// In ur, this message translates to:
  /// **'\'{name}\' ko naya maal banayein'**
  String quickAddItem(String name);

  /// Offered when a scanned barcode matches no item.
  ///
  /// In ur, this message translates to:
  /// **'Barcode {code} se naya maal banayein'**
  String quickAddBarcode(String code);

  /// Offered when a weighing-scale label's PLU matches no item's code.
  ///
  /// In ur, this message translates to:
  /// **'Code {code} se naya maal banayein'**
  String quickAddCode(String code);

  /// No description provided for @quickAddScaleHint.
  ///
  /// In ur, this message translates to:
  /// **'Code lag jaye to tarazu ka har label khud bill par aa jaye ga.'**
  String get quickAddScaleHint;

  /// No description provided for @quickBackToBill.
  ///
  /// In ur, this message translates to:
  /// **'Bill par wapas'**
  String get quickBackToBill;

  /// No description provided for @quickSupplierTitle.
  ///
  /// In ur, this message translates to:
  /// **'Naya supplier'**
  String get quickSupplierTitle;

  /// No description provided for @quickPartyMobile.
  ///
  /// In ur, this message translates to:
  /// **'Mobile (marzi se)'**
  String get quickPartyMobile;

  /// No description provided for @quickPartyMobileHint.
  ///
  /// In ur, this message translates to:
  /// **'0300 1234567'**
  String get quickPartyMobileHint;

  /// No description provided for @quickPartyMobileInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Mobile number is tarah likhein: 0300 1234567'**
  String get quickPartyMobileInvalid;

  /// No description provided for @quickPartyCreditLimit.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd (marzi se)'**
  String get quickPartyCreditLimit;

  /// No description provided for @quickPartyTwins.
  ///
  /// In ur, this message translates to:
  /// **'Yeh pehle se khata mein hain'**
  String get quickPartyTwins;

  /// No description provided for @quickPartyTwinsHint.
  ///
  /// In ur, this message translates to:
  /// **'Agar yehi hain to naam par tap karein. Koi aur hain to naya banayein.'**
  String get quickPartyTwinsHint;

  /// No description provided for @quickAddAnyway.
  ///
  /// In ur, this message translates to:
  /// **'Nahi, naya banayein'**
  String get quickAddAnyway;

  /// No description provided for @quickItemTwins.
  ///
  /// In ur, this message translates to:
  /// **'Yeh maal pehle se hai'**
  String get quickItemTwins;

  /// No description provided for @quickItemTwinsHint.
  ///
  /// In ur, this message translates to:
  /// **'Agar yehi hai to is par tap karein. Kuch aur hai to naya banayein.'**
  String get quickItemTwinsHint;

  /// No description provided for @quickItemBuyingAt.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ki qeemat (fi unit)'**
  String get quickItemBuyingAt;

  /// No description provided for @quickItemNoCost.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ki qeemat aur stock maalik baad mein Maal se daalein ge.'**
  String get quickItemNoCost;

  /// No description provided for @entryReceiptTitle.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli {no}'**
  String entryReceiptTitle(String no);

  /// No description provided for @entryPaymentTitle.
  ///
  /// In ur, this message translates to:
  /// **'Adaygi {no}'**
  String entryPaymentTitle(String no);

  /// No description provided for @entryDate.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh'**
  String get entryDate;

  /// No description provided for @entryHow.
  ///
  /// In ur, this message translates to:
  /// **'Kis tarah'**
  String get entryHow;

  /// No description provided for @entryAccount.
  ///
  /// In ur, this message translates to:
  /// **'Kis account mein'**
  String get entryAccount;

  /// No description provided for @entryFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kis se mile'**
  String get entryFrom;

  /// No description provided for @entryTo.
  ///
  /// In ur, this message translates to:
  /// **'Kis ko diye'**
  String get entryTo;

  /// No description provided for @entryReference.
  ///
  /// In ur, this message translates to:
  /// **'Reference ya note'**
  String get entryReference;

  /// No description provided for @entryEnteredBy.
  ///
  /// In ur, this message translates to:
  /// **'Kis ne likha'**
  String get entryEnteredBy;

  /// No description provided for @entrySettled.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill is se chuke'**
  String get entrySettled;

  /// No description provided for @entryShare.
  ///
  /// In ur, this message translates to:
  /// **'Raseed bhejein (PDF)'**
  String get entryShare;

  /// No description provided for @entryCancel.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh karein'**
  String get entryCancel;

  /// No description provided for @entryCancelTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh entry mansookh karein'**
  String get entryCancelTitle;

  /// No description provided for @entryCancelExplain.
  ///
  /// In ur, this message translates to:
  /// **'Kuch mit-ta nahi. Ulta ijraa aaj ki tareekh se likha jayega, asal entry \'mansookh\' ke nishan ke sath hisaab mein rahegi, aur jo bill is se chuke thay woh dobara baqi ho jayenge.'**
  String get entryCancelExplain;

  /// No description provided for @entryCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh'**
  String get entryCancelled;

  /// No description provided for @entryCancelledWhy.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh: {reason}'**
  String entryCancelledWhy(String reason);

  /// No description provided for @entryReplaces.
  ///
  /// In ur, this message translates to:
  /// **'{no} ki jagah likhi gayi'**
  String entryReplaces(String no);

  /// No description provided for @entryReplacedBy.
  ///
  /// In ur, this message translates to:
  /// **'Is ki jagah ab {no} hai'**
  String entryReplacedBy(String no);

  /// No description provided for @entryTakenWithBill.
  ///
  /// In ur, this message translates to:
  /// **'Yeh paisay bill {no} ke sath counter par liye gaye thay, is liye bill ke sath hi jayenge. Bill khol kar wapsi ya mansookhi karein.'**
  String entryTakenWithBill(String no);

  /// No description provided for @entryChequeAtBank.
  ///
  /// In ur, this message translates to:
  /// **'Cheque bank mein hai. Clear ya bounce hone ka intezar karein aur Cheque screen par darj karein.'**
  String get entryChequeAtBank;

  /// No description provided for @entryChequeCleared.
  ///
  /// In ur, this message translates to:
  /// **'Cheque clear ho chuka, paisay bank mein hain, is liye ab mansookh nahi ho sakta.'**
  String get entryChequeCleared;

  /// No description provided for @entryChequeBounced.
  ///
  /// In ur, this message translates to:
  /// **'Cheque bounce ho chuka. Jo is ne chukaya tha woh pehle hi wapas khate mein hai.'**
  String get entryChequeBounced;

  /// No description provided for @entryNotAllowed.
  ///
  /// In ur, this message translates to:
  /// **'Isay sirf malik, manager ya accountant badal ya mansookh kar sakte hain.'**
  String get entryNotAllowed;

  /// No description provided for @entryOpenBill.
  ///
  /// In ur, this message translates to:
  /// **'Bill kholein'**
  String get entryOpenBill;

  /// No description provided for @entryEditTitle.
  ///
  /// In ur, this message translates to:
  /// **'{no} theek karein'**
  String entryEditTitle(String no);

  /// No description provided for @entryEditExplain.
  ///
  /// In ur, this message translates to:
  /// **'Purani entry mansookh hogi aur theek wali aaj ki tareekh se likhi jayegi. Dono hisaab mein rahengi.'**
  String get entryEditExplain;

  /// No description provided for @entryEditReason.
  ///
  /// In ur, this message translates to:
  /// **'Kya galat tha (marzi se)'**
  String get entryEditReason;

  /// No description provided for @entryEditReasonDefault.
  ///
  /// In ur, this message translates to:
  /// **'Galat likha gaya tha'**
  String get entryEditReasonDefault;

  /// No description provided for @entryEditSave.
  ///
  /// In ur, this message translates to:
  /// **'Tabdeeli save karein'**
  String get entryEditSave;

  /// No description provided for @entryEditSaved.
  ///
  /// In ur, this message translates to:
  /// **'{no} theek ho gaya, ab {newNo}'**
  String entryEditSaved(String no, String newNo);

  /// No description provided for @entryPaidBy.
  ///
  /// In ur, this message translates to:
  /// **'Is par {nos} ki adaygi ho chuki hai. Pehle woh khol kar mansookh karein.'**
  String entryPaidBy(String nos);

  /// No description provided for @chargeEntryHint.
  ///
  /// In ur, this message translates to:
  /// **'{amount} ka charge. Raqam ya wajah galat hai to theek karein; ghalti se dala tha to wapas lein.'**
  String chargeEntryHint(String amount);

  /// No description provided for @openingTitle.
  ///
  /// In ur, this message translates to:
  /// **'Purana baqaya theek karein'**
  String get openingTitle;

  /// No description provided for @openingNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi likha hai'**
  String get openingNow;

  /// No description provided for @openingNew.
  ///
  /// In ur, this message translates to:
  /// **'Sahi purana baqaya'**
  String get openingNew;

  /// No description provided for @openingExplain.
  ///
  /// In ur, this message translates to:
  /// **'Purana ijraa ulta ho kar sahi raqam ka naya likha jayega. Khate ki shuruat ka baqaya isi se badlega.'**
  String get openingExplain;

  /// No description provided for @openingCorrect.
  ///
  /// In ur, this message translates to:
  /// **'Theek karein'**
  String get openingCorrect;

  /// No description provided for @openingSaved.
  ///
  /// In ur, this message translates to:
  /// **'Purana baqaya theek ho gaya'**
  String get openingSaved;

  /// No description provided for @reasonPick.
  ///
  /// In ur, this message translates to:
  /// **'Wajah chunein'**
  String get reasonPick;

  /// No description provided for @reasonWrongEntry.
  ///
  /// In ur, this message translates to:
  /// **'Galat entry'**
  String get reasonWrongEntry;

  /// No description provided for @reasonDuplicate.
  ///
  /// In ur, this message translates to:
  /// **'Do baar likh di'**
  String get reasonDuplicate;

  /// No description provided for @reasonWrongAmount.
  ///
  /// In ur, this message translates to:
  /// **'Galat raqam'**
  String get reasonWrongAmount;

  /// No description provided for @reasonDispute.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ka ikhtilaf'**
  String get reasonDispute;

  /// No description provided for @reasonOther.
  ///
  /// In ur, this message translates to:
  /// **'Kuch aur'**
  String get reasonOther;

  /// No description provided for @reasonDetail.
  ///
  /// In ur, this message translates to:
  /// **'Tafseel (marzi se)'**
  String get reasonDetail;

  /// No description provided for @entryCancelledBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne {when} ko mansookh kiya'**
  String entryCancelledBy(String name, String when);

  /// No description provided for @salesSearch.
  ///
  /// In ur, this message translates to:
  /// **'Bill talash karein'**
  String get salesSearch;

  /// No description provided for @salesSearchHint.
  ///
  /// In ur, this message translates to:
  /// **'Bill number, naam, phone ya raqam'**
  String get salesSearchHint;

  /// No description provided for @salesClearSearch.
  ///
  /// In ur, this message translates to:
  /// **'Talash saaf karein'**
  String get salesClearSearch;

  /// No description provided for @salesPeriodAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab din'**
  String get salesPeriodAll;

  /// No description provided for @salesPeriodToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj'**
  String get salesPeriodToday;

  /// No description provided for @salesPeriodWeek.
  ///
  /// In ur, this message translates to:
  /// **'Is hafte'**
  String get salesPeriodWeek;

  /// No description provided for @salesPeriodMonth.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine'**
  String get salesPeriodMonth;

  /// No description provided for @salesPeriodLastMonth.
  ///
  /// In ur, this message translates to:
  /// **'Pichhle mahine'**
  String get salesPeriodLastMonth;

  /// No description provided for @salesPeriodPick.
  ///
  /// In ur, this message translates to:
  /// **'Tareekhen chunein'**
  String get salesPeriodPick;

  /// No description provided for @salesPeriodRange.
  ///
  /// In ur, this message translates to:
  /// **'{from} se {to}'**
  String salesPeriodRange(String from, String to);

  /// No description provided for @salesStandingAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab bill'**
  String get salesStandingAll;

  /// No description provided for @salesStandingPaid.
  ///
  /// In ur, this message translates to:
  /// **'Ada ho chuke'**
  String get salesStandingPaid;

  /// No description provided for @salesStandingUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar wale'**
  String get salesStandingUdhaar;

  /// No description provided for @salesStandingCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh kiye'**
  String get salesStandingCancelled;

  /// No description provided for @salesNoneFound.
  ///
  /// In ur, this message translates to:
  /// **'Is talash par koi bill nahi'**
  String get salesNoneFound;

  /// No description provided for @salesNoneFoundHint.
  ///
  /// In ur, this message translates to:
  /// **'Doosra naam, number ya tareekh aazma kar dekhein'**
  String get salesNoneFoundHint;

  /// No description provided for @salesClearFilters.
  ///
  /// In ur, this message translates to:
  /// **'Sab bill dikhayein'**
  String get salesClearFilters;

  /// No description provided for @sendAction.
  ///
  /// In ur, this message translates to:
  /// **'Bhejein'**
  String get sendAction;

  /// No description provided for @sendTitle.
  ///
  /// In ur, this message translates to:
  /// **'Bhejein: {docNo}'**
  String sendTitle(String docNo);

  /// No description provided for @sendWalkIn.
  ///
  /// In ur, this message translates to:
  /// **'Aam gahak, koi number nahi'**
  String get sendWalkIn;

  /// No description provided for @sendWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp par bhejein'**
  String get sendWhatsApp;

  /// No description provided for @sendWhatsAppShort.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp'**
  String get sendWhatsAppShort;

  /// No description provided for @sendWhatsAppTo.
  ///
  /// In ur, this message translates to:
  /// **'{name} ki chat khulegi, bill ki tafseel likhi hui'**
  String sendWhatsAppTo(String name);

  /// No description provided for @sendWhatsAppNoNumber.
  ///
  /// In ur, this message translates to:
  /// **'Number nahi hai, PDF share sheet se jayegi'**
  String get sendWhatsAppNoNumber;

  /// No description provided for @sendNoNumber.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ka WhatsApp number nahi, PDF share sheet se bheji'**
  String get sendNoNumber;

  /// No description provided for @sendNoWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par WhatsApp nahi mila, PDF share sheet se bheji'**
  String get sendNoWhatsApp;

  /// No description provided for @sendPdfHint.
  ///
  /// In ur, this message translates to:
  /// **'File, saath mein bill ki tafseel'**
  String get sendPdfHint;

  /// No description provided for @sendPicture.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer bhejein'**
  String get sendPicture;

  /// No description provided for @sendPictureShort.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer'**
  String get sendPictureShort;

  /// No description provided for @sendPictureHint.
  ///
  /// In ur, this message translates to:
  /// **'Bill ki tasveer, chat mein seedha khulti hai'**
  String get sendPictureHint;

  /// No description provided for @sendPrintHint.
  ///
  /// In ur, this message translates to:
  /// **'Is counter ke printer par'**
  String get sendPrintHint;

  /// No description provided for @documentView.
  ///
  /// In ur, this message translates to:
  /// **'Poora dekhein'**
  String get documentView;

  /// No description provided for @purchaseSendBack.
  ///
  /// In ur, this message translates to:
  /// **'Maal wapas karein'**
  String get purchaseSendBack;

  /// No description provided for @reportGroupTransaction.
  ///
  /// In ur, this message translates to:
  /// **'Len den'**
  String get reportGroupTransaction;

  /// No description provided for @reportGroupParty.
  ///
  /// In ur, this message translates to:
  /// **'Party ki report'**
  String get reportGroupParty;

  /// No description provided for @reportGroupItemStock.
  ///
  /// In ur, this message translates to:
  /// **'Cheezen aur stock'**
  String get reportGroupItemStock;

  /// No description provided for @reportGroupBusiness.
  ///
  /// In ur, this message translates to:
  /// **'Karobar ki halat'**
  String get reportGroupBusiness;

  /// No description provided for @reportGroupTaxes.
  ///
  /// In ur, this message translates to:
  /// **'Tax'**
  String get reportGroupTaxes;

  /// No description provided for @reportGroupExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharchay'**
  String get reportGroupExpense;

  /// No description provided for @reportGroupOrders.
  ///
  /// In ur, this message translates to:
  /// **'Bikri aur khareed ke order'**
  String get reportGroupOrders;

  /// No description provided for @reportGroupLoans.
  ///
  /// In ur, this message translates to:
  /// **'Qarz ke khate'**
  String get reportGroupLoans;

  /// No description provided for @reportFavourites.
  ///
  /// In ur, this message translates to:
  /// **'Pasandeeda'**
  String get reportFavourites;

  /// No description provided for @reportRecent.
  ///
  /// In ur, this message translates to:
  /// **'Haal hi mein khole'**
  String get reportRecent;

  /// No description provided for @reportSearchHint.
  ///
  /// In ur, this message translates to:
  /// **'Report ka naam likhein'**
  String get reportSearchHint;

  /// No description provided for @reportSearchNone.
  ///
  /// In ur, this message translates to:
  /// **'Is naam ki koi report nahi'**
  String get reportSearchNone;

  /// No description provided for @reportStar.
  ///
  /// In ur, this message translates to:
  /// **'Pasandeeda mein daalein'**
  String get reportStar;

  /// No description provided for @reportUnstar.
  ///
  /// In ur, this message translates to:
  /// **'Pasandeeda se hatayein'**
  String get reportUnstar;

  /// No description provided for @reportSale.
  ///
  /// In ur, this message translates to:
  /// **'Bikri report'**
  String get reportSale;

  /// No description provided for @reportSaleHint.
  ///
  /// In ur, this message translates to:
  /// **'Har bill: kul, kitna mila, kitna baqi, kaise diya'**
  String get reportSaleHint;

  /// No description provided for @reportPurchase.
  ///
  /// In ur, this message translates to:
  /// **'Khareed report'**
  String get reportPurchase;

  /// No description provided for @reportPurchaseHint.
  ///
  /// In ur, this message translates to:
  /// **'Har khareed ka bill: kul, kitna diya, kitna baqi'**
  String get reportPurchaseHint;

  /// No description provided for @reportAllTransactions.
  ///
  /// In ur, this message translates to:
  /// **'Tamam len den'**
  String get reportAllTransactions;

  /// No description provided for @reportAllTransactionsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har bill, wapsi, kharcha aur payment, ek jagah'**
  String get reportAllTransactionsHint;

  /// No description provided for @reportBillWiseProfit.
  ///
  /// In ur, this message translates to:
  /// **'Bill-war nafa'**
  String get reportBillWiseProfit;

  /// No description provided for @reportBillWiseProfitHint.
  ///
  /// In ur, this message translates to:
  /// **'Har bill par laagat se upar kitna kamaya'**
  String get reportBillWiseProfitHint;

  /// No description provided for @reportCashflow.
  ///
  /// In ur, this message translates to:
  /// **'Cash flow'**
  String get reportCashflow;

  /// No description provided for @reportCashflowHint.
  ///
  /// In ur, this message translates to:
  /// **'Galle aur bank mein paisa kahan se aaya, kahan gaya'**
  String get reportCashflowHint;

  /// No description provided for @reportPartyStatement.
  ///
  /// In ur, this message translates to:
  /// **'Party ka statement'**
  String get reportPartyStatement;

  /// No description provided for @reportPartyStatementHint.
  ///
  /// In ur, this message translates to:
  /// **'Ek party ka poora hisaab, har entry ke baad baqi'**
  String get reportPartyStatementHint;

  /// No description provided for @reportPartyProfit.
  ///
  /// In ur, this message translates to:
  /// **'Party-war nafa nuqsan'**
  String get reportPartyProfit;

  /// No description provided for @reportPartyProfitHint.
  ///
  /// In ur, this message translates to:
  /// **'Kis gahak se kitna nafa hua'**
  String get reportPartyProfitHint;

  /// No description provided for @reportAllParties.
  ///
  /// In ur, this message translates to:
  /// **'Tamam parties'**
  String get reportAllParties;

  /// No description provided for @reportAllPartiesHint.
  ///
  /// In ur, this message translates to:
  /// **'Har party ka lena, dena aur udhaar ki hadd'**
  String get reportAllPartiesHint;

  /// No description provided for @reportPartyItems.
  ///
  /// In ur, this message translates to:
  /// **'Party ki cheezen'**
  String get reportPartyItems;

  /// No description provided for @reportPartyItemsHint.
  ///
  /// In ur, this message translates to:
  /// **'Party ne kaunsi cheez kitni li ya di'**
  String get reportPartyItemsHint;

  /// No description provided for @reportSalePurchaseByParty.
  ///
  /// In ur, this message translates to:
  /// **'Party-war bikri aur khareed'**
  String get reportSalePurchaseByParty;

  /// No description provided for @reportSalePurchaseByPartyHint.
  ///
  /// In ur, this message translates to:
  /// **'Har party ko kitna becha, us se kitna khareeda'**
  String get reportSalePurchaseByPartyHint;

  /// No description provided for @reportSalePurchaseByGroup.
  ///
  /// In ur, this message translates to:
  /// **'Group-war bikri aur khareed'**
  String get reportSalePurchaseByGroup;

  /// No description provided for @reportSalePurchaseByGroupHint.
  ///
  /// In ur, this message translates to:
  /// **'Har party group ki bikri aur khareed'**
  String get reportSalePurchaseByGroupHint;

  /// No description provided for @reportYesterday.
  ///
  /// In ur, this message translates to:
  /// **'Kal'**
  String get reportYesterday;

  /// No description provided for @reportThisWeek.
  ///
  /// In ur, this message translates to:
  /// **'Is hafta'**
  String get reportThisWeek;

  /// No description provided for @reportThisQuarter.
  ///
  /// In ur, this message translates to:
  /// **'Yeh teen mahine'**
  String get reportThisQuarter;

  /// No description provided for @reportLastYear.
  ///
  /// In ur, this message translates to:
  /// **'Pichla saal'**
  String get reportLastYear;

  /// No description provided for @reportCustom.
  ///
  /// In ur, this message translates to:
  /// **'Apni tareekhen'**
  String get reportCustom;

  /// No description provided for @reportFilterParty.
  ///
  /// In ur, this message translates to:
  /// **'Party'**
  String get reportFilterParty;

  /// No description provided for @reportFilterItem.
  ///
  /// In ur, this message translates to:
  /// **'Cheez'**
  String get reportFilterItem;

  /// No description provided for @reportFilterCategory.
  ///
  /// In ur, this message translates to:
  /// **'Cheez ki qisam'**
  String get reportFilterCategory;

  /// No description provided for @reportFilterGroup.
  ///
  /// In ur, this message translates to:
  /// **'Party group'**
  String get reportFilterGroup;

  /// No description provided for @reportFilterType.
  ///
  /// In ur, this message translates to:
  /// **'Len den ki qisam'**
  String get reportFilterType;

  /// No description provided for @reportFilterMode.
  ///
  /// In ur, this message translates to:
  /// **'Kaise diya'**
  String get reportFilterMode;

  /// No description provided for @reportFilterUser.
  ///
  /// In ur, this message translates to:
  /// **'Kis ne likha'**
  String get reportFilterUser;

  /// No description provided for @reportFilterStatus.
  ///
  /// In ur, this message translates to:
  /// **'Adaigi'**
  String get reportFilterStatus;

  /// No description provided for @reportFilterWithBalance.
  ///
  /// In ur, this message translates to:
  /// **'Sirf jin ka baqi hai'**
  String get reportFilterWithBalance;

  /// No description provided for @reportFilterClear.
  ///
  /// In ur, this message translates to:
  /// **'Hatayein'**
  String get reportFilterClear;

  /// No description provided for @reportFilterNothing.
  ///
  /// In ur, this message translates to:
  /// **'Kuch nahi mila'**
  String get reportFilterNothing;

  /// No description provided for @reportFilterUngrouped.
  ///
  /// In ur, this message translates to:
  /// **'Bina group'**
  String get reportFilterUngrouped;

  /// No description provided for @reportStatusPaid.
  ///
  /// In ur, this message translates to:
  /// **'Poora mila'**
  String get reportStatusPaid;

  /// No description provided for @reportStatusPartial.
  ///
  /// In ur, this message translates to:
  /// **'Kuch mila'**
  String get reportStatusPartial;

  /// No description provided for @reportStatusUnpaid.
  ///
  /// In ur, this message translates to:
  /// **'Kuch nahi mila'**
  String get reportStatusUnpaid;

  /// No description provided for @reportTypeSale.
  ///
  /// In ur, this message translates to:
  /// **'Bikri'**
  String get reportTypeSale;

  /// No description provided for @reportTypeSaleReturn.
  ///
  /// In ur, this message translates to:
  /// **'Bikri ki wapsi'**
  String get reportTypeSaleReturn;

  /// No description provided for @reportTypePurchase.
  ///
  /// In ur, this message translates to:
  /// **'Khareed'**
  String get reportTypePurchase;

  /// No description provided for @reportTypePurchaseReturn.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ki wapsi'**
  String get reportTypePurchaseReturn;

  /// No description provided for @reportTypeExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharcha'**
  String get reportTypeExpense;

  /// No description provided for @reportTypeCharge.
  ///
  /// In ur, this message translates to:
  /// **'Charge ya doosri aamdani'**
  String get reportTypeCharge;

  /// No description provided for @reportTypeQuotation.
  ///
  /// In ur, this message translates to:
  /// **'Quotation'**
  String get reportTypeQuotation;

  /// No description provided for @reportTypeChallan.
  ///
  /// In ur, this message translates to:
  /// **'Challan'**
  String get reportTypeChallan;

  /// No description provided for @reportTypeSaleOrder.
  ///
  /// In ur, this message translates to:
  /// **'Bikri ka order'**
  String get reportTypeSaleOrder;

  /// No description provided for @reportTypePurchaseOrder.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ka order'**
  String get reportTypePurchaseOrder;

  /// No description provided for @reportTypeProforma.
  ///
  /// In ur, this message translates to:
  /// **'Proforma'**
  String get reportTypeProforma;

  /// No description provided for @reportTypePaymentIn.
  ///
  /// In ur, this message translates to:
  /// **'Paisay aaye'**
  String get reportTypePaymentIn;

  /// No description provided for @reportTypePaymentOut.
  ///
  /// In ur, this message translates to:
  /// **'Paisay diye'**
  String get reportTypePaymentOut;

  /// No description provided for @reportShareExcel.
  ///
  /// In ur, this message translates to:
  /// **'Excel bhejein'**
  String get reportShareExcel;

  /// No description provided for @reportShowMore.
  ///
  /// In ur, this message translates to:
  /// **'Aur dikhayein ({shown} / {total})'**
  String reportShowMore(int shown, int total);

  /// No description provided for @reportChooseParty.
  ///
  /// In ur, this message translates to:
  /// **'Statement dekhne ke liye party chunein'**
  String get reportChooseParty;

  /// No description provided for @reportVsPrevious.
  ///
  /// In ur, this message translates to:
  /// **'{change} pichli dafa se'**
  String reportVsPrevious(String change);

  /// No description provided for @reportSortedBy.
  ///
  /// In ur, this message translates to:
  /// **'{column} se tarteeb'**
  String reportSortedBy(String column);

  /// No description provided for @reportExcel.
  ///
  /// In ur, this message translates to:
  /// **'Excel'**
  String get reportExcel;

  /// No description provided for @reportCsv.
  ///
  /// In ur, this message translates to:
  /// **'CSV'**
  String get reportCsv;

  /// No description provided for @reportPrint.
  ///
  /// In ur, this message translates to:
  /// **'Print'**
  String get reportPrint;

  /// No description provided for @reportPrintTitle.
  ///
  /// In ur, this message translates to:
  /// **'Printer par chhapein'**
  String get reportPrintTitle;

  /// Loans the shop has taken (M48): the screen, and the button to it in Accounts.
  ///
  /// In ur, this message translates to:
  /// **'Qarzay'**
  String get loansTitle;

  /// No description provided for @loansNew.
  ///
  /// In ur, this message translates to:
  /// **'Naya qarza'**
  String get loansNew;

  /// No description provided for @loansEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Koi qarza nahi'**
  String get loansEmpty;

  /// No description provided for @loansEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Bank, committee, rishtedar ya supplier se liya qarza yahan likhein. Har qist mein asal aur sood alag likha jaye ga.'**
  String get loansEmptyHint;

  /// No description provided for @loansTotalOwed.
  ///
  /// In ur, this message translates to:
  /// **'Kul baqi qarza'**
  String get loansTotalOwed;

  /// No description provided for @loanOwed.
  ///
  /// In ur, this message translates to:
  /// **'Baqi'**
  String get loanOwed;

  /// No description provided for @loanOf.
  ///
  /// In ur, this message translates to:
  /// **'{amount} mein se'**
  String loanOf(String amount);

  /// No description provided for @loanTakenOn.
  ///
  /// In ur, this message translates to:
  /// **'Liya: {date}'**
  String loanTakenOn(String date);

  /// No description provided for @loanCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Cancel ho gaya'**
  String get loanCancelled;

  /// No description provided for @loanLender.
  ///
  /// In ur, this message translates to:
  /// **'Kis se liya (bank, committee, rishtedar)'**
  String get loanLender;

  /// No description provided for @loanAmount.
  ///
  /// In ur, this message translates to:
  /// **'Qarze ki raqam'**
  String get loanAmount;

  /// No description provided for @loanInto.
  ///
  /// In ur, this message translates to:
  /// **'Paisay kahan aaye'**
  String get loanInto;

  /// No description provided for @loanDate.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh: {date}'**
  String loanDate(String date);

  /// No description provided for @loanPickDate.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh badlein'**
  String get loanPickDate;

  /// No description provided for @loanRate.
  ///
  /// In ur, this message translates to:
  /// **'Sood (markup), % saalana (marzi se)'**
  String get loanRate;

  /// No description provided for @loanTerm.
  ///
  /// In ur, this message translates to:
  /// **'Kitne mahine mein wapis (marzi se)'**
  String get loanTerm;

  /// No description provided for @loanInstalment.
  ///
  /// In ur, this message translates to:
  /// **'Mahana qist (marzi se)'**
  String get loanInstalment;

  /// No description provided for @loanFee.
  ///
  /// In ur, this message translates to:
  /// **'Processing fee (marzi se)'**
  String get loanFee;

  /// No description provided for @loanReceivedAfterFee.
  ///
  /// In ur, this message translates to:
  /// **'Fee ke baad haath mein: {amount}'**
  String loanReceivedAfterFee(String amount);

  /// No description provided for @loanNotes.
  ///
  /// In ur, this message translates to:
  /// **'Note (marzi se)'**
  String get loanNotes;

  /// No description provided for @loanSave.
  ///
  /// In ur, this message translates to:
  /// **'Qarza save karein'**
  String get loanSave;

  /// No description provided for @loanSaved.
  ///
  /// In ur, this message translates to:
  /// **'Qarza save ho gaya'**
  String get loanSaved;

  /// No description provided for @loanRepay.
  ///
  /// In ur, this message translates to:
  /// **'Qist dein'**
  String get loanRepay;

  /// No description provided for @loanPaid.
  ///
  /// In ur, this message translates to:
  /// **'Kitne diye'**
  String get loanPaid;

  /// No description provided for @loanInterest.
  ///
  /// In ur, this message translates to:
  /// **'Is mein sood (markup)'**
  String get loanInterest;

  /// No description provided for @loanCharges.
  ///
  /// In ur, this message translates to:
  /// **'Charges ya jurmana (marzi se)'**
  String get loanCharges;

  /// No description provided for @loanFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kahan se diye'**
  String get loanFrom;

  /// No description provided for @loanPrincipalLine.
  ///
  /// In ur, this message translates to:
  /// **'Qarze mein se kam'**
  String get loanPrincipalLine;

  /// No description provided for @loanAfterLine.
  ///
  /// In ur, this message translates to:
  /// **'Is ke baad baqi'**
  String get loanAfterLine;

  /// No description provided for @loanRepaySave.
  ///
  /// In ur, this message translates to:
  /// **'Qist save karein'**
  String get loanRepaySave;

  /// No description provided for @loanRepaid.
  ///
  /// In ur, this message translates to:
  /// **'Qist {entryNo} save ho gayi'**
  String loanRepaid(String entryNo);

  /// No description provided for @loanInterestSuggested.
  ///
  /// In ur, this message translates to:
  /// **'Sood {rate} saalana ke hisaab se lagaya hai. Bank ki parchi se theek kar lein.'**
  String loanInterestSuggested(String rate);

  /// No description provided for @loanSharePdf.
  ///
  /// In ur, this message translates to:
  /// **'Statement (PDF)'**
  String get loanSharePdf;

  /// No description provided for @loanShareCsv.
  ///
  /// In ur, this message translates to:
  /// **'Statement (Excel, CSV)'**
  String get loanShareCsv;

  /// No description provided for @loanOpening.
  ///
  /// In ur, this message translates to:
  /// **'Shuru mein baqi'**
  String get loanOpening;

  /// No description provided for @loanClosing.
  ///
  /// In ur, this message translates to:
  /// **'Aakhir mein baqi'**
  String get loanClosing;

  /// No description provided for @loanKindReceived.
  ///
  /// In ur, this message translates to:
  /// **'Qarza mila'**
  String get loanKindReceived;

  /// No description provided for @loanKindRepaid.
  ///
  /// In ur, this message translates to:
  /// **'Qist di'**
  String get loanKindRepaid;

  /// No description provided for @loanKindCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Cancel kiya'**
  String get loanKindCancelled;

  /// No description provided for @loanColBorrowed.
  ///
  /// In ur, this message translates to:
  /// **'Mila'**
  String get loanColBorrowed;

  /// No description provided for @loanColPrincipal.
  ///
  /// In ur, this message translates to:
  /// **'Asal'**
  String get loanColPrincipal;

  /// No description provided for @loanColInterest.
  ///
  /// In ur, this message translates to:
  /// **'Sood'**
  String get loanColInterest;

  /// No description provided for @loanColCharges.
  ///
  /// In ur, this message translates to:
  /// **'Fee, charges'**
  String get loanColCharges;

  /// No description provided for @loanCancelEntry.
  ///
  /// In ur, this message translates to:
  /// **'Ghalat hai, cancel karein'**
  String get loanCancelEntry;

  /// No description provided for @loanCancelReason.
  ///
  /// In ur, this message translates to:
  /// **'Kyun cancel kar rahe hain (zaroori)'**
  String get loanCancelReason;

  /// No description provided for @loanCancelDone.
  ///
  /// In ur, this message translates to:
  /// **'Cancel ho gaya ({entryNo})'**
  String loanCancelDone(String entryNo);

  /// No description provided for @loanRateShown.
  ///
  /// In ur, this message translates to:
  /// **'{rate} saalana'**
  String loanRateShown(String rate);

  /// No description provided for @loanInstalmentShown.
  ///
  /// In ur, this message translates to:
  /// **'Qist {amount}'**
  String loanInstalmentShown(String amount);

  /// No description provided for @loanAmountInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Raqam theek likhein, jaise 25000 ya 2500.50'**
  String get loanAmountInvalid;

  /// Tooltip of the counter's customer button: who the bill is for (M37).
  ///
  /// In ur, this message translates to:
  /// **'Bill kis ke naam'**
  String get posBillTo;

  /// The empty counter, once a customer has been chosen for the bill.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka bill abhi khali hai'**
  String posCartEmptyFor(String name);

  /// A line sold by description and amount with no item behind it (M37).
  ///
  /// In ur, this message translates to:
  /// **'Khula maal'**
  String get looseTitle;

  /// No description provided for @looseHint.
  ///
  /// In ur, this message translates to:
  /// **'Cheez banaye baghair bechein. Maal ki list mein kuch save nahi hoga aur stock nahi hile ga.'**
  String get looseHint;

  /// No description provided for @looseName.
  ///
  /// In ur, this message translates to:
  /// **'Kya hai (marzi se)'**
  String get looseName;

  /// No description provided for @looseNameHint.
  ///
  /// In ur, this message translates to:
  /// **'Maslan: pyaz'**
  String get looseNameHint;

  /// No description provided for @looseRate.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat (fi unit, ya poori raqam)'**
  String get looseRate;

  /// No description provided for @looseAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam: {amount}'**
  String looseAmount(String amount);

  /// No description provided for @looseAdd.
  ///
  /// In ur, this message translates to:
  /// **'Bill mein daalein'**
  String get looseAdd;

  /// Shown to roles that may see costs: a loose line has no cost, so profit counts all of it.
  ///
  /// In ur, this message translates to:
  /// **'Is ki laagat maloom nahi, is liye munafe mein yeh poori raqam munafa gini jaye gi.'**
  String get looseNoCost;

  /// No description provided for @looseNeedsPrice.
  ///
  /// In ur, this message translates to:
  /// **'Tadaad aur qeemat likhein'**
  String get looseNeedsPrice;

  /// No description provided for @looseFbrRefused.
  ///
  /// In ur, this message translates to:
  /// **'Yeh dukaan FBR ko bill bhejti hai, aur FBR ko har line ka HS code chahiye. Khula maal ki jagah is ki cheez bana kar bechein.'**
  String get looseFbrRefused;

  /// No description provided for @looseNotKept.
  ///
  /// In ur, this message translates to:
  /// **'Khula maal quotation ya challan par nahi ja sakta. Is ki cheez banayein, ya abhi bill banayein.'**
  String get looseNotKept;

  /// Offered at the counter when an item search finds nothing: sell what was typed as a loose line.
  ///
  /// In ur, this message translates to:
  /// **'\'{name}\' khula bechein (cheez nahi banegi)'**
  String looseOffer(String name);

  /// No description provided for @looseBadge.
  ///
  /// In ur, this message translates to:
  /// **'Khula maal · stock nahi'**
  String get looseBadge;

  /// Heading over the customer's last prices for an item (M37).
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ko pichhli dafa'**
  String get dealsSoldTitle;

  /// Heading over the supplier's last prices for an item on a delivery (M37).
  ///
  /// In ur, this message translates to:
  /// **'Is supplier se pichhli khareed'**
  String get dealsBoughtTitle;

  /// No description provided for @dealsTapHint.
  ///
  /// In ur, this message translates to:
  /// **'Kisi par tap karein to wohi qeemat is line par lag jaye gi.'**
  String get dealsTapHint;

  /// On a counter line: what this customer paid for it last time, and when.
  ///
  /// In ur, this message translates to:
  /// **'Pichhli dafa {price} · {date}'**
  String dealLastTime(String price, String date);

  /// No description provided for @dealOtherUnit.
  ///
  /// In ur, this message translates to:
  /// **'Yeh qeemat {unit} ki hai. Pehle line ko {unit} mein karein.'**
  String dealOtherUnit(String unit);

  /// Screen-reader label for one earlier price.
  ///
  /// In ur, this message translates to:
  /// **'Yeh qeemat lagayein: {price}'**
  String dealUse(String price);

  /// Shown only to roles that may see costs: the last delivery of this item.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri khareed {price} · {supplier} · {date}'**
  String dealLastBought(String price, String supplier, String date);

  /// Heads the counter's lines once a customer is named (M37).
  ///
  /// In ur, this message translates to:
  /// **'{name} ka bill'**
  String posBillFor(String name);

  /// M40. The area, route or kind of customer a party is filed under.
  ///
  /// In ur, this message translates to:
  /// **'Group (marzi se)'**
  String get partyGroup;

  /// No description provided for @partyGroupHint.
  ///
  /// In ur, this message translates to:
  /// **'Mohalla, route ya qisam'**
  String get partyGroupHint;

  /// M40. A note about the customer shown to the cashier on the payment sheet.
  ///
  /// In ur, this message translates to:
  /// **'Counter ke liye note'**
  String get partyRemarks;

  /// No description provided for @partyRemarksHint.
  ///
  /// In ur, this message translates to:
  /// **'Jaise: Sirf cash — cheque bounce ho chuka'**
  String get partyRemarksHint;

  /// No description provided for @groupsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Group'**
  String get groupsTitle;

  /// No description provided for @groupsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi group nahi'**
  String get groupsEmpty;

  /// No description provided for @groupsEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ke form mein group likhein — mohalla, route ya qisam — ya list mein kai gahak chun kar ek saath group lagayein'**
  String get groupsEmptyHint;

  /// No description provided for @groupAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab'**
  String get groupAll;

  /// No description provided for @groupNone.
  ///
  /// In ur, this message translates to:
  /// **'Baghair group'**
  String get groupNone;

  /// No description provided for @groupMembers.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 shakhs} other{{count} log}}'**
  String groupMembers(int count);

  /// No description provided for @groupReceivable.
  ///
  /// In ur, this message translates to:
  /// **'Lene hain'**
  String get groupReceivable;

  /// No description provided for @groupPayable.
  ///
  /// In ur, this message translates to:
  /// **'Dene hain'**
  String get groupPayable;

  /// No description provided for @groupRename.
  ///
  /// In ur, this message translates to:
  /// **'Naam badlein'**
  String get groupRename;

  /// No description provided for @groupNewName.
  ///
  /// In ur, this message translates to:
  /// **'Naya naam'**
  String get groupNewName;

  /// No description provided for @groupRenameMerges.
  ///
  /// In ur, this message translates to:
  /// **'\'{name}\' pehle se hai — dono group ek ho jayenge'**
  String groupRenameMerges(String name);

  /// No description provided for @groupMerge.
  ///
  /// In ur, this message translates to:
  /// **'Doosre group mein milayein'**
  String get groupMerge;

  /// No description provided for @groupMergeInto.
  ///
  /// In ur, this message translates to:
  /// **'Kis group mein milana hai?'**
  String get groupMergeInto;

  /// No description provided for @groupMergeConfirm.
  ///
  /// In ur, this message translates to:
  /// **'\'{from}\' ke sab log \'{to}\' mein chale jayenge, aur \'{from}\' khatam ho jayega.'**
  String groupMergeConfirm(String from, String to);

  /// No description provided for @groupNoOther.
  ///
  /// In ur, this message translates to:
  /// **'Milane ke liye koi doosra group nahi'**
  String get groupNoOther;

  /// No description provided for @groupMoved.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 shakhs \'{name}\' mein} other{{count} log \'{name}\' mein}}'**
  String groupMoved(int count, String name);

  /// No description provided for @groupCleared.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 shakhs group se bahar} other{{count} log group se bahar}}'**
  String groupCleared(int count);

  /// No description provided for @groupSet.
  ///
  /// In ur, this message translates to:
  /// **'Group lagayein'**
  String get groupSet;

  /// No description provided for @groupSetFor.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak ka group} other{{count} gahak ka group}}'**
  String groupSetFor(int count);

  /// No description provided for @groupClear.
  ///
  /// In ur, this message translates to:
  /// **'Group se nikalein'**
  String get groupClear;

  /// No description provided for @groupMembersTitle.
  ///
  /// In ur, this message translates to:
  /// **'Is group ke log'**
  String get groupMembersTitle;

  /// No description provided for @groupNobody.
  ///
  /// In ur, this message translates to:
  /// **'Is group mein koi nahi'**
  String get groupNobody;

  /// No description provided for @partiesSelect.
  ///
  /// In ur, this message translates to:
  /// **'Kai gahak chunein'**
  String get partiesSelect;

  /// No description provided for @partiesSelected.
  ///
  /// In ur, this message translates to:
  /// **'{count} chune'**
  String partiesSelected(int count);

  /// No description provided for @partiesSort.
  ///
  /// In ur, this message translates to:
  /// **'Tarteeb'**
  String get partiesSort;

  /// No description provided for @partiesSortName.
  ///
  /// In ur, this message translates to:
  /// **'Naam se'**
  String get partiesSortName;

  /// No description provided for @partiesSortBalance.
  ///
  /// In ur, this message translates to:
  /// **'Zyada udhaar pehle'**
  String get partiesSortBalance;

  /// No description provided for @partiesSortOldest.
  ///
  /// In ur, this message translates to:
  /// **'Sab se purana udhaar pehle'**
  String get partiesSortOldest;

  /// No description provided for @partiesCapped.
  ///
  /// In ur, this message translates to:
  /// **'Pehle {count} dikhaye — baqi talash se dhoondein'**
  String partiesCapped(int count);

  /// No description provided for @importFromWhere.
  ///
  /// In ur, this message translates to:
  /// **'Yeh file kahan se aayi hai?'**
  String get importFromWhere;

  /// No description provided for @importSourceOurs.
  ///
  /// In ur, this message translates to:
  /// **'Bazaar Ledger ki list'**
  String get importSourceOurs;

  /// No description provided for @importSourceVyaparItems.
  ///
  /// In ur, this message translates to:
  /// **'Vyapar ka maal'**
  String get importSourceVyaparItems;

  /// No description provided for @importSourceVyaparParties.
  ///
  /// In ur, this message translates to:
  /// **'Vyapar ki parties'**
  String get importSourceVyaparParties;

  /// No description provided for @importSourceKhatabook.
  ///
  /// In ur, this message translates to:
  /// **'Khatabook'**
  String get importSourceKhatabook;

  /// No description provided for @importSourceOther.
  ///
  /// In ur, this message translates to:
  /// **'Koi aur'**
  String get importSourceOther;

  /// No description provided for @importRecognised.
  ///
  /// In ur, this message translates to:
  /// **'Pehchaan liya: {source}'**
  String importRecognised(String source);

  /// No description provided for @importGuideTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh file kaise nikalein'**
  String get importGuideTitle;

  /// No description provided for @importGuideOurs.
  ///
  /// In ur, this message translates to:
  /// **'Pehli line mein yeh naam likhein: {headings}. Phir har line par ek cheez, ya ek customer.'**
  String importGuideOurs(String headings);

  /// No description provided for @importGuideVyaparItems.
  ///
  /// In ur, this message translates to:
  /// **'1. Jis computer ya phone par dukaan ka Vyapar hai, us par Vyapar kholein.\n2. Menu se Utilities, phir Export Items kholein aur Excel mein save karein.\n3. File is phone par bhejein (apne aap ko WhatsApp karein, ya cable se) aur neeche chunein.\nVyapar ki Import Items wali bhari hui sheet bhi isi tarah aa jati hai.'**
  String get importGuideVyaparItems;

  /// No description provided for @importGuideVyaparParties.
  ///
  /// In ur, this message translates to:
  /// **'1. Vyapar mein Reports, phir Party Reports, phir All Parties kholein.\n2. Oopar Excel ka button dabayein aur file save karein.\n3. File is phone par bhejein aur neeche chunein.\nHar baqaya apni taraf aata hai: To Receive woh hai jo customer ne aap ko dena hai.'**
  String get importGuideVyaparParties;

  /// No description provided for @importGuideKhatabook.
  ///
  /// In ur, this message translates to:
  /// **'1. Khatabook ki phone app report PDF mein deti hai, aur PDF parhi nahin ja sakti. Agar aap ka Khatabook, computer ya web par, customers ki list Excel ya CSV mein deta hai to woh download karein.\n2. Agar sirf PDF milti hai to ek sheet banayein jis mein Name, Phone, You will get, You will give likha ho, aur baqaya us mein likh dein.\n3. File is phone par bhejein aur neeche chunein.'**
  String get importGuideKhatabook;

  /// No description provided for @importGuideOther.
  ///
  /// In ur, this message translates to:
  /// **'Koi bhi .xlsx, .xls ya .csv jis ki pehli line mein columns ke naam hon. Jo naam app na pehchane, use Columns mein khud chun lein.'**
  String get importGuideOther;

  /// No description provided for @importReading.
  ///
  /// In ur, this message translates to:
  /// **'File parhi ja rahi hai…'**
  String get importReading;

  /// No description provided for @importChecking.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan mein pehle se maujood cheezon se mila rahe hain…'**
  String get importChecking;

  /// No description provided for @importColumnsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Columns'**
  String get importColumnsTitle;

  /// No description provided for @importColumnsHint.
  ///
  /// In ur, this message translates to:
  /// **'Agar koi column ghalat parha gaya ho to sahi chunein.'**
  String get importColumnsHint;

  /// No description provided for @importColumnNone.
  ///
  /// In ur, this message translates to:
  /// **'Is file mein nahin'**
  String get importColumnNone;

  /// No description provided for @importColumnLetter.
  ///
  /// In ur, this message translates to:
  /// **'Column {letter}'**
  String importColumnLetter(String letter);

  /// No description provided for @importFieldName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get importFieldName;

  /// No description provided for @importFieldSalePrice.
  ///
  /// In ur, this message translates to:
  /// **'Bechne ki qeemat'**
  String get importFieldSalePrice;

  /// No description provided for @importFieldPurchasePrice.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ki qeemat'**
  String get importFieldPurchasePrice;

  /// No description provided for @importFieldWholesalePrice.
  ///
  /// In ur, this message translates to:
  /// **'Thok ki qeemat'**
  String get importFieldWholesalePrice;

  /// No description provided for @importFieldMrp.
  ///
  /// In ur, this message translates to:
  /// **'MRP'**
  String get importFieldMrp;

  /// No description provided for @importFieldStock.
  ///
  /// In ur, this message translates to:
  /// **'Maujooda stock'**
  String get importFieldStock;

  /// No description provided for @importFieldMinStock.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam stock'**
  String get importFieldMinStock;

  /// No description provided for @importFieldUnit.
  ///
  /// In ur, this message translates to:
  /// **'Unit'**
  String get importFieldUnit;

  /// No description provided for @importFieldSecondaryUnit.
  ///
  /// In ur, this message translates to:
  /// **'Doosra unit'**
  String get importFieldSecondaryUnit;

  /// No description provided for @importFieldConversion.
  ///
  /// In ur, this message translates to:
  /// **'Ek mein doosre unit kitne'**
  String get importFieldConversion;

  /// No description provided for @importFieldCode.
  ///
  /// In ur, this message translates to:
  /// **'Code'**
  String get importFieldCode;

  /// No description provided for @importFieldBarcode.
  ///
  /// In ur, this message translates to:
  /// **'Barcode'**
  String get importFieldBarcode;

  /// No description provided for @importFieldCategory.
  ///
  /// In ur, this message translates to:
  /// **'Qism'**
  String get importFieldCategory;

  /// No description provided for @importFieldDescription.
  ///
  /// In ur, this message translates to:
  /// **'Tafseel'**
  String get importFieldDescription;

  /// No description provided for @importFieldHsCode.
  ///
  /// In ur, this message translates to:
  /// **'HS / PCT code'**
  String get importFieldHsCode;

  /// No description provided for @importFieldItemType.
  ///
  /// In ur, this message translates to:
  /// **'Maal ya service'**
  String get importFieldItemType;

  /// No description provided for @importFieldHsn.
  ///
  /// In ur, this message translates to:
  /// **'HSN (India ka, nahin rakha jata)'**
  String get importFieldHsn;

  /// No description provided for @importFieldTax.
  ///
  /// In ur, this message translates to:
  /// **'Tax rate (nahin parha jata)'**
  String get importFieldTax;

  /// No description provided for @importFieldPhone.
  ///
  /// In ur, this message translates to:
  /// **'Phone'**
  String get importFieldPhone;

  /// No description provided for @importFieldBalance.
  ///
  /// In ur, this message translates to:
  /// **'Baqaya'**
  String get importFieldBalance;

  /// No description provided for @importFieldReceivable.
  ///
  /// In ur, this message translates to:
  /// **'Unhon ne aap ko dena hai'**
  String get importFieldReceivable;

  /// No description provided for @importFieldPayable.
  ///
  /// In ur, this message translates to:
  /// **'Aap ne unhein dena hai'**
  String get importFieldPayable;

  /// No description provided for @importFieldBalanceType.
  ///
  /// In ur, this message translates to:
  /// **'Lena ya dena'**
  String get importFieldBalanceType;

  /// No description provided for @importFieldType.
  ///
  /// In ur, this message translates to:
  /// **'Customer ya supplier'**
  String get importFieldType;

  /// No description provided for @importFieldCity.
  ///
  /// In ur, this message translates to:
  /// **'Shehar'**
  String get importFieldCity;

  /// No description provided for @importFieldAddress.
  ///
  /// In ur, this message translates to:
  /// **'Pata'**
  String get importFieldAddress;

  /// No description provided for @importFieldCreditLimit.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd'**
  String get importFieldCreditLimit;

  /// No description provided for @importFieldGstin.
  ///
  /// In ur, this message translates to:
  /// **'GSTIN (India ka, nahin rakha jata)'**
  String get importFieldGstin;

  /// No description provided for @importNoteGst.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezon par India ka GST rate tha ({rates}). GST Pakistan ka sales tax nahin, is liye koi rate nahin liya gaya: har cheez par dukaan ka aam tax lagega, jaise haath se daali cheez par.'**
  String importNoteGst(String count, String rates);

  /// No description provided for @importNoteTax.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezon par tax rate tha. Woh nahin parha gaya: har cheez par dukaan ka aam tax lagega, jaise haath se daali cheez par.'**
  String importNoteTax(String count);

  /// No description provided for @importNoteHsn.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezon ka HSN code tha. Woh India ka hai; Pakistan ka PCT code hota hai, is liye nahin rakha gaya. FBR ko report hone wali cheezon mein PCT code daalein.'**
  String importNoteHsn(String count);

  /// No description provided for @importNoteGstin.
  ///
  /// In ur, this message translates to:
  /// **'{count} parties ka GSTIN tha. Woh India ka tax number hai, NTN nahin, is liye nahin rakha gaya.'**
  String importNoteGstin(String count);

  /// No description provided for @importNoteRupee.
  ///
  /// In ur, this message translates to:
  /// **'Raqam par ₹ ka nishaan tha, jaise Vyapar likhta hai. Inhein aap ke rupay hi samjha gaya hai.'**
  String get importNoteRupee;

  /// No description provided for @importNoteColumns.
  ///
  /// In ur, this message translates to:
  /// **'Nahin rakhe gaye: {columns}'**
  String importNoteColumns(String columns);

  /// No description provided for @importNoteServices.
  ///
  /// In ur, this message translates to:
  /// **'{count} services ka stock nahin gina jata.'**
  String importNoteServices(String count);

  /// No description provided for @importUnknownUnit.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezein \"{unit}\" mein hain, jo is dukaan ka unit nahin: yeh adad mein rakhi jayengi, qeemat aur stock file jaise.'**
  String importUnknownUnit(String count, String unit);

  /// No description provided for @importSecondUnit.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezon ka doosra unit hai ({unit}): yeh sirf pehle unit mein rakhi jayengi.'**
  String importSecondUnit(String count, String unit);

  /// No description provided for @importBalancesOwed.
  ///
  /// In ur, this message translates to:
  /// **'{count} ne aap ko {amount} dene hain'**
  String importBalancesOwed(String count, String amount);

  /// No description provided for @importBalancesAhead.
  ///
  /// In ur, this message translates to:
  /// **'{count} ne pehle se diye: aap ke paas un ke {amount} hain'**
  String importBalancesAhead(String count, String amount);

  /// No description provided for @importBalancesSuppliers.
  ///
  /// In ur, this message translates to:
  /// **'{count} suppliers jin ko aap ne {amount} dene hain: yeh baqaya nahin laaya gaya. Har ek ka purchase bill darj karein.'**
  String importBalancesSuppliers(String count, String amount);

  /// No description provided for @importOwedQuestion.
  ///
  /// In ur, this message translates to:
  /// **'{count} jin ko aap ne dena hai, aur file nahin batati ke woh kaun hain. Woh hain:'**
  String importOwedQuestion(String count);

  /// No description provided for @importOwedSuppliers.
  ///
  /// In ur, this message translates to:
  /// **'Suppliers'**
  String get importOwedSuppliers;

  /// No description provided for @importOwedCustomers.
  ///
  /// In ur, this message translates to:
  /// **'Pehle se paise de chuke customers'**
  String get importOwedCustomers;

  /// No description provided for @importDuplicates.
  ///
  /// In ur, this message translates to:
  /// **'{count} pehle se dukaan mein hain'**
  String importDuplicates(String count);

  /// No description provided for @importDuplicatesSkip.
  ///
  /// In ur, this message translates to:
  /// **'Jaise hain rehne dein'**
  String get importDuplicatesSkip;

  /// No description provided for @importDuplicatesUpdate.
  ///
  /// In ur, this message translates to:
  /// **'File se naya karein'**
  String get importDuplicatesUpdate;

  /// No description provided for @importDuplicatesItemsHint.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat file se aayegi; code ya barcode sirf wahan jahan pehle nahin. Shelf ka stock nahin badlega.'**
  String get importDuplicatesItemsHint;

  /// No description provided for @importDuplicatesPartiesHint.
  ///
  /// In ur, this message translates to:
  /// **'Phone, pata aur udhaar ki hadd sirf khaali jagah bhari jayegi. Baqaya nahin badlega.'**
  String get importDuplicatesPartiesHint;

  /// No description provided for @importPartial.
  ///
  /// In ur, this message translates to:
  /// **'{count} kuch chhor kar aayenge'**
  String importPartial(String count);

  /// No description provided for @importMore.
  ///
  /// In ur, this message translates to:
  /// **'aur {count}'**
  String importMore(String count);

  /// No description provided for @importLine.
  ///
  /// In ur, this message translates to:
  /// **'Line {line}: {reason}'**
  String importLine(String line, String reason);

  /// No description provided for @importIssueNoName.
  ///
  /// In ur, this message translates to:
  /// **'naam nahin'**
  String get importIssueNoName;

  /// No description provided for @importIssueTwice.
  ///
  /// In ur, this message translates to:
  /// **'{name} file mein do dafa hai'**
  String importIssueTwice(String name);

  /// No description provided for @importIssueTotal.
  ///
  /// In ur, this message translates to:
  /// **'yeh total ki line hai, koi cheez ya party nahin'**
  String get importIssueTotal;

  /// No description provided for @importIssueNoPrice.
  ///
  /// In ur, this message translates to:
  /// **'{name} ki bechne ki qeemat nahin'**
  String importIssueNoPrice(String name);

  /// No description provided for @importIssueNotPrice.
  ///
  /// In ur, this message translates to:
  /// **'{name}: \"{value}\" qeemat nahin'**
  String importIssueNotPrice(String name, String value);

  /// No description provided for @importIssueNotQty.
  ///
  /// In ur, this message translates to:
  /// **'{name}: \"{value}\" stock ki tadaad nahin'**
  String importIssueNotQty(String name, String value);

  /// No description provided for @importIssueNotAmount.
  ///
  /// In ur, this message translates to:
  /// **'{name}: \"{value}\" raqam nahin'**
  String importIssueNotAmount(String name, String value);

  /// No description provided for @importIssueNegativeStock.
  ///
  /// In ur, this message translates to:
  /// **'{name} baghair stock ke aayega; file mein {value} likha hai'**
  String importIssueNegativeStock(String name, String value);

  /// No description provided for @importIssueBarcode.
  ///
  /// In ur, this message translates to:
  /// **'{name} baghair barcode ke aayega; Excel ne use {value} bana diya'**
  String importIssueBarcode(String name, String value);

  /// No description provided for @importIssueSupplierOwed.
  ///
  /// In ur, this message translates to:
  /// **'{name} supplier ban kar aayega, aap ke dene wale Rs {value} ke baghair: yeh purchase bill mein darj karein'**
  String importIssueSupplierOwed(String name, String value);

  /// No description provided for @importIssueSupplierOwes.
  ///
  /// In ur, this message translates to:
  /// **'{name} supplier ban kar aayega, un ke dene wale Rs {value} ke baghair'**
  String importIssueSupplierOwes(String name, String value);

  /// No description provided for @importIssueAlreadyItem.
  ///
  /// In ur, this message translates to:
  /// **'{name} pehle se maal mein hai'**
  String importIssueAlreadyItem(String name);

  /// No description provided for @importIssueAlreadyItemAs.
  ///
  /// In ur, this message translates to:
  /// **'{name} pehle se maal mein hai, {value} ke naam se'**
  String importIssueAlreadyItemAs(String name, String value);

  /// No description provided for @importIssueAlreadyParty.
  ///
  /// In ur, this message translates to:
  /// **'{name} pehle se khate mein hai'**
  String importIssueAlreadyParty(String name);

  /// No description provided for @importIssueAlreadyPartyAs.
  ///
  /// In ur, this message translates to:
  /// **'{name} pehle se khate mein hai, {value} ke naam se'**
  String importIssueAlreadyPartyAs(String name, String value);

  /// No description provided for @importIssueOther.
  ///
  /// In ur, this message translates to:
  /// **'{name}: {value}'**
  String importIssueOther(String name, String value);

  /// No description provided for @importProgress.
  ///
  /// In ur, this message translates to:
  /// **'{total} mein se {done} aa rahe hain…'**
  String importProgress(String total, String done);

  /// No description provided for @importUpdated.
  ///
  /// In ur, this message translates to:
  /// **'{count} naye kiye gaye'**
  String importUpdated(String count);

  /// No description provided for @importRefusedUnreadable.
  ///
  /// In ur, this message translates to:
  /// **'Yeh file sheet ki tarah parhi nahin ja saki. Ise Excel ya Google Sheets mein khol kar .xlsx ya .csv mein save karein, phir woh chunein.'**
  String get importRefusedUnreadable;

  /// No description provided for @importRefusedOld.
  ///
  /// In ur, this message translates to:
  /// **'Yeh .xls Excel 95 ya us se purani hai. Ise .xlsx mein dobara save kar ke chunein.'**
  String get importRefusedOld;

  /// No description provided for @importRefusedPassword.
  ///
  /// In ur, this message translates to:
  /// **'Is workbook par password hai. Excel mein password hata kar save karein aur dobara chunein.'**
  String get importRefusedPassword;

  /// No description provided for @importNeedItemColumns.
  ///
  /// In ur, this message translates to:
  /// **'Naam aur bechne ki qeemat ke columns nahin mile. Neeche Columns mein chunein.'**
  String get importNeedItemColumns;

  /// No description provided for @importNeedPartyColumns.
  ///
  /// In ur, this message translates to:
  /// **'Naam ka column nahin mila. Neeche Columns mein chunein.'**
  String get importNeedPartyColumns;

  /// No description provided for @reportStockSummary.
  ///
  /// In ur, this message translates to:
  /// **'Stock ka khulasa'**
  String get reportStockSummary;

  /// No description provided for @reportStockSummaryHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez ka stock, qeemat aur maaliyat, kisi bhi din ki'**
  String get reportStockSummaryHint;

  /// No description provided for @reportItemByParty.
  ///
  /// In ur, this message translates to:
  /// **'Cheez ki party-war report'**
  String get reportItemByParty;

  /// No description provided for @reportItemByPartyHint.
  ///
  /// In ur, this message translates to:
  /// **'Yeh cheez kis ne khareedi aur kis ne di'**
  String get reportItemByPartyHint;

  /// No description provided for @reportItemProfit.
  ///
  /// In ur, this message translates to:
  /// **'Cheez-war nafa nuqsan'**
  String get reportItemProfit;

  /// No description provided for @reportItemProfitHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez ne laagat se kitna kamaya'**
  String get reportItemProfitHint;

  /// No description provided for @reportCategoryProfit.
  ///
  /// In ur, this message translates to:
  /// **'Category-war nafa nuqsan'**
  String get reportCategoryProfit;

  /// No description provided for @reportCategoryProfitHint.
  ///
  /// In ur, this message translates to:
  /// **'Har category ka nafa'**
  String get reportCategoryProfitHint;

  /// No description provided for @reportLowStock.
  ///
  /// In ur, this message translates to:
  /// **'Kam stock'**
  String get reportLowStock;

  /// No description provided for @reportLowStockHint.
  ///
  /// In ur, this message translates to:
  /// **'Kya khatam ho raha hai aur kitna mangwana hai'**
  String get reportLowStockHint;

  /// No description provided for @reportItemDetail.
  ///
  /// In ur, this message translates to:
  /// **'Cheez ki tafseel'**
  String get reportItemDetail;

  /// No description provided for @reportItemDetailHint.
  ///
  /// In ur, this message translates to:
  /// **'Ek cheez ka stock, din ba din'**
  String get reportItemDetailHint;

  /// No description provided for @reportStockDetail.
  ///
  /// In ur, this message translates to:
  /// **'Stock ki tafseel'**
  String get reportStockDetail;

  /// No description provided for @reportStockDetailHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez ka shuru ka stock, aamad, kharch aur akhir'**
  String get reportStockDetailHint;

  /// No description provided for @reportSalePurchaseByCategory.
  ///
  /// In ur, this message translates to:
  /// **'Category-war bikri aur khareed'**
  String get reportSalePurchaseByCategory;

  /// No description provided for @reportSalePurchaseByCategoryHint.
  ///
  /// In ur, this message translates to:
  /// **'Har category kitni biki aur kitni aayi'**
  String get reportSalePurchaseByCategoryHint;

  /// No description provided for @reportStockByCategory.
  ///
  /// In ur, this message translates to:
  /// **'Category-war stock'**
  String get reportStockByCategory;

  /// No description provided for @reportStockByCategoryHint.
  ///
  /// In ur, this message translates to:
  /// **'Har category ka stock aur maaliyat'**
  String get reportStockByCategoryHint;

  /// No description provided for @reportBatches.
  ///
  /// In ur, this message translates to:
  /// **'Batch report'**
  String get reportBatches;

  /// No description provided for @reportBatchesHint.
  ///
  /// In ur, this message translates to:
  /// **'Shelf par har batch, expiry ke saath'**
  String get reportBatchesHint;

  /// No description provided for @reportSerials.
  ///
  /// In ur, this message translates to:
  /// **'Serial aur IMEI report'**
  String get reportSerials;

  /// No description provided for @reportSerialsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har numbered cheez: mojood, biki ya wapas gayi'**
  String get reportSerialsHint;

  /// No description provided for @reportItemDiscount.
  ///
  /// In ur, this message translates to:
  /// **'Cheez-war discount'**
  String get reportItemDiscount;

  /// No description provided for @reportItemDiscountHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez ki qeemat se kitna kam kiya'**
  String get reportItemDiscountHint;

  /// No description provided for @reportStockTransfers.
  ///
  /// In ur, this message translates to:
  /// **'Maal ki muntaqili'**
  String get reportStockTransfers;

  /// No description provided for @reportStockTransfersHint.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan, godown aur van ke darmiyan maal'**
  String get reportStockTransfersHint;

  /// No description provided for @reportProduction.
  ///
  /// In ur, this message translates to:
  /// **'Production register'**
  String get reportProduction;

  /// No description provided for @reportProductionHint.
  ///
  /// In ur, this message translates to:
  /// **'Har production: kya laga aur kitne ka'**
  String get reportProductionHint;

  /// No description provided for @reportFastSlow.
  ///
  /// In ur, this message translates to:
  /// **'Tez, sust aur band maal'**
  String get reportFastSlow;

  /// No description provided for @reportFastSlowHint.
  ///
  /// In ur, this message translates to:
  /// **'Kya bikta hai, kya nahi, aur kitna paisa phansa hai'**
  String get reportFastSlowHint;

  /// No description provided for @reportStockAgeing.
  ///
  /// In ur, this message translates to:
  /// **'Maal kitna purana'**
  String get reportStockAgeing;

  /// No description provided for @reportStockAgeingHint.
  ///
  /// In ur, this message translates to:
  /// **'Maal kab se shelf par para hai'**
  String get reportStockAgeingHint;

  /// No description provided for @reportFilterPlace.
  ///
  /// In ur, this message translates to:
  /// **'Jagah'**
  String get reportFilterPlace;

  /// No description provided for @reportFilterInStock.
  ///
  /// In ur, this message translates to:
  /// **'Sirf mojood maal'**
  String get reportFilterInStock;

  /// No description provided for @reportFilterAsOf.
  ///
  /// In ur, this message translates to:
  /// **'Is din tak'**
  String get reportFilterAsOf;

  /// No description provided for @reportFilterSalesDays.
  ///
  /// In ur, this message translates to:
  /// **'Bikri kitne din ki'**
  String get reportFilterSalesDays;

  /// No description provided for @reportFilterCoverDays.
  ///
  /// In ur, this message translates to:
  /// **'Kitne din ka maal'**
  String get reportFilterCoverDays;

  /// No description provided for @reportFilterFastAt.
  ///
  /// In ur, this message translates to:
  /// **'Tez kitne bills se'**
  String get reportFilterFastAt;

  /// No description provided for @reportFilterSlowBelow.
  ///
  /// In ur, this message translates to:
  /// **'Sust kitne bills se kam'**
  String get reportFilterSlowBelow;

  /// No description provided for @reportFilterSerial.
  ///
  /// In ur, this message translates to:
  /// **'Serial ya IMEI'**
  String get reportFilterSerial;

  /// No description provided for @reportFilterSerialHint.
  ///
  /// In ur, this message translates to:
  /// **'Number, ya uske aakhri chand hindse'**
  String get reportFilterSerialHint;

  /// No description provided for @reportFilterDaysValue.
  ///
  /// In ur, this message translates to:
  /// **'{days} din'**
  String reportFilterDaysValue(int days);

  /// No description provided for @reportFilterBillsValue.
  ///
  /// In ur, this message translates to:
  /// **'{bills} bill'**
  String reportFilterBillsValue(int bills);

  /// No description provided for @copyTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsi copy?'**
  String get copyTitle;

  /// No description provided for @copyOriginal.
  ///
  /// In ur, this message translates to:
  /// **'Asal'**
  String get copyOriginal;

  /// No description provided for @copyDuplicate.
  ///
  /// In ur, this message translates to:
  /// **'Duplicate'**
  String get copyDuplicate;

  /// No description provided for @copyTriplicate.
  ///
  /// In ur, this message translates to:
  /// **'Triplicate'**
  String get copyTriplicate;

  /// No description provided for @copyTransporter.
  ///
  /// In ur, this message translates to:
  /// **'Transporter'**
  String get copyTransporter;

  /// No description provided for @copyAutoHint.
  ///
  /// In ur, this message translates to:
  /// **'Na chunein to: pehli dafa asal, us ke baad duplicate'**
  String get copyAutoHint;

  /// No description provided for @copyChosenHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaghaz par yahi copy likhi chhapegi'**
  String get copyChosenHint;

  /// No description provided for @copyTransporterHint.
  ///
  /// In ur, this message translates to:
  /// **'Maal, miqdar aur kis ke liye — koi qeemat nahi'**
  String get copyTransporterHint;

  /// No description provided for @copyOriginalGone.
  ///
  /// In ur, this message translates to:
  /// **'Asal copy pehle chhap chuki hai'**
  String get copyOriginalGone;

  /// No description provided for @transportTitle.
  ///
  /// In ur, this message translates to:
  /// **'Transport ki tafseel'**
  String get transportTitle;

  /// No description provided for @transportHint.
  ///
  /// In ur, this message translates to:
  /// **'Bilty aur gaari ka number bill par chhapega. Paison mein kuch nahi badlega.'**
  String get transportHint;

  /// No description provided for @transportAdd.
  ///
  /// In ur, this message translates to:
  /// **'Transport ki tafseel likhein (bilty, gaari)'**
  String get transportAdd;

  /// No description provided for @transportTransporter.
  ///
  /// In ur, this message translates to:
  /// **'Transporter / adda'**
  String get transportTransporter;

  /// No description provided for @transportVehicle.
  ///
  /// In ur, this message translates to:
  /// **'Gaari no'**
  String get transportVehicle;

  /// No description provided for @transportBilty.
  ///
  /// In ur, this message translates to:
  /// **'Bilty no'**
  String get transportBilty;

  /// No description provided for @transportShipTo.
  ///
  /// In ur, this message translates to:
  /// **'Kahan bhejna hai'**
  String get transportShipTo;

  /// No description provided for @settingsBillDesign.
  ///
  /// In ur, this message translates to:
  /// **'Bill ka design'**
  String get settingsBillDesign;

  /// No description provided for @billDesignIntro.
  ///
  /// In ur, this message translates to:
  /// **'PDF bill ka andaaz: design, rang, logo aur payment QR. Thermal slip printer ke apne font mein chhapti hai; us ka andaaz (aam, compact ya bara total), baqaya, neeche ki likhai aur QR ka faisla yahan hota hai.'**
  String get billDesignIntro;

  /// No description provided for @billDesignLayout.
  ///
  /// In ur, this message translates to:
  /// **'Design'**
  String get billDesignLayout;

  /// No description provided for @billThemeClassic.
  ///
  /// In ur, this message translates to:
  /// **'Saada'**
  String get billThemeClassic;

  /// No description provided for @billThemeClassicHint.
  ///
  /// In ur, this message translates to:
  /// **'Beech mein dukan ka naam, saada kaghaz jaisa'**
  String get billThemeClassicHint;

  /// No description provided for @billThemeModern.
  ///
  /// In ur, this message translates to:
  /// **'Rangeen patti'**
  String get billThemeModern;

  /// No description provided for @billThemeModernHint.
  ///
  /// In ur, this message translates to:
  /// **'Upar dukan ke rang ki patti par naam aur logo'**
  String get billThemeModernHint;

  /// No description provided for @billThemeCompact.
  ///
  /// In ur, this message translates to:
  /// **'Chhota'**
  String get billThemeCompact;

  /// No description provided for @billThemeCompactHint.
  ///
  /// In ur, this message translates to:
  /// **'Chhoti likhai, lamba wholesale bill ek safhe par'**
  String get billThemeCompactHint;

  /// No description provided for @billThemeTax.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax invoice'**
  String get billThemeTax;

  /// No description provided for @billThemeTaxHint.
  ///
  /// In ur, this message translates to:
  /// **'FBR ke mutabiq: dono taraf ka NTN/STRN, har line par tax se pehle, tax ki sharah, tax aur tax samet qeemat'**
  String get billThemeTaxHint;

  /// No description provided for @billDesignTaxNeedsNtn.
  ///
  /// In ur, this message translates to:
  /// **'Tax invoice ke liye Dukan ki tafseel mein apna NTN aur STRN likhein'**
  String get billDesignTaxNeedsNtn;

  /// No description provided for @billDesignColour.
  ///
  /// In ur, this message translates to:
  /// **'Rang'**
  String get billDesignColour;

  /// No description provided for @billAccentInk.
  ///
  /// In ur, this message translates to:
  /// **'Siyah'**
  String get billAccentInk;

  /// No description provided for @billAccentBlue.
  ///
  /// In ur, this message translates to:
  /// **'Neela'**
  String get billAccentBlue;

  /// No description provided for @billAccentGreen.
  ///
  /// In ur, this message translates to:
  /// **'Hara'**
  String get billAccentGreen;

  /// No description provided for @billAccentMaroon.
  ///
  /// In ur, this message translates to:
  /// **'Maroon'**
  String get billAccentMaroon;

  /// No description provided for @billAccentOrange.
  ///
  /// In ur, this message translates to:
  /// **'Narangi'**
  String get billAccentOrange;

  /// No description provided for @billAccentPurple.
  ///
  /// In ur, this message translates to:
  /// **'Jamni'**
  String get billAccentPurple;

  /// No description provided for @billDesignPage.
  ///
  /// In ur, this message translates to:
  /// **'Kaghaz ka size'**
  String get billDesignPage;

  /// No description provided for @billDesignPictures.
  ///
  /// In ur, this message translates to:
  /// **'Logo aur QR'**
  String get billDesignPictures;

  /// No description provided for @billDesignLogo.
  ///
  /// In ur, this message translates to:
  /// **'Dukan ka logo'**
  String get billDesignLogo;

  /// No description provided for @billDesignLogoHint.
  ///
  /// In ur, this message translates to:
  /// **'PDF bill ke upar chhapta hai'**
  String get billDesignLogoHint;

  /// No description provided for @billDesignPaymentQr.
  ///
  /// In ur, this message translates to:
  /// **'Payment QR'**
  String get billDesignPaymentQr;

  /// No description provided for @billDesignPaymentQrHint.
  ///
  /// In ur, this message translates to:
  /// **'Aap ke bank, JazzCash ya Easypaisa ka apna QR — screenshot ya tasveer. PDF bill ke neeche chhapta hai.'**
  String get billDesignPaymentQrHint;

  /// No description provided for @billDesignQrOnThermal.
  ///
  /// In ur, this message translates to:
  /// **'QR thermal slip par bhi'**
  String get billDesignQrOnThermal;

  /// No description provided for @billDesignQrOnThermalHint.
  ///
  /// In ur, this message translates to:
  /// **'Pehle ek slip chhap kar phone se scan kar ke dekh lein'**
  String get billDesignQrOnThermalHint;

  /// No description provided for @billDesignKhata.
  ///
  /// In ur, this message translates to:
  /// **'Pichhla baqaya bill par'**
  String get billDesignKhata;

  /// No description provided for @billDesignKhataHint.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar wale gahak ke bill par: pichhla baqaya, is bill, kul baqaya. Purane bill ki copy par wahi hisaab chhapta hai jo bill ke din tha.'**
  String get billDesignKhataHint;

  /// No description provided for @billDesignFooter.
  ///
  /// In ur, this message translates to:
  /// **'Bill ke neeche ki likhai'**
  String get billDesignFooter;

  /// No description provided for @billDesignFooterLabel.
  ///
  /// In ur, this message translates to:
  /// **'Har line alag (zyada se zyada 4)'**
  String get billDesignFooterLabel;

  /// No description provided for @billDesignFooterHint.
  ///
  /// In ur, this message translates to:
  /// **'Shukriya, wapsi ki shart, kuch bhi — Urdu, Roman ya English'**
  String get billDesignFooterHint;

  /// No description provided for @billDesignFooterPresets.
  ///
  /// In ur, this message translates to:
  /// **'Ek tap mein daalein'**
  String get billDesignFooterPresets;

  /// No description provided for @billDesignPreview.
  ///
  /// In ur, this message translates to:
  /// **'Kaisa dikhega'**
  String get billDesignPreview;

  /// No description provided for @billDesignPreviewPdf.
  ///
  /// In ur, this message translates to:
  /// **'PDF'**
  String get billDesignPreviewPdf;

  /// No description provided for @billDesignPreviewSlip.
  ///
  /// In ur, this message translates to:
  /// **'Thermal slip'**
  String get billDesignPreviewSlip;

  /// No description provided for @billDesignPreviewNote.
  ///
  /// In ur, this message translates to:
  /// **'Yeh andaaz ka khaka hai. Asal PDF dekhne ke liye neeche wala button dabayein.'**
  String get billDesignPreviewNote;

  /// No description provided for @billDesignSamplePdf.
  ///
  /// In ur, this message translates to:
  /// **'Namoona PDF dekhein'**
  String get billDesignSamplePdf;

  /// No description provided for @billDesignSaved.
  ///
  /// In ur, this message translates to:
  /// **'Bill ka design mehfooz ho gaya'**
  String get billDesignSaved;

  /// No description provided for @settingsTextSize.
  ///
  /// In ur, this message translates to:
  /// **'Likhai ka size'**
  String get settingsTextSize;

  /// No description provided for @settingsTextSizeNormal.
  ///
  /// In ur, this message translates to:
  /// **'Aam'**
  String get settingsTextSizeNormal;

  /// No description provided for @settingsTextSizeLarge.
  ///
  /// In ur, this message translates to:
  /// **'Bara'**
  String get settingsTextSizeLarge;

  /// No description provided for @settingsTextSizeLarger.
  ///
  /// In ur, this message translates to:
  /// **'Aur bara'**
  String get settingsTextSizeLarger;

  /// No description provided for @settingsTextSizeHint.
  ///
  /// In ur, this message translates to:
  /// **'Sirf is phone ki screen par. Bill, raseed aur PDF har size par aik jaise chhapte hain.'**
  String get settingsTextSizeHint;

  /// No description provided for @itemStockLeft.
  ///
  /// In ur, this message translates to:
  /// **'{amount} mojood'**
  String itemStockLeft(String amount);

  /// No description provided for @expenseWhose.
  ///
  /// In ur, this message translates to:
  /// **'Kis ka kharcha'**
  String get expenseWhose;

  /// No description provided for @expenseForShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ka kharcha'**
  String get expenseForShop;

  /// No description provided for @expenseForHome.
  ///
  /// In ur, this message translates to:
  /// **'Ghar ka kharcha'**
  String get expenseForHome;

  /// No description provided for @expenseHomeChip.
  ///
  /// In ur, this message translates to:
  /// **'Ghar'**
  String get expenseHomeChip;

  /// No description provided for @expenseHomeExplain.
  ///
  /// In ur, this message translates to:
  /// **'Ghar ka kharcha malik ka apna paisa hai jo dukaan se nikla. Yeh dukaan ka kharcha nahi, is liye munafa kam nahi karta; malik ka hissa kam karta hai.'**
  String get expenseHomeExplain;

  /// No description provided for @expenseHomeGoodsLink.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ka maal ghar le gaye?'**
  String get expenseHomeGoodsLink;

  /// No description provided for @expenseRemind.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine yaad dilayen'**
  String get expenseRemind;

  /// No description provided for @expenseRemindDay.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ki tareekh'**
  String get expenseRemindDay;

  /// No description provided for @expenseRemindDayInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ki tareekh 1 se 31 tak likhein'**
  String get expenseRemindDayInvalid;

  /// No description provided for @expenseMonthShop.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine dukaan'**
  String get expenseMonthShop;

  /// No description provided for @expenseMonthHome.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine ghar'**
  String get expenseMonthHome;

  /// No description provided for @expenseGoodsCancelOnly.
  ///
  /// In ur, this message translates to:
  /// **'Ghar le gaye maal ko badla nahi jata: mansookh kar ke dobara likhein.'**
  String get expenseGoodsCancelOnly;

  /// No description provided for @expenseHomeNotAllowed.
  ///
  /// In ur, this message translates to:
  /// **'Ghar ka kharcha sirf malik ya accountant badal sakte hain.'**
  String get expenseHomeNotAllowed;

  /// No description provided for @billsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Mahana bill'**
  String get billsTitle;

  /// No description provided for @billsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi mahana bill nahi'**
  String get billsEmpty;

  /// No description provided for @billsEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Kiraya, bijli, tankhwah: aik dafa likhein, app us tareekh ko yaad dilayegi. Khud se kuch nahi diya jata.'**
  String get billsEmptyHint;

  /// No description provided for @billsNew.
  ///
  /// In ur, this message translates to:
  /// **'Naya mahana bill'**
  String get billsNew;

  /// No description provided for @billDue.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine dena hai: {name}'**
  String billDue(String name);

  /// No description provided for @billDueOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} ko dena tha'**
  String billDueOn(String date);

  /// No description provided for @billPayNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi dein'**
  String get billPayNow;

  /// No description provided for @billSkip.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine nahi'**
  String get billSkip;

  /// No description provided for @billSkipped.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine dobara yaad nahi dilaya jayega'**
  String get billSkipped;

  /// No description provided for @billEvery.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine {day} tareekh ko'**
  String billEvery(String day);

  /// No description provided for @billName.
  ///
  /// In ur, this message translates to:
  /// **'Kis cheez ka bill'**
  String get billName;

  /// No description provided for @billAmount.
  ///
  /// In ur, this message translates to:
  /// **'Aam taur par raqam'**
  String get billAmount;

  /// No description provided for @billSave.
  ///
  /// In ur, this message translates to:
  /// **'Bill save karein'**
  String get billSave;

  /// No description provided for @monthlyBillSaved.
  ///
  /// In ur, this message translates to:
  /// **'Mahana bill save ho gaya'**
  String get monthlyBillSaved;

  /// No description provided for @billDelete.
  ///
  /// In ur, this message translates to:
  /// **'Yaad dilana band karein'**
  String get billDelete;

  /// No description provided for @billDeleted.
  ///
  /// In ur, this message translates to:
  /// **'Yaad dilana band ho gaya'**
  String get billDeleted;

  /// No description provided for @billPaidFrom.
  ///
  /// In ur, this message translates to:
  /// **'Aam taur par kahan se'**
  String get billPaidFrom;

  /// No description provided for @headsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Mad'**
  String get headsTitle;

  /// No description provided for @headsExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharche ki mad'**
  String get headsExpense;

  /// No description provided for @headsIncome.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani ki mad'**
  String get headsIncome;

  /// No description provided for @headsAddExpense.
  ///
  /// In ur, this message translates to:
  /// **'Kharche ki nayi mad'**
  String get headsAddExpense;

  /// No description provided for @headsAddIncome.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani ki nayi mad'**
  String get headsAddIncome;

  /// No description provided for @headName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get headName;

  /// No description provided for @headDirect.
  ///
  /// In ur, this message translates to:
  /// **'Maal ki lagat (gross munafe se pehle)'**
  String get headDirect;

  /// No description provided for @headDirectChip.
  ///
  /// In ur, this message translates to:
  /// **'Direct'**
  String get headDirectChip;

  /// No description provided for @headIndirectChip.
  ///
  /// In ur, this message translates to:
  /// **'Indirect'**
  String get headIndirectChip;

  /// No description provided for @headHidden.
  ///
  /// In ur, this message translates to:
  /// **'Chhupi hui'**
  String get headHidden;

  /// No description provided for @headHide.
  ///
  /// In ur, this message translates to:
  /// **'List se chhupayein'**
  String get headHide;

  /// No description provided for @headSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get headSave;

  /// No description provided for @headSaved.
  ///
  /// In ur, this message translates to:
  /// **'Save ho gaya'**
  String get headSaved;

  /// No description provided for @headDirectExplain.
  ///
  /// In ur, this message translates to:
  /// **'Maal ki lagat (aate maal ka kiraya) bikri se gross munafe se pehle kat-ti hai; baqi (kiraya, tankhwah, bijli) us ke baad. Badalne se har mahine ke munafa nuqsan mein yeh mad jagah badalti hai.'**
  String get headDirectExplain;

  /// No description provided for @incomeTitle.
  ///
  /// In ur, this message translates to:
  /// **'Deegar aamdani'**
  String get incomeTitle;

  /// No description provided for @incomeEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi deegar aamdani nahi'**
  String get incomeEmpty;

  /// No description provided for @incomeEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Upar wale kamre ka kiraya, commission, bank ka munafa, raddi: jo paisa bikri ke ilawa aaya yahan likhein.'**
  String get incomeEmptyHint;

  /// No description provided for @incomeNew.
  ///
  /// In ur, this message translates to:
  /// **'Nayi aamdani'**
  String get incomeNew;

  /// No description provided for @incomeHead.
  ///
  /// In ur, this message translates to:
  /// **'Kis mad mein'**
  String get incomeHead;

  /// No description provided for @incomeFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kis se mila (marzi se)'**
  String get incomeFrom;

  /// No description provided for @incomeFromParty.
  ///
  /// In ur, this message translates to:
  /// **'Khate se chunein'**
  String get incomeFromParty;

  /// No description provided for @incomeInto.
  ///
  /// In ur, this message translates to:
  /// **'Kahan aaya'**
  String get incomeInto;

  /// No description provided for @incomeNote.
  ///
  /// In ur, this message translates to:
  /// **'Kis cheez ka (marzi se)'**
  String get incomeNote;

  /// No description provided for @incomeSave.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani save karein'**
  String get incomeSave;

  /// No description provided for @incomeSaved.
  ///
  /// In ur, this message translates to:
  /// **'Aamdani {docNo} save ho gayi'**
  String incomeSaved(String docNo);

  /// No description provided for @incomeThisMonth.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine'**
  String get incomeThisMonth;

  /// No description provided for @incomeNotASale.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bikri nahi: munafa nuqsan mein deegar aamdani mein, gross munafe ke baad aati hai.'**
  String get incomeNotASale;

  /// No description provided for @incomeHeadRent.
  ///
  /// In ur, this message translates to:
  /// **'Kiraya mila'**
  String get incomeHeadRent;

  /// No description provided for @incomeHeadCommission.
  ///
  /// In ur, this message translates to:
  /// **'Commission'**
  String get incomeHeadCommission;

  /// No description provided for @incomeHeadInterest.
  ///
  /// In ur, this message translates to:
  /// **'Bank ka munafa'**
  String get incomeHeadInterest;

  /// No description provided for @incomeHeadScrap.
  ///
  /// In ur, this message translates to:
  /// **'Raddi, khali dabbe'**
  String get incomeHeadScrap;

  /// No description provided for @incomeHeadRefund.
  ///
  /// In ur, this message translates to:
  /// **'Refund mila'**
  String get incomeHeadRefund;

  /// No description provided for @incomeHeadOther.
  ///
  /// In ur, this message translates to:
  /// **'Deegar'**
  String get incomeHeadOther;

  /// No description provided for @homeGoodsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Ghar le gaye maal'**
  String get homeGoodsTitle;

  /// No description provided for @homeGoodsExplain.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke shelf se ghar ke liye maal. Lagat par nikalta hai, aur malik ke hisse se kat-ta hai, munafe se nahi.'**
  String get homeGoodsExplain;

  /// No description provided for @homeGoodsSearch.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsa maal'**
  String get homeGoodsSearch;

  /// No description provided for @homeGoodsQty.
  ///
  /// In ur, this message translates to:
  /// **'Kitna'**
  String get homeGoodsQty;

  /// No description provided for @homeGoodsOnHand.
  ///
  /// In ur, this message translates to:
  /// **'Shelf par {qty}'**
  String homeGoodsOnHand(String qty);

  /// No description provided for @homeGoodsNote.
  ///
  /// In ur, this message translates to:
  /// **'Note (marzi se)'**
  String get homeGoodsNote;

  /// No description provided for @homeGoodsSave.
  ///
  /// In ur, this message translates to:
  /// **'Ghar le gaye, save karein'**
  String get homeGoodsSave;

  /// No description provided for @homeGoodsSaved.
  ///
  /// In ur, this message translates to:
  /// **'{docNo}: {amount} ka maal ghar gaya'**
  String homeGoodsSaved(String docNo, String amount);

  /// No description provided for @homeGoodsPick.
  ///
  /// In ur, this message translates to:
  /// **'Pehle maal chunein'**
  String get homeGoodsPick;

  /// No description provided for @homeGoodsQtyInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Kitna likhein, jaise 2 ya 1.5'**
  String get homeGoodsQtyInvalid;

  /// No description provided for @reportDailySummary.
  ///
  /// In ur, this message translates to:
  /// **'Din ka khulasa (Z report)'**
  String get reportDailySummary;

  /// No description provided for @reportDailySummaryHint.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki bikri, har tareeqe se aaya paisa, udhaar, kharchay aur galla'**
  String get reportDailySummaryHint;

  /// No description provided for @reportBankStatement.
  ///
  /// In ur, this message translates to:
  /// **'Bank statement'**
  String get reportBankStatement;

  /// No description provided for @reportBankStatementHint.
  ///
  /// In ur, this message translates to:
  /// **'Har jama aur nikasi, har ek ke baad baqi'**
  String get reportBankStatementHint;

  /// No description provided for @reportDiscount.
  ///
  /// In ur, this message translates to:
  /// **'Discount report'**
  String get reportDiscount;

  /// No description provided for @reportDiscountHint.
  ///
  /// In ur, this message translates to:
  /// **'Har party ko kitna discount diya, supplier se kitna mila'**
  String get reportDiscountHint;

  /// No description provided for @reportDiscountByCashier.
  ///
  /// In ur, this message translates to:
  /// **'Cashier-war discount'**
  String get reportDiscountByCashier;

  /// No description provided for @reportDiscountByCashierHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaunsa cashier kitna discount deta hai'**
  String get reportDiscountByCashierHint;

  /// No description provided for @reportSalesByCashier.
  ///
  /// In ur, this message translates to:
  /// **'Cashier-war bikri'**
  String get reportSalesByCashier;

  /// No description provided for @reportSalesByCashierHint.
  ///
  /// In ur, this message translates to:
  /// **'Har banday ke bill, bikri, discount, wapsi aur cancel'**
  String get reportSalesByCashierHint;

  /// No description provided for @reportSalesByCounter.
  ///
  /// In ur, this message translates to:
  /// **'Counter-war bikri'**
  String get reportSalesByCounter;

  /// No description provided for @reportSalesByCounterHint.
  ///
  /// In ur, this message translates to:
  /// **'Yehi, har phone ya counter ka'**
  String get reportSalesByCounterHint;

  /// No description provided for @reportPaymentModes.
  ///
  /// In ur, this message translates to:
  /// **'Adaigi ke tareeqay'**
  String get reportPaymentModes;

  /// No description provided for @reportPaymentModesHint.
  ///
  /// In ur, this message translates to:
  /// **'Naqad, bank, JazzCash, Easypaisa, cheque aur udhaar, har ek alag'**
  String get reportPaymentModesHint;

  /// No description provided for @reportHourlySales.
  ///
  /// In ur, this message translates to:
  /// **'Ghanta-war bikri'**
  String get reportHourlySales;

  /// No description provided for @reportHourlySalesHint.
  ///
  /// In ur, this message translates to:
  /// **'Din ke kis waqt sab se zyada rush hota hai'**
  String get reportHourlySalesHint;

  /// No description provided for @reportPaymentPerformance.
  ///
  /// In ur, this message translates to:
  /// **'Gahakon ki adaigi'**
  String get reportPaymentPerformance;

  /// No description provided for @reportPaymentPerformanceHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaun kitne din mein deta hai, kaun der se deta hai'**
  String get reportPaymentPerformanceHint;

  /// No description provided for @reportDefaulters.
  ///
  /// In ur, this message translates to:
  /// **'Defaulter list'**
  String get reportDefaulters;

  /// No description provided for @reportDefaultersHint.
  ///
  /// In ur, this message translates to:
  /// **'Jin ka udhaar apni muddat se guzar gaya'**
  String get reportDefaultersHint;

  /// No description provided for @reportChangedBills.
  ///
  /// In ur, this message translates to:
  /// **'Badle aur cancel bill'**
  String get reportChangedBills;

  /// No description provided for @reportChangedBillsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cancel, wapsi aur tabdeeli: kis ne, kab aur kyun'**
  String get reportChangedBillsHint;

  /// No description provided for @reportTaxReport.
  ///
  /// In ur, this message translates to:
  /// **'Tax report'**
  String get reportTaxReport;

  /// No description provided for @reportTaxReportHint.
  ///
  /// In ur, this message translates to:
  /// **'Bikri aur khareed par tax, party-war, NTN ke saath'**
  String get reportTaxReportHint;

  /// No description provided for @reportTaxRate.
  ///
  /// In ur, this message translates to:
  /// **'Tax rate report'**
  String get reportTaxRate;

  /// No description provided for @reportTaxRateHint.
  ///
  /// In ur, this message translates to:
  /// **'Rate-war tax: 18%, kam rate, exempt, zero, Third Schedule, further tax'**
  String get reportTaxRateHint;

  /// No description provided for @reportSalesByHsCode.
  ///
  /// In ur, this message translates to:
  /// **'HS code-war bikri'**
  String get reportSalesByHsCode;

  /// No description provided for @reportSalesByHsCodeHint.
  ///
  /// In ur, this message translates to:
  /// **'Har HS code ke tehat kitna becha'**
  String get reportSalesByHsCodeHint;

  /// No description provided for @reportAnnexC.
  ///
  /// In ur, this message translates to:
  /// **'Annex-C (bikri)'**
  String get reportAnnexC;

  /// No description provided for @reportAnnexCHint.
  ///
  /// In ur, this message translates to:
  /// **'Har bikri FBR ke Annex-C ke khanon mein, accountant ke liye'**
  String get reportAnnexCHint;

  /// No description provided for @reportAnnexA.
  ///
  /// In ur, this message translates to:
  /// **'Annex-A (khareed)'**
  String get reportAnnexA;

  /// No description provided for @reportAnnexAHint.
  ///
  /// In ur, this message translates to:
  /// **'Har khareed FBR ke Annex-A ke khanon mein'**
  String get reportAnnexAHint;

  /// No description provided for @reportExpenseTransactions.
  ///
  /// In ur, this message translates to:
  /// **'Kharchon ki fehrist'**
  String get reportExpenseTransactions;

  /// No description provided for @reportExpenseTransactionsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har kharcha: kis mad mein, kahan se diya, kis liye'**
  String get reportExpenseTransactionsHint;

  /// No description provided for @reportExpenseCategories.
  ///
  /// In ur, this message translates to:
  /// **'Kharchon ki mad'**
  String get reportExpenseCategories;

  /// No description provided for @reportExpenseCategoriesHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mad ka kul, direct aur indirect'**
  String get reportExpenseCategoriesHint;

  /// No description provided for @reportExpenseItems.
  ///
  /// In ur, this message translates to:
  /// **'Kharchay kis cheez par'**
  String get reportExpenseItems;

  /// No description provided for @reportExpenseItemsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mad mein paisa kis cheez par gaya'**
  String get reportExpenseItemsHint;

  /// No description provided for @reportOpenQuotations.
  ///
  /// In ur, this message translates to:
  /// **'Khuli quotations'**
  String get reportOpenQuotations;

  /// No description provided for @reportOpenQuotationsHint.
  ///
  /// In ur, this message translates to:
  /// **'Jo quotations abhi bill nahi baneen, kitne din se'**
  String get reportOpenQuotationsHint;

  /// No description provided for @reportOpenChallans.
  ///
  /// In ur, this message translates to:
  /// **'Bina bill ke challan'**
  String get reportOpenChallans;

  /// No description provided for @reportOpenChallansHint.
  ///
  /// In ur, this message translates to:
  /// **'Challan par gaya maal jis ka bill abhi nahi bana'**
  String get reportOpenChallansHint;

  /// No description provided for @reportOpenOrderItems.
  ///
  /// In ur, this message translates to:
  /// **'Quotation aur challan ki cheezen'**
  String get reportOpenOrderItems;

  /// No description provided for @reportOpenOrderItemsHint.
  ///
  /// In ur, this message translates to:
  /// **'Khuli quotations aur challan par cheezen aur miqdar'**
  String get reportOpenOrderItemsHint;

  /// No description provided for @reportFilterAccount.
  ///
  /// In ur, this message translates to:
  /// **'Bank ya wallet'**
  String get reportFilterAccount;

  /// No description provided for @reportFilterHead.
  ///
  /// In ur, this message translates to:
  /// **'Kharche ki mad'**
  String get reportFilterHead;

  /// No description provided for @dayCloseSummary.
  ///
  /// In ur, this message translates to:
  /// **'Din ka khulasa dekhein (Z report)'**
  String get dayCloseSummary;

  /// No description provided for @dueOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak'**
  String dueOn(String date);

  /// No description provided for @dueToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj dena hai'**
  String get dueToday;

  /// No description provided for @dueOverdue.
  ///
  /// In ur, this message translates to:
  /// **'{days, plural, =1{1 din der} other{{days} din der}}'**
  String dueOverdue(int days);

  /// No description provided for @dueNotYet.
  ///
  /// In ur, this message translates to:
  /// **'Abhi waqt hai'**
  String get dueNotYet;

  /// No description provided for @khataCreditDays.
  ///
  /// In ur, this message translates to:
  /// **'{days} din ka udhaar'**
  String khataCreditDays(int days);

  /// No description provided for @khataCreditUsual.
  ///
  /// In ur, this message translates to:
  /// **'Aam muddat, {days} din'**
  String khataCreditUsual(int days);

  /// No description provided for @khataReturn.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi {no}'**
  String khataReturn(String no);

  /// No description provided for @partyCreditDays.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar kitne din ka (marzi se)'**
  String get partyCreditDays;

  /// No description provided for @partyCreditDaysHint.
  ///
  /// In ur, this message translates to:
  /// **'Khaali chhorein to {days} din. Badalne se khule billon ki aakhri tareekh bhi badlegi.'**
  String partyCreditDaysHint(int days);

  /// No description provided for @partyCreditDaysInvalid.
  ///
  /// In ur, this message translates to:
  /// **'0 se 365 din ke darmiyan likhein'**
  String get partyCreditDaysInvalid;

  /// No description provided for @promiseTitle.
  ///
  /// In ur, this message translates to:
  /// **'Adaygi ka wada'**
  String get promiseTitle;

  /// No description provided for @promiseRecord.
  ///
  /// In ur, this message translates to:
  /// **'Wada likhein'**
  String get promiseRecord;

  /// No description provided for @promiseNew.
  ///
  /// In ur, this message translates to:
  /// **'Naya wada'**
  String get promiseNew;

  /// No description provided for @promiseNone.
  ///
  /// In ur, this message translates to:
  /// **'Kab dene ka kaha? \"Jumma ko de dunga\" yahan likhein, us din yaad aayega.'**
  String get promiseNone;

  /// No description provided for @promiseWhen.
  ///
  /// In ur, this message translates to:
  /// **'Kab dene ka kaha?'**
  String get promiseWhen;

  /// No description provided for @promiseTomorrow.
  ///
  /// In ur, this message translates to:
  /// **'Kal'**
  String get promiseTomorrow;

  /// No description provided for @promiseFriday.
  ///
  /// In ur, this message translates to:
  /// **'Jumma'**
  String get promiseFriday;

  /// No description provided for @promiseNextWeek.
  ///
  /// In ur, this message translates to:
  /// **'Agle hafte'**
  String get promiseNextWeek;

  /// No description provided for @promiseSalaryDay.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah (1 tareekh)'**
  String get promiseSalaryDay;

  /// No description provided for @promisePickDay.
  ///
  /// In ur, this message translates to:
  /// **'Din chunein'**
  String get promisePickDay;

  /// No description provided for @promiseAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitne ka kaha (marzi se)'**
  String get promiseAmount;

  /// No description provided for @promiseNote.
  ///
  /// In ur, this message translates to:
  /// **'Unhon ne kya kaha (marzi se)'**
  String get promiseNote;

  /// No description provided for @promiseSave.
  ///
  /// In ur, this message translates to:
  /// **'Wada save karein'**
  String get promiseSave;

  /// No description provided for @promiseSaved.
  ///
  /// In ur, this message translates to:
  /// **'Wada likh liya: {date}'**
  String promiseSaved(String date);

  /// No description provided for @promiseFor.
  ///
  /// In ur, this message translates to:
  /// **'{date} ka wada'**
  String promiseFor(String date);

  /// No description provided for @promiseForAmount.
  ///
  /// In ur, this message translates to:
  /// **'{date} ko Rs {amount} ka wada'**
  String promiseForAmount(String date, String amount);

  /// No description provided for @promisePending.
  ///
  /// In ur, this message translates to:
  /// **'Intezar'**
  String get promisePending;

  /// No description provided for @promiseDueToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ka wada'**
  String get promiseDueToday;

  /// No description provided for @promiseKept.
  ///
  /// In ur, this message translates to:
  /// **'Pura hua'**
  String get promiseKept;

  /// No description provided for @promiseBroken.
  ///
  /// In ur, this message translates to:
  /// **'Toot gaya'**
  String get promiseBroken;

  /// No description provided for @promiseReplaced.
  ///
  /// In ur, this message translates to:
  /// **'Naye wade se badla'**
  String get promiseReplaced;

  /// No description provided for @promiseWithdrawnLabel.
  ///
  /// In ur, this message translates to:
  /// **'Hata diya'**
  String get promiseWithdrawnLabel;

  /// No description provided for @promiseWithdraw.
  ///
  /// In ur, this message translates to:
  /// **'Wada hatayein'**
  String get promiseWithdraw;

  /// No description provided for @promiseWithdrawn.
  ///
  /// In ur, this message translates to:
  /// **'Wada hata diya. Purane wadon mein rahega.'**
  String get promiseWithdrawn;

  /// No description provided for @promiseHistory.
  ///
  /// In ur, this message translates to:
  /// **'Purane wade'**
  String get promiseHistory;

  /// No description provided for @promiseBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne {date} ko likha'**
  String promiseBy(String name, String date);

  /// No description provided for @promisePaidSince.
  ///
  /// In ur, this message translates to:
  /// **'Tab se Rs {amount} aaye'**
  String promisePaidSince(String amount);

  /// No description provided for @homeUdhaarDueToday.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak ka udhaar aaj dena hai · Rs {amount}} other{{count} gahakon ka udhaar aaj dena hai · Rs {amount}}}'**
  String homeUdhaarDueToday(int count, String amount);

  /// No description provided for @homeUdhaarOverdue.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak der se · Rs {amount}} other{{count} gahak der se · Rs {amount}}}'**
  String homeUdhaarOverdue(int count, String amount);

  /// No description provided for @homeUdhaarPromised.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak ne aaj dene ka wada kiya · Rs {amount}} other{{count} gahakon ne aaj dene ka wada kiya · Rs {amount}}}'**
  String homeUdhaarPromised(int count, String amount);

  /// No description provided for @chaseSortLate.
  ///
  /// In ur, this message translates to:
  /// **'Sab se der wale pehle'**
  String get chaseSortLate;

  /// No description provided for @chaseSortPromise.
  ///
  /// In ur, this message translates to:
  /// **'Wade ki tareekh se'**
  String get chaseSortPromise;

  /// No description provided for @chaseFilterPromised.
  ///
  /// In ur, this message translates to:
  /// **'Wade wale'**
  String get chaseFilterPromised;

  /// No description provided for @chaseFilterDueToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj dena hai'**
  String get chaseFilterDueToday;

  /// No description provided for @chaseFilterPromisedToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ka wada'**
  String get chaseFilterPromisedToday;

  /// No description provided for @promiseToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj'**
  String get promiseToday;

  /// No description provided for @chaseFilterOverdue.
  ///
  /// In ur, this message translates to:
  /// **'Der wale'**
  String get chaseFilterOverdue;

  /// No description provided for @khataRemindOff.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani band'**
  String get khataRemindOff;

  /// No description provided for @remindedToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj yaad dilaya'**
  String get remindedToday;

  /// No description provided for @remindedDaysAgo.
  ///
  /// In ur, this message translates to:
  /// **'{days, plural, =1{Kal yaad dilaya} other{{days} din pehle yaad dilaya}}'**
  String remindedDaysAgo(int days);

  /// No description provided for @remindedBy.
  ///
  /// In ur, this message translates to:
  /// **'{when} · {name} · {channel}'**
  String remindedBy(String when, String name, String channel);

  /// No description provided for @reminderChannelSms.
  ///
  /// In ur, this message translates to:
  /// **'SMS'**
  String get reminderChannelSms;

  /// No description provided for @reminderChannelShare.
  ///
  /// In ur, this message translates to:
  /// **'Share sheet'**
  String get reminderChannelShare;

  /// No description provided for @reminderLangUrdu.
  ///
  /// In ur, this message translates to:
  /// **'اردو'**
  String get reminderLangUrdu;

  /// No description provided for @reminderLangRoman.
  ///
  /// In ur, this message translates to:
  /// **'Roman Urdu'**
  String get reminderLangRoman;

  /// No description provided for @reminderLangEnglish.
  ///
  /// In ur, this message translates to:
  /// **'English'**
  String get reminderLangEnglish;

  /// No description provided for @chaseRemind.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani bhejein'**
  String get chaseRemind;

  /// No description provided for @chaseSelectLate.
  ///
  /// In ur, this message translates to:
  /// **'Sab der wale chunein'**
  String get chaseSelectLate;

  /// No description provided for @chaseSendCount.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 ko yaad dilayein} other{{count} ko yaad dilayein}}'**
  String chaseSendCount(int count);

  /// No description provided for @chasePickHint.
  ///
  /// In ur, this message translates to:
  /// **'Jin ko yaad dilana hai un par tick lagayein'**
  String get chasePickHint;

  /// No description provided for @roundTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani'**
  String get roundTitle;

  /// No description provided for @roundResume.
  ///
  /// In ur, this message translates to:
  /// **'{left, plural, =1{Yaad-dehani adhoori hai: 1 baqi} other{Yaad-dehani adhoori hai: {left} baqi}}'**
  String roundResume(int left);

  /// No description provided for @roundResumeAction.
  ///
  /// In ur, this message translates to:
  /// **'Jaari rakhein'**
  String get roundResumeAction;

  /// No description provided for @roundDiscard.
  ///
  /// In ur, this message translates to:
  /// **'Khatam karein'**
  String get roundDiscard;

  /// No description provided for @roundChannelSms.
  ///
  /// In ur, this message translates to:
  /// **'SMS'**
  String get roundChannelSms;

  /// No description provided for @roundOpenWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp par kholein'**
  String get roundOpenWhatsApp;

  /// No description provided for @roundOpenSms.
  ///
  /// In ur, this message translates to:
  /// **'SMS mein kholein'**
  String get roundOpenSms;

  /// No description provided for @roundSent.
  ///
  /// In ur, this message translates to:
  /// **'Bhej diya ✓'**
  String get roundSent;

  /// No description provided for @roundSkip.
  ///
  /// In ur, this message translates to:
  /// **'Chhor dein'**
  String get roundSkip;

  /// No description provided for @roundLater.
  ///
  /// In ur, this message translates to:
  /// **'Baad mein'**
  String get roundLater;

  /// No description provided for @roundDone.
  ///
  /// In ur, this message translates to:
  /// **'Sab ho gaye: {sent} ko bheja, {skipped} chhore'**
  String roundDone(int sent, int skipped);

  /// No description provided for @roundFinish.
  ///
  /// In ur, this message translates to:
  /// **'Khatam'**
  String get roundFinish;

  /// No description provided for @roundNoNumber.
  ///
  /// In ur, this message translates to:
  /// **'Number nahi, share sheet se jayega'**
  String get roundNoNumber;

  /// No description provided for @partyReminders.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani'**
  String get partyReminders;

  /// No description provided for @partyReminderLanguage.
  ///
  /// In ur, this message translates to:
  /// **'Kis zabaan mein bhejein'**
  String get partyReminderLanguage;

  /// No description provided for @partyReminderOptOut.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ko yaad-dehani na bhejein'**
  String get partyReminderOptOut;

  /// No description provided for @settingsReminders.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani ke paighamat'**
  String get settingsReminders;

  /// No description provided for @templatesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yaad-dehani ke paighamat'**
  String get templatesTitle;

  /// No description provided for @templatesHint.
  ///
  /// In ur, this message translates to:
  /// **'Har gahak ko unki zabaan wala paigham jata hai. Braces wale khaane khud bhar jate hain; jis line ka khaana khaali ho woh nahi jati.'**
  String get templatesHint;

  /// No description provided for @templatesField.
  ///
  /// In ur, this message translates to:
  /// **'Paigham'**
  String get templatesField;

  /// No description provided for @templatesPreview.
  ///
  /// In ur, this message translates to:
  /// **'Aisa jayega'**
  String get templatesPreview;

  /// No description provided for @templatesSaved.
  ///
  /// In ur, this message translates to:
  /// **'Paigham save ho gaya'**
  String get templatesSaved;

  /// No description provided for @templatesReset.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke asal alfaz wapas layein'**
  String get templatesReset;

  /// No description provided for @templatesResetDone.
  ///
  /// In ur, this message translates to:
  /// **'Asal alfaz wapas aa gaye'**
  String get templatesResetDone;

  /// No description provided for @templatesSampleName.
  ///
  /// In ur, this message translates to:
  /// **'Aslam Karyana'**
  String get templatesSampleName;

  /// No description provided for @khataWriteOff.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui raqam likhein'**
  String get khataWriteOff;

  /// No description provided for @writeOffTitle.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui raqam'**
  String get writeOffTitle;

  /// No description provided for @writeOffExplain.
  ///
  /// In ur, this message translates to:
  /// **'Yeh raqam khate se hat kar \'Doobi hui raqam\' kharche mein jayegi aur munafa nuqsan mein nazar aayegi. Ghalti ho to khate mein is entry ko mansookh karein, udhaar wapas aa jayega.'**
  String get writeOffExplain;

  /// No description provided for @writeOffWhole.
  ///
  /// In ur, this message translates to:
  /// **'Kul baqaya: Rs {amount}'**
  String writeOffWhole(String amount);

  /// No description provided for @writeOffWholeShort.
  ///
  /// In ur, this message translates to:
  /// **'Poora baqaya'**
  String get writeOffWholeShort;

  /// No description provided for @writeOffBills.
  ///
  /// In ur, this message translates to:
  /// **'Sirf kuch bill'**
  String get writeOffBills;

  /// No description provided for @writeOffWhy.
  ///
  /// In ur, this message translates to:
  /// **'Kyun chhor rahe hain?'**
  String get writeOffWhy;

  /// No description provided for @writeOffReasonMoved.
  ///
  /// In ur, this message translates to:
  /// **'Gahak chala gaya'**
  String get writeOffReasonMoved;

  /// No description provided for @writeOffReasonDied.
  ///
  /// In ur, this message translates to:
  /// **'Wafaat ho gayi'**
  String get writeOffReasonDied;

  /// No description provided for @writeOffReasonRefused.
  ///
  /// In ur, this message translates to:
  /// **'Dene se inkaar'**
  String get writeOffReasonRefused;

  /// No description provided for @writeOffReasonClosed.
  ///
  /// In ur, this message translates to:
  /// **'Un ka kaam band'**
  String get writeOffReasonClosed;

  /// No description provided for @writeOffReasonText.
  ///
  /// In ur, this message translates to:
  /// **'Wajah likhein'**
  String get writeOffReasonText;

  /// No description provided for @writeOffReasonRequired.
  ///
  /// In ur, this message translates to:
  /// **'Wajah zaroori hai'**
  String get writeOffReasonRequired;

  /// No description provided for @writeOffPickBills.
  ///
  /// In ur, this message translates to:
  /// **'Kam se kam aik bill chunein'**
  String get writeOffPickBills;

  /// No description provided for @writeOffSave.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui raqam mein likh dein'**
  String get writeOffSave;

  /// No description provided for @writeOffSaved.
  ///
  /// In ur, this message translates to:
  /// **'{no}: Rs {amount} doobi hui raqam mein likh diye'**
  String writeOffSaved(String no, String amount);

  /// No description provided for @badDebtsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Chhori hui raqam'**
  String get badDebtsTitle;

  /// No description provided for @badDebtsWrittenOff.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui'**
  String get badDebtsWrittenOff;

  /// No description provided for @badDebtsDiscounts.
  ///
  /// In ur, this message translates to:
  /// **'Riayat'**
  String get badDebtsDiscounts;

  /// No description provided for @badDebtsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi kuch nahi chhora'**
  String get badDebtsEmpty;

  /// No description provided for @allowanceTotal.
  ///
  /// In ur, this message translates to:
  /// **'Kul (mansookh ke ilawa)'**
  String get allowanceTotal;

  /// No description provided for @allowanceBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne chhora'**
  String allowanceBy(String name);

  /// No description provided for @allowanceDiscountLine.
  ///
  /// In ur, this message translates to:
  /// **'Riayat {no}'**
  String allowanceDiscountLine(String no);

  /// No description provided for @allowanceWriteOffLine.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui raqam {no}'**
  String allowanceWriteOffLine(String no);

  /// No description provided for @entryDiscountTitle.
  ///
  /// In ur, this message translates to:
  /// **'Riayat {no}'**
  String entryDiscountTitle(String no);

  /// No description provided for @entryWriteOffTitle.
  ///
  /// In ur, this message translates to:
  /// **'Doobi hui raqam {no}'**
  String entryWriteOffTitle(String no);

  /// No description provided for @entryAllowanceNoEdit.
  ///
  /// In ur, this message translates to:
  /// **'Isay badla nahi jata: mansookh kar ke dobara likhein.'**
  String get entryAllowanceNoEdit;

  /// No description provided for @tenderModeAdjustment.
  ///
  /// In ur, this message translates to:
  /// **'Chhoot'**
  String get tenderModeAdjustment;

  /// No description provided for @settleDiscountToggle.
  ///
  /// In ur, this message translates to:
  /// **'Baqi chhor dein (riayat se hisaab saaf)'**
  String get settleDiscountToggle;

  /// No description provided for @settleDiscountLine.
  ///
  /// In ur, this message translates to:
  /// **'Riayat: Rs {amount}, sab bill saaf'**
  String settleDiscountLine(String amount);

  /// No description provided for @settleDiscountNone.
  ///
  /// In ur, this message translates to:
  /// **'Itne mein poora hisaab saaf hai, riayat ki zaroorat nahi'**
  String get settleDiscountNone;

  /// No description provided for @settleDiscountReason.
  ///
  /// In ur, this message translates to:
  /// **'Riayat ki wajah (marzi se)'**
  String get settleDiscountReason;

  /// No description provided for @settleDiscountSaved.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} wasool, Rs {discount} chhor diye'**
  String settleDiscountSaved(String amount, String discount);

  /// No description provided for @settleDiscountOverCeiling.
  ///
  /// In ur, this message translates to:
  /// **'Itni riayat aap ki hadd se ziyada hai. Malik, manager ya accountant se karwayein.'**
  String get settleDiscountOverCeiling;

  /// No description provided for @chaseBadDebts.
  ///
  /// In ur, this message translates to:
  /// **'Chhori hui raqam'**
  String get chaseBadDebts;

  /// No description provided for @billMoreActions.
  ///
  /// In ur, this message translates to:
  /// **'Aur'**
  String get billMoreActions;

  /// No description provided for @copyAction.
  ///
  /// In ur, this message translates to:
  /// **'Isi tarah ka naya bill'**
  String get copyAction;

  /// No description provided for @correctAction.
  ///
  /// In ur, this message translates to:
  /// **'Ghalti theek karein'**
  String get correctAction;

  /// No description provided for @copyRatesTitle.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} dobara: kaun se rate?'**
  String copyRatesTitle(String docNo);

  /// No description provided for @copyRatesToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ke rate'**
  String get copyRatesToday;

  /// No description provided for @copyRatesTodayHint.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ki aaj ki qeemat aur riayat'**
  String get copyRatesTodayHint;

  /// No description provided for @copyRatesOld.
  ///
  /// In ur, this message translates to:
  /// **'Purane rate'**
  String get copyRatesOld;

  /// No description provided for @copyRatesOldHint.
  ///
  /// In ur, this message translates to:
  /// **'Jo {docNo} par lage the, riayat samait'**
  String copyRatesOldHint(String docNo);

  /// No description provided for @copyLoaded.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} ki naqal counter par hai'**
  String copyLoaded(String docNo);

  /// No description provided for @copyLeftOut.
  ///
  /// In ur, this message translates to:
  /// **'Yeh nahi aayin: {names}'**
  String copyLeftOut(String names);

  /// No description provided for @copyNothing.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} ki koi cheez counter par nahi aa sakti'**
  String copyNothing(String docNo);

  /// No description provided for @copyWhyGone.
  ///
  /// In ur, this message translates to:
  /// **'{name} (cheez hata di gayi)'**
  String copyWhyGone(String name);

  /// No description provided for @copyWhyFree.
  ///
  /// In ur, this message translates to:
  /// **'{name} (muft)'**
  String copyWhyFree(String name);

  /// No description provided for @copyWhySerial.
  ///
  /// In ur, this message translates to:
  /// **'{name} (serial dobara scan karein)'**
  String copyWhySerial(String name);

  /// No description provided for @copyWhyTwice.
  ///
  /// In ur, this message translates to:
  /// **'{name} (bill par do dafa)'**
  String copyWhyTwice(String name);

  /// No description provided for @copyNoCustomer.
  ///
  /// In ur, this message translates to:
  /// **'{name} ab khate mein nahi; bill bina gahak ke'**
  String copyNoCustomer(String name);

  /// No description provided for @repeatLastOrder.
  ///
  /// In ur, this message translates to:
  /// **'Pichhla order dobara ({docNo})'**
  String repeatLastOrder(String docNo);

  /// No description provided for @correctTitle.
  ///
  /// In ur, this message translates to:
  /// **'Ghalti theek karein'**
  String get correctTitle;

  /// No description provided for @correctExplain.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill mansookh hoga (iska number aur kaghaz waisay hi rahenge) aur iski naqal counter par khulegi. Ghalti theek kar ke naya bill save karein; dono bill aapas mein jure rahenge.'**
  String get correctExplain;

  /// No description provided for @correctPaid.
  ///
  /// In ur, this message translates to:
  /// **'Is bill par Rs {amount} ({mode}) liye gaye the. Naye bill mein yehi raqam pehle se likhi hogi.'**
  String correctPaid(String amount, String mode);

  /// No description provided for @correctUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill udhaar par tha; naya bill bhi udhaar par khulega.'**
  String get correctUdhaar;

  /// No description provided for @correctAbandon.
  ///
  /// In ur, this message translates to:
  /// **'Naya bill save na kiya to bhi yeh bill mansookh hi rahega.'**
  String get correctAbandon;

  /// No description provided for @correctAbandonPaid.
  ///
  /// In ur, this message translates to:
  /// **'Naya bill save na kiya to bhi yeh bill mansookh hi rahega, aur Rs {amount} gahak ko wapas dene honge.'**
  String correctAbandonPaid(String amount);

  /// No description provided for @correctConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh kar ke naya bill kholein'**
  String get correctConfirm;

  /// No description provided for @reasonWrongItem.
  ///
  /// In ur, this message translates to:
  /// **'Galat cheez'**
  String get reasonWrongItem;

  /// No description provided for @reasonWrongQty.
  ///
  /// In ur, this message translates to:
  /// **'Galat tadaad'**
  String get reasonWrongQty;

  /// No description provided for @reasonWrongPrice.
  ///
  /// In ur, this message translates to:
  /// **'Galat qeemat'**
  String get reasonWrongPrice;

  /// No description provided for @reasonWrongCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Galat gahak'**
  String get reasonWrongCustomer;

  /// No description provided for @reasonOrderCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ne order chhor diya'**
  String get reasonOrderCancelled;

  /// No description provided for @correctOnCounter.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} ki jagah naya bill'**
  String correctOnCounter(String docNo);

  /// No description provided for @correctOnCounterHint.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} mansookh ho chuka hai. Theek kar ke paisay lein.'**
  String correctOnCounterHint(String docNo);

  /// No description provided for @correctClearConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Naya bill chhor dein? {docNo} phir bhi mansookh rahega.'**
  String correctClearConfirm(String docNo);

  /// No description provided for @tenderPaidBefore.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} par Rs {amount} ({mode}) liye gaye the; wohi yahan likhe hain.'**
  String tenderPaidBefore(String docNo, String amount, String mode);

  /// No description provided for @tenderPaidBeforeUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} poora udhaar par tha.'**
  String tenderPaidBeforeUdhaar(String docNo);

  /// No description provided for @tenderGiveBack.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} gahak ko wapas dein'**
  String tenderGiveBack(String amount);

  /// No description provided for @tenderTakeMore.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} aur lein'**
  String tenderTakeMore(String amount);

  /// No description provided for @billReplaces.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} ki jagah bana'**
  String billReplaces(String docNo);

  /// No description provided for @billReplacedBy.
  ///
  /// In ur, this message translates to:
  /// **'Iski jagah {docNo} bana'**
  String billReplacedBy(String docNo);

  /// No description provided for @billReplacedByVoid.
  ///
  /// In ur, this message translates to:
  /// **'Iski jagah {docNo} bana (woh bhi mansookh)'**
  String billReplacedByVoid(String docNo);

  /// No description provided for @copyHint.
  ///
  /// In ur, this message translates to:
  /// **'Wohi cheezein aur gahak, naye bill mein'**
  String get copyHint;

  /// No description provided for @trailAction.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh'**
  String get trailAction;

  /// No description provided for @trailTitle.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh · {no}'**
  String trailTitle(String no);

  /// No description provided for @trailEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Is par abhi kuch likha nahi gaya'**
  String get trailEmpty;

  /// No description provided for @trailByOn.
  ///
  /// In ur, this message translates to:
  /// **'{who}, {device} par · {when}'**
  String trailByOn(String who, String device, String when);

  /// No description provided for @trailBy.
  ///
  /// In ur, this message translates to:
  /// **'{who} · {when}'**
  String trailBy(String who, String when);

  /// No description provided for @trailWhy.
  ///
  /// In ur, this message translates to:
  /// **'Wajah: {reason}'**
  String trailWhy(String reason);

  /// No description provided for @trailMade.
  ///
  /// In ur, this message translates to:
  /// **'Banaya gaya'**
  String get trailMade;

  /// No description provided for @trailPrinted.
  ///
  /// In ur, this message translates to:
  /// **'Print hua'**
  String get trailPrinted;

  /// No description provided for @trailPrintFailed.
  ///
  /// In ur, this message translates to:
  /// **'Print nahi hua'**
  String get trailPrintFailed;

  /// No description provided for @trailCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Cancel hua'**
  String get trailCancelled;

  /// No description provided for @trailReturned.
  ///
  /// In ur, this message translates to:
  /// **'Maal wapas aaya'**
  String get trailReturned;

  /// No description provided for @trailPaid.
  ///
  /// In ur, this message translates to:
  /// **'Is par raqam lagi'**
  String get trailPaid;

  /// No description provided for @trailPaidAtCounter.
  ///
  /// In ur, this message translates to:
  /// **'Counter par diye'**
  String get trailPaidAtCounter;

  /// No description provided for @trailLetGo.
  ///
  /// In ur, this message translates to:
  /// **'Chhor diye'**
  String get trailLetGo;

  /// No description provided for @trailSettled.
  ///
  /// In ur, this message translates to:
  /// **'Is bill par laga'**
  String get trailSettled;

  /// No description provided for @trailReleased.
  ///
  /// In ur, this message translates to:
  /// **'Is bill se hata (cancel)'**
  String get trailReleased;

  /// No description provided for @trailCorrected.
  ///
  /// In ur, this message translates to:
  /// **'Durust kiya'**
  String get trailCorrected;

  /// No description provided for @trailChanged.
  ///
  /// In ur, this message translates to:
  /// **'Badla gaya'**
  String get trailChanged;

  /// No description provided for @trailApproved.
  ///
  /// In ur, this message translates to:
  /// **'PIN se ijazat'**
  String get trailApproved;

  /// No description provided for @trailMadeFrom.
  ///
  /// In ur, this message translates to:
  /// **'Is se bana'**
  String get trailMadeFrom;

  /// No description provided for @trailBecame.
  ///
  /// In ur, this message translates to:
  /// **'Bill bana'**
  String get trailBecame;

  /// No description provided for @trailReturnOf.
  ///
  /// In ur, this message translates to:
  /// **'Is bill ki wapsi'**
  String get trailReturnOf;

  /// No description provided for @trailOpen.
  ///
  /// In ur, this message translates to:
  /// **'{no} kholein'**
  String trailOpen(String no);

  /// No description provided for @trailFieldName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get trailFieldName;

  /// No description provided for @trailFieldPhone.
  ///
  /// In ur, this message translates to:
  /// **'Phone'**
  String get trailFieldPhone;

  /// No description provided for @trailFieldAddress.
  ///
  /// In ur, this message translates to:
  /// **'Pata'**
  String get trailFieldAddress;

  /// No description provided for @trailFieldSaleRate.
  ///
  /// In ur, this message translates to:
  /// **'Bechne ka rate'**
  String get trailFieldSaleRate;

  /// No description provided for @trailFieldPurchaseRate.
  ///
  /// In ur, this message translates to:
  /// **'Khareed ka rate'**
  String get trailFieldPurchaseRate;

  /// No description provided for @trailFieldCreditLimit.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd'**
  String get trailFieldCreditLimit;

  /// No description provided for @trailFieldOpening.
  ///
  /// In ur, this message translates to:
  /// **'Pichla baqaya'**
  String get trailFieldOpening;

  /// No description provided for @trailFieldAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam'**
  String get trailFieldAmount;

  /// No description provided for @trailFieldActive.
  ///
  /// In ur, this message translates to:
  /// **'Nazar aata hai'**
  String get trailFieldActive;

  /// No description provided for @trailFieldGroup.
  ///
  /// In ur, this message translates to:
  /// **'Group'**
  String get trailFieldGroup;

  /// No description provided for @trailFieldBarcode.
  ///
  /// In ur, this message translates to:
  /// **'Barcode'**
  String get trailFieldBarcode;

  /// No description provided for @trailYes.
  ///
  /// In ur, this message translates to:
  /// **'Haan'**
  String get trailYes;

  /// No description provided for @trailNo.
  ///
  /// In ur, this message translates to:
  /// **'Nahi'**
  String get trailNo;

  /// No description provided for @approvalClosedTitle.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab band hai'**
  String get approvalClosedTitle;

  /// No description provided for @approvalClosedBody.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak ka hisaab band hai, aur yeh {entryDate} ki entry hai. Sirf Malik apne PIN aur wajah ke saath ise andar daal sakta hai.'**
  String approvalClosedBody(String date, String entryDate);

  /// No description provided for @approvalLockTitle.
  ///
  /// In ur, this message translates to:
  /// **'Data Lock: PIN chahiye'**
  String get approvalLockTitle;

  /// No description provided for @approvalLockBody.
  ///
  /// In ur, this message translates to:
  /// **'Kuch bhi cancel, chhorne ya chhupane se pehle PIN chahiye.'**
  String get approvalLockBody;

  /// No description provided for @approvalWho.
  ///
  /// In ur, this message translates to:
  /// **'Kis ka PIN'**
  String get approvalWho;

  /// No description provided for @approvalReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah (zaroori)'**
  String get approvalReason;

  /// No description provided for @approvalAllow.
  ///
  /// In ur, this message translates to:
  /// **'Ijazat dein'**
  String get approvalAllow;

  /// No description provided for @approvalWrongPin.
  ///
  /// In ur, this message translates to:
  /// **'Ghalat PIN'**
  String get approvalWrongPin;

  /// No description provided for @approvalTooMany.
  ///
  /// In ur, this message translates to:
  /// **'Bohat ghalat PIN. Aadha minute ruk kar dobara.'**
  String get approvalTooMany;

  /// No description provided for @approvalReasonNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Wajah likhein'**
  String get approvalReasonNeeded;

  /// No description provided for @approvalNoPin.
  ///
  /// In ur, this message translates to:
  /// **'Is ka koi PIN nahi, kisi aur ka PIN dein'**
  String get approvalNoPin;

  /// No description provided for @booksLockTitle.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab band aur Data Lock'**
  String get booksLockTitle;

  /// No description provided for @booksClosedThrough.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak hisaab band hai'**
  String booksClosedThrough(String date);

  /// No description provided for @booksOpenNow.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi din band nahi'**
  String get booksOpenNow;

  /// No description provided for @booksCloseExplain.
  ///
  /// In ur, this message translates to:
  /// **'Band din par ya us se pehle ki koi nayi entry, cancel ya durustagi nahi hogi, jab tak Malik PIN aur wajah se ijazat na de. Aaj ki wapsi purane bill par bhi aaj ki hai, woh ho jati hai.'**
  String get booksCloseExplain;

  /// No description provided for @booksCloseThrough.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak band karein'**
  String booksCloseThrough(String date);

  /// No description provided for @booksClosePick.
  ///
  /// In ur, this message translates to:
  /// **'Koi aur din chunein'**
  String get booksClosePick;

  /// No description provided for @booksReopen.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab dobara kholein'**
  String get booksReopen;

  /// No description provided for @booksClosedDone.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab {date} tak band'**
  String booksClosedDone(String date);

  /// No description provided for @booksReopened.
  ///
  /// In ur, this message translates to:
  /// **'Hisaab dobara khul gaya'**
  String get booksReopened;

  /// No description provided for @dataLockTitle.
  ///
  /// In ur, this message translates to:
  /// **'Cancel se pehle PIN (Data Lock)'**
  String get dataLockTitle;

  /// No description provided for @dataLockExplain.
  ///
  /// In ur, this message translates to:
  /// **'Bill ya payment cancel karna, payment durust karna, udhaar chhorna, cheez ya customer chhupana, ya backup wapas lana: har ek se pehle PIN. Jo kar raha hai us ka apna PIN, ya Malik ka.'**
  String get dataLockExplain;

  /// No description provided for @dataLockNeedsPin.
  ///
  /// In ur, this message translates to:
  /// **'Pehle apna PIN rakhein (Staff aur PIN)'**
  String get dataLockNeedsPin;

  /// No description provided for @lateArrivalsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Band hone ke baad counter se aayi entries'**
  String get lateArrivalsTitle;

  /// No description provided for @lateArrivalsExplain.
  ///
  /// In ur, this message translates to:
  /// **'Yeh dusre counter par band hone se pehle bani thin, is liye le li gayin. Band dinon ka hisaab in ke saath dobara dekh lein.'**
  String get lateArrivalsExplain;

  /// No description provided for @homeOrders.
  ///
  /// In ur, this message translates to:
  /// **'Order'**
  String get homeOrders;

  /// No description provided for @ordersTitle.
  ///
  /// In ur, this message translates to:
  /// **'Order'**
  String get ordersTitle;

  /// No description provided for @ordersPurchase.
  ///
  /// In ur, this message translates to:
  /// **'Purchase order (PO)'**
  String get ordersPurchase;

  /// No description provided for @ordersPurchaseHint.
  ///
  /// In ur, this message translates to:
  /// **'Supplier se kya mangwaya, aur kitna aaya'**
  String get ordersPurchaseHint;

  /// No description provided for @ordersSale.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ke order'**
  String get ordersSale;

  /// No description provided for @ordersSaleHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ne kya mangwaya, kitna diya, advance'**
  String get ordersSaleHint;

  /// No description provided for @ordersShortage.
  ///
  /// In ur, this message translates to:
  /// **'Mangwana hai'**
  String get ordersShortage;

  /// No description provided for @ordersShortageHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ne maanga aur shelf par nahi tha'**
  String get ordersShortageHint;

  /// No description provided for @ordersReorder.
  ///
  /// In ur, this message translates to:
  /// **'Order banayein'**
  String get ordersReorder;

  /// No description provided for @ordersReorderHint.
  ///
  /// In ur, this message translates to:
  /// **'Kam maal aur mangwana hai, supplier ke hisaab se'**
  String get ordersReorderHint;

  /// No description provided for @ordersOpenCount.
  ///
  /// In ur, this message translates to:
  /// **'{count} khule'**
  String ordersOpenCount(int count);

  /// No description provided for @orderListEmptyPurchase.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi PO nahi'**
  String get orderListEmptyPurchase;

  /// No description provided for @orderListEmptyPurchaseHint.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ko jo mangwana ho, uski PO banayein aur WhatsApp par bhejein'**
  String get orderListEmptyPurchaseHint;

  /// No description provided for @orderListEmptySale.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi gahak ka order nahi'**
  String get orderListEmptySale;

  /// No description provided for @orderListEmptySaleHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ka order likhein, advance ke saath ya baghair'**
  String get orderListEmptySaleHint;

  /// No description provided for @orderNewPurchase.
  ///
  /// In ur, this message translates to:
  /// **'Nayi PO'**
  String get orderNewPurchase;

  /// No description provided for @orderNewSale.
  ///
  /// In ur, this message translates to:
  /// **'Naya gahak order'**
  String get orderNewSale;

  /// No description provided for @orderStatusOpen.
  ///
  /// In ur, this message translates to:
  /// **'Khula'**
  String get orderStatusOpen;

  /// No description provided for @orderStatusPartIn.
  ///
  /// In ur, this message translates to:
  /// **'Kuch aa gaya'**
  String get orderStatusPartIn;

  /// No description provided for @orderStatusPartOut.
  ///
  /// In ur, this message translates to:
  /// **'Kuch de diya'**
  String get orderStatusPartOut;

  /// No description provided for @orderStatusDoneIn.
  ///
  /// In ur, this message translates to:
  /// **'Sab aa gaya'**
  String get orderStatusDoneIn;

  /// No description provided for @orderStatusDoneOut.
  ///
  /// In ur, this message translates to:
  /// **'Sab de diya'**
  String get orderStatusDoneOut;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh'**
  String get orderStatusCancelled;

  /// No description provided for @orderStatusClosed.
  ///
  /// In ur, this message translates to:
  /// **'Band, baqi nahi aayega'**
  String get orderStatusClosed;

  /// No description provided for @orderLate.
  ///
  /// In ur, this message translates to:
  /// **'Der ho gayi'**
  String get orderLate;

  /// No description provided for @orderDue.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak'**
  String orderDue(String date);

  /// No description provided for @orderAdvance.
  ///
  /// In ur, this message translates to:
  /// **'Advance Rs {amount}'**
  String orderAdvance(String amount);

  /// No description provided for @orderCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Gahak chunein'**
  String get orderCustomer;

  /// No description provided for @orderPartyRequired.
  ///
  /// In ur, this message translates to:
  /// **'Pehle supplier ya gahak chunein'**
  String get orderPartyRequired;

  /// No description provided for @orderNoLinesHint.
  ///
  /// In ur, this message translates to:
  /// **'Jo mangwana hai woh shamil karein'**
  String get orderNoLinesHint;

  /// No description provided for @orderDueExpected.
  ///
  /// In ur, this message translates to:
  /// **'Kab tak aaye'**
  String get orderDueExpected;

  /// No description provided for @orderDuePromised.
  ///
  /// In ur, this message translates to:
  /// **'Kab tak dena hai'**
  String get orderDuePromised;

  /// No description provided for @orderDueTomorrow.
  ///
  /// In ur, this message translates to:
  /// **'Kal'**
  String get orderDueTomorrow;

  /// No description provided for @orderDueInDays.
  ///
  /// In ur, this message translates to:
  /// **'{count} din mein'**
  String orderDueInDays(int count);

  /// No description provided for @orderDueInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh YYYY-MM-DD mein likhein, aaj ya aage ki'**
  String get orderDueInvalid;

  /// No description provided for @orderNote.
  ///
  /// In ur, this message translates to:
  /// **'Note (marzi se)'**
  String get orderNote;

  /// No description provided for @orderAdvanceAmount.
  ///
  /// In ur, this message translates to:
  /// **'Advance (marzi se)'**
  String get orderAdvanceAmount;

  /// No description provided for @orderSave.
  ///
  /// In ur, this message translates to:
  /// **'Order save karein'**
  String get orderSave;

  /// No description provided for @orderSaved.
  ///
  /// In ur, this message translates to:
  /// **'Order {docNo} ban gaya'**
  String orderSaved(String docNo);

  /// No description provided for @orderRate.
  ///
  /// In ur, this message translates to:
  /// **'Rate'**
  String get orderRate;

  /// No description provided for @orderSupplierRate.
  ///
  /// In ur, this message translates to:
  /// **'Supplier ka rate'**
  String get orderSupplierRate;

  /// No description provided for @orderItemNeeds.
  ///
  /// In ur, this message translates to:
  /// **'Tadaad aur rate sahi likhein'**
  String get orderItemNeeds;

  /// No description provided for @orderItemUnitInexact.
  ///
  /// In ur, this message translates to:
  /// **'Is unit mein yeh tadaad poori nahi banti. Doosra unit chunein.'**
  String get orderItemUnitInexact;

  /// No description provided for @orderReceive.
  ///
  /// In ur, this message translates to:
  /// **'Maal aa gaya'**
  String get orderReceive;

  /// No description provided for @orderToCounter.
  ///
  /// In ur, this message translates to:
  /// **'Counter par bill banayein'**
  String get orderToCounter;

  /// No description provided for @orderTakeAdvance.
  ///
  /// In ur, this message translates to:
  /// **'Advance lein'**
  String get orderTakeAdvance;

  /// No description provided for @orderAdvanceTaken.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} advance le liya'**
  String orderAdvanceTaken(String amount);

  /// No description provided for @orderCancel.
  ///
  /// In ur, this message translates to:
  /// **'Order mansookh karein'**
  String get orderCancel;

  /// No description provided for @orderCancelReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah'**
  String get orderCancelReason;

  /// No description provided for @orderCancelNeedsReason.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh karne ki wajah likhein'**
  String get orderCancelNeedsReason;

  /// No description provided for @orderCancelConfirm.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} mansookh ho jaye ga. Jo aa chuka ya ja chuka woh rahe ga. Wajah likh kar dobara dabayein.'**
  String orderCancelConfirm(String docNo);

  /// No description provided for @orderCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Order mansookh ho gaya'**
  String get orderCancelled;

  /// No description provided for @orderLineIn.
  ///
  /// In ur, this message translates to:
  /// **'Aaya {done}, baqi {left} {unit}'**
  String orderLineIn(String done, String left, String unit);

  /// No description provided for @orderLineOut.
  ///
  /// In ur, this message translates to:
  /// **'Diya {done}, baqi {left} {unit}'**
  String orderLineOut(String done, String left, String unit);

  /// No description provided for @orderFollowUps.
  ///
  /// In ur, this message translates to:
  /// **'Is order se'**
  String get orderFollowUps;

  /// No description provided for @orderNothingLeft.
  ///
  /// In ur, this message translates to:
  /// **'Is order mein ab kuch baqi nahi'**
  String get orderNothingLeft;

  /// No description provided for @orderStillToCome.
  ///
  /// In ur, this message translates to:
  /// **'Baqi: Rs {amount}'**
  String orderStillToCome(String amount);

  /// No description provided for @purchaseFromOrder.
  ///
  /// In ur, this message translates to:
  /// **'PO {docNo} ke khilaf'**
  String purchaseFromOrder(String docNo);

  /// No description provided for @purchaseOrderedRate.
  ///
  /// In ur, this message translates to:
  /// **'PO ka rate: {rate} / {unit}'**
  String purchaseOrderedRate(String rate, String unit);

  /// No description provided for @purchaseRateDiffers.
  ///
  /// In ur, this message translates to:
  /// **'Rate PO se mukhtalif: {now} vs {ordered}'**
  String purchaseRateDiffers(String now, String ordered);

  /// No description provided for @shortageAdd.
  ///
  /// In ur, this message translates to:
  /// **'Mangwana hai mein likhein'**
  String get shortageAdd;

  /// No description provided for @shortageEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Kuch mangwana baqi nahi'**
  String get shortageEmpty;

  /// No description provided for @shortageEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak koi cheez maange jo shelf par nahi, to counter ke * se yahan likhein'**
  String get shortageEmptyHint;

  /// No description provided for @shortageWhat.
  ///
  /// In ur, this message translates to:
  /// **'Kya maanga?'**
  String get shortageWhat;

  /// No description provided for @shortageWhatNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Likhein gahak ne kya maanga'**
  String get shortageWhatNeeded;

  /// No description provided for @shortageQty.
  ///
  /// In ur, this message translates to:
  /// **'Kitna (marzi se)'**
  String get shortageQty;

  /// No description provided for @shortageSave.
  ///
  /// In ur, this message translates to:
  /// **'List mein likhein'**
  String get shortageSave;

  /// No description provided for @shortageSaved.
  ///
  /// In ur, this message translates to:
  /// **'{name} list mein likh diya'**
  String shortageSaved(String name);

  /// No description provided for @shortageClear.
  ///
  /// In ur, this message translates to:
  /// **'Mil gaya'**
  String get shortageClear;

  /// No description provided for @shortageShare.
  ///
  /// In ur, this message translates to:
  /// **'List bhejein'**
  String get shortageShare;

  /// No description provided for @reorderEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi kuch mangwane ki zaroorat nahi'**
  String get reorderEmpty;

  /// No description provided for @reorderEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Cheez par kam se kam stock likhein, ya counter se mangwana hai mein daalein'**
  String get reorderEmptyHint;

  /// No description provided for @reorderNoSupplier.
  ///
  /// In ur, this message translates to:
  /// **'Supplier maloom nahi'**
  String get reorderNoSupplier;

  /// No description provided for @reorderFacts.
  ///
  /// In ur, this message translates to:
  /// **'Stock {stock} · {sold} bika · {onOrder} raaste mein'**
  String reorderFacts(String stock, String sold, String onOrder);

  /// No description provided for @reorderAsked.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ne maanga'**
  String get reorderAsked;

  /// No description provided for @reorderMakeOne.
  ///
  /// In ur, this message translates to:
  /// **'Is ki PO'**
  String get reorderMakeOne;

  /// No description provided for @reorderMakeAll.
  ///
  /// In ur, this message translates to:
  /// **'PO banayein ({count} supplier)'**
  String reorderMakeAll(int count);

  /// No description provided for @reorderMade.
  ///
  /// In ur, this message translates to:
  /// **'{count} PO ban gayi'**
  String reorderMade(int count);

  /// No description provided for @reorderNothingPicked.
  ///
  /// In ur, this message translates to:
  /// **'Kuch chuna nahi. Tadaad likhein ya supplier chunein.'**
  String get reorderNothingPicked;

  /// No description provided for @reportOpenPurchaseOrders.
  ///
  /// In ur, this message translates to:
  /// **'Khuli purchase orders'**
  String get reportOpenPurchaseOrders;

  /// No description provided for @reportOpenPurchaseOrdersHint.
  ///
  /// In ur, this message translates to:
  /// **'Supplier se jo maal aana baqi hai, kitne din se'**
  String get reportOpenPurchaseOrdersHint;

  /// No description provided for @reportOpenSaleOrders.
  ///
  /// In ur, this message translates to:
  /// **'Khule gahak order'**
  String get reportOpenSaleOrders;

  /// No description provided for @reportOpenSaleOrdersHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ko jo dena baqi hai, advance ke saath'**
  String get reportOpenSaleOrdersHint;

  /// No description provided for @reportOrderItemsDue.
  ///
  /// In ur, this message translates to:
  /// **'Orders ki cheezein'**
  String get reportOrderItemsDue;

  /// No description provided for @reportOrderItemsDueHint.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez: kitna mangwaya, aaya ya gaya, baqi'**
  String get reportOrderItemsDueHint;

  /// No description provided for @orderItemAdd.
  ///
  /// In ur, this message translates to:
  /// **'Order mein daalein'**
  String get orderItemAdd;

  /// No description provided for @shortageWrite.
  ///
  /// In ur, this message translates to:
  /// **'Likhein'**
  String get shortageWrite;

  /// No description provided for @shelfRuleTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock khatam ho to'**
  String get shelfRuleTitle;

  /// No description provided for @shelfRuleAllow.
  ///
  /// In ur, this message translates to:
  /// **'Bechte rahein'**
  String get shelfRuleAllow;

  /// No description provided for @shelfRuleAllowHint.
  ///
  /// In ur, this message translates to:
  /// **'Koi sawal nahi. Stock minus mein chala jaye ga aur list mein laal dikhe ga.'**
  String get shelfRuleAllowHint;

  /// No description provided for @shelfRuleWarn.
  ///
  /// In ur, this message translates to:
  /// **'Pehle poochein'**
  String get shelfRuleWarn;

  /// No description provided for @shelfRuleWarnHint.
  ///
  /// In ur, this message translates to:
  /// **'Cashier se poocha jaye ga: stock itna hi hai, phir bhi bechein?'**
  String get shelfRuleWarnHint;

  /// No description provided for @shelfRuleBlock.
  ///
  /// In ur, this message translates to:
  /// **'Na bechein'**
  String get shelfRuleBlock;

  /// No description provided for @shelfRuleBlockHint.
  ///
  /// In ur, this message translates to:
  /// **'Stock se zyada nahi bikta. Maalik stock theek kare ya item ki setting badle.'**
  String get shelfRuleBlockHint;

  /// No description provided for @shelfRuleShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ki setting ({rule})'**
  String shelfRuleShop(String rule);

  /// No description provided for @shelfRuleShopHint.
  ///
  /// In ur, this message translates to:
  /// **'Har us item par lagti hai jis ki apni setting nahi. Har item apni bhi rakh sakta hai.'**
  String get shelfRuleShopHint;

  /// No description provided for @shelfRuleOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Yeh setting sirf maalik badal sakta hai.'**
  String get shelfRuleOwnerOnly;

  /// No description provided for @shelfWarnTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock kam hai'**
  String get shelfWarnTitle;

  /// No description provided for @shelfWarnAsk.
  ///
  /// In ur, this message translates to:
  /// **'Stock sirf {onHand} hai — phir bhi bechein?'**
  String shelfWarnAsk(String onHand);

  /// No description provided for @shelfOnBill.
  ///
  /// In ur, this message translates to:
  /// **'{item}: bill par {wanted}'**
  String shelfOnBill(String item, String wanted);

  /// No description provided for @shelfSellAnyway.
  ///
  /// In ur, this message translates to:
  /// **'Haan, bechein'**
  String get shelfSellAnyway;

  /// No description provided for @shelfBlockedTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock se zyada nahi bik sakta'**
  String get shelfBlockedTitle;

  /// No description provided for @shelfBlocked.
  ///
  /// In ur, this message translates to:
  /// **'Stock sirf {onHand} hai — is se zyada nahi bikta. Maalik stock theek kare ya item ki setting badle.'**
  String shelfBlocked(String onHand);

  /// No description provided for @itemsBelowNothing.
  ///
  /// In ur, this message translates to:
  /// **'Stock minus mein'**
  String get itemsBelowNothing;

  /// No description provided for @itemPacksTitle.
  ///
  /// In ur, this message translates to:
  /// **'Packing (carton, dabba, bori)'**
  String get itemPacksTitle;

  /// No description provided for @itemPacksHint.
  ///
  /// In ur, this message translates to:
  /// **'Aik pack mein kitna maal hai. Bill aur khareed pack se bhi ho sakti hai; stock {unit} mein hi ginta hai.'**
  String itemPacksHint(String unit);

  /// No description provided for @itemPackAdd.
  ///
  /// In ur, this message translates to:
  /// **'Pack jorein'**
  String get itemPackAdd;

  /// No description provided for @itemPackUnit.
  ///
  /// In ur, this message translates to:
  /// **'Pack'**
  String get itemPackUnit;

  /// No description provided for @itemPackSize.
  ///
  /// In ur, this message translates to:
  /// **'1 {pack} mein kitne {unit}?'**
  String itemPackSize(String pack, String unit);

  /// No description provided for @itemPackRemove.
  ///
  /// In ur, this message translates to:
  /// **'Pack hatayein'**
  String get itemPackRemove;

  /// No description provided for @itemPackNoneLeft.
  ///
  /// In ur, this message translates to:
  /// **'Har pack lag chuka hai.'**
  String get itemPackNoneLeft;

  /// No description provided for @purchaseInPack.
  ///
  /// In ur, this message translates to:
  /// **'Kis mein aaya'**
  String get purchaseInPack;

  /// No description provided for @reportLoanStatement.
  ///
  /// In ur, this message translates to:
  /// **'Qarz ka hisaab'**
  String get reportLoanStatement;

  /// No description provided for @reportLoanStatementHint.
  ///
  /// In ur, this message translates to:
  /// **'Sab qarz ek safhe par, ya ek qarz ki wasooli, adaigi aur sood'**
  String get reportLoanStatementHint;

  /// No description provided for @reportReceivablesByDue.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar, adaigi ki tareekh se'**
  String get reportReceivablesByDue;

  /// No description provided for @reportReceivablesByDueHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaun der se hai, aur har bill adaigi ki tareekh se kitne din upar'**
  String get reportReceivablesByDueHint;

  /// No description provided for @reportBadDebts.
  ///
  /// In ur, this message translates to:
  /// **'Doobi raqam aur riayat'**
  String get reportBadDebts;

  /// No description provided for @reportBadDebtsHint.
  ///
  /// In ur, this message translates to:
  /// **'Chhora gaya udhaar: kis ka, kyun, kitna, aur kis ne chhora'**
  String get reportBadDebtsHint;

  /// No description provided for @reportFilterLoan.
  ///
  /// In ur, this message translates to:
  /// **'Qarz'**
  String get reportFilterLoan;

  /// No description provided for @reportViewTable.
  ///
  /// In ur, this message translates to:
  /// **'Table'**
  String get reportViewTable;

  /// No description provided for @reportViewChart.
  ///
  /// In ur, this message translates to:
  /// **'Chart'**
  String get reportViewChart;

  /// No description provided for @reportChartRest.
  ///
  /// In ur, this message translates to:
  /// **'Baaqi sab ({count})'**
  String reportChartRest(int count);

  /// No description provided for @reportChartNothing.
  ///
  /// In ur, this message translates to:
  /// **'Is muddat mein dikhane ko kuch nahi'**
  String get reportChartNothing;

  /// No description provided for @reportChartHighest.
  ///
  /// In ur, this message translates to:
  /// **'Sab se ziyada: {label}, {amount}'**
  String reportChartHighest(String label, String amount);

  /// No description provided for @reportChartPicked.
  ///
  /// In ur, this message translates to:
  /// **'{label}: {amount}'**
  String reportChartPicked(String label, String amount);

  /// No description provided for @reportChartTotal.
  ///
  /// In ur, this message translates to:
  /// **'Kul'**
  String get reportChartTotal;

  /// No description provided for @reportChartLeftOut.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 line sifar ya kam hai, dikhayi nahi gayi} other{{count} lines sifar ya kam hain, dikhayi nahi gayin}}'**
  String reportChartLeftOut(int count);

  /// No description provided for @reportChartSummary.
  ///
  /// In ur, this message translates to:
  /// **'{what} ka chart: {count} hisse, kul {amount}'**
  String reportChartSummary(String what, int count, String amount);

  /// No description provided for @reportTodayTitle.
  ///
  /// In ur, this message translates to:
  /// **'Aaj'**
  String get reportTodayTitle;

  /// No description provided for @reportTodaySale.
  ///
  /// In ur, this message translates to:
  /// **'Bikri'**
  String get reportTodaySale;

  /// No description provided for @reportTodayReceived.
  ///
  /// In ur, this message translates to:
  /// **'Wasool'**
  String get reportTodayReceived;

  /// No description provided for @reportTodayUdhaar.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar diya'**
  String get reportTodayUdhaar;

  /// No description provided for @reportTodayExpenses.
  ///
  /// In ur, this message translates to:
  /// **'Kharche'**
  String get reportTodayExpenses;

  /// No description provided for @reportTodayProfit.
  ///
  /// In ur, this message translates to:
  /// **'Maal ka nafa'**
  String get reportTodayProfit;

  /// No description provided for @reportTodayOpen.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ka Z report kholein'**
  String get reportTodayOpen;

  /// No description provided for @reportFilterMinAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam'**
  String get reportFilterMinAmount;

  /// No description provided for @reportFilterMinAmountValue.
  ///
  /// In ur, this message translates to:
  /// **'{amount} ya ziyada'**
  String reportFilterMinAmountValue(String amount);

  /// No description provided for @bonusOnCounter.
  ///
  /// In ur, this message translates to:
  /// **'Bonus / muft: {what}'**
  String bonusOnCounter(String what);

  /// No description provided for @bonusTakeOff.
  ///
  /// In ur, this message translates to:
  /// **'Bonus hatayein'**
  String get bonusTakeOff;

  /// No description provided for @bonusTakenOff.
  ///
  /// In ur, this message translates to:
  /// **'Bonus hata diya: {what}'**
  String bonusTakenOff(String what);

  /// No description provided for @bonusPutBack.
  ///
  /// In ur, this message translates to:
  /// **'Wapas lagayein'**
  String get bonusPutBack;

  /// No description provided for @bonusSchemeHint.
  ///
  /// In ur, this message translates to:
  /// **'Scheme {label}'**
  String bonusSchemeHint(String label);

  /// No description provided for @billSlabApplied.
  ///
  /// In ur, this message translates to:
  /// **'Bill par {percent} discount (Rs {from} se upar)'**
  String billSlabApplied(String percent, String from);

  /// No description provided for @billSlabTakeOff.
  ///
  /// In ur, this message translates to:
  /// **'Hatayein'**
  String get billSlabTakeOff;

  /// No description provided for @billSlabTakenOff.
  ///
  /// In ur, this message translates to:
  /// **'{percent} bill discount hata diya'**
  String billSlabTakenOff(String percent);

  /// No description provided for @billSlabNext.
  ///
  /// In ur, this message translates to:
  /// **'Rs {short} ka aur saman lein to bill par {percent} discount'**
  String billSlabNext(String short, String percent);

  /// No description provided for @schemesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Scheme aur slab'**
  String get schemesTitle;

  /// No description provided for @schemesIntro.
  ///
  /// In ur, this message translates to:
  /// **'Bonus (10+1), tadaad par sasta rate, aur bare bill par discount. Counter khud lagata hai, aur cashier bill se hata sakta hai.'**
  String get schemesIntro;

  /// No description provided for @schemesOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Scheme sirf malik badal sakta hai.'**
  String get schemesOwnerOnly;

  /// No description provided for @schemesItemsHeader.
  ///
  /// In ur, this message translates to:
  /// **'Maal ki scheme'**
  String get schemesItemsHeader;

  /// No description provided for @schemesNoItems.
  ///
  /// In ur, this message translates to:
  /// **'Abhi kisi maal par scheme nahi.'**
  String get schemesNoItems;

  /// No description provided for @schemesAddItem.
  ///
  /// In ur, this message translates to:
  /// **'Maal par scheme lagayein'**
  String get schemesAddItem;

  /// No description provided for @schemeBonusLabel.
  ///
  /// In ur, this message translates to:
  /// **'Bonus {label}'**
  String schemeBonusLabel(String label);

  /// No description provided for @schemeSlabsLabel.
  ///
  /// In ur, this message translates to:
  /// **'{count} rate slab'**
  String schemeSlabsLabel(int count);

  /// No description provided for @billSlabsHeader.
  ///
  /// In ur, this message translates to:
  /// **'Bare bill par discount'**
  String get billSlabsHeader;

  /// No description provided for @billSlabFrom.
  ///
  /// In ur, this message translates to:
  /// **'Bill kam az kam (Rs)'**
  String get billSlabFrom;

  /// No description provided for @billSlabPercent.
  ///
  /// In ur, this message translates to:
  /// **'Discount %'**
  String get billSlabPercent;

  /// No description provided for @schemeAddSlab.
  ///
  /// In ur, this message translates to:
  /// **'Aur slab'**
  String get schemeAddSlab;

  /// No description provided for @schemeSaved.
  ///
  /// In ur, this message translates to:
  /// **'Scheme save ho gayi'**
  String get schemeSaved;

  /// No description provided for @schemeTakeOff.
  ///
  /// In ur, this message translates to:
  /// **'Scheme hatayein'**
  String get schemeTakeOff;

  /// No description provided for @itemSchemeTitle.
  ///
  /// In ur, this message translates to:
  /// **'Scheme: {name}'**
  String itemSchemeTitle(String name);

  /// No description provided for @itemSchemeEntry.
  ///
  /// In ur, this message translates to:
  /// **'Scheme (10+1) aur tadaad par rate'**
  String get itemSchemeEntry;

  /// No description provided for @itemSchemeSaveFirst.
  ///
  /// In ur, this message translates to:
  /// **'Pehle maal save karein, phir scheme lagayein.'**
  String get itemSchemeSaveFirst;

  /// No description provided for @bonusHeader.
  ///
  /// In ur, this message translates to:
  /// **'Bonus (muft maal)'**
  String get bonusHeader;

  /// No description provided for @bonusBuy.
  ///
  /// In ur, this message translates to:
  /// **'Itne lein ({unit})'**
  String bonusBuy(String unit);

  /// No description provided for @bonusFree.
  ///
  /// In ur, this message translates to:
  /// **'Itne muft ({unit})'**
  String bonusFree(String unit);

  /// No description provided for @bonusCountedIn.
  ///
  /// In ur, this message translates to:
  /// **'Ginti kis mein'**
  String get bonusCountedIn;

  /// No description provided for @bonusFreeGoods.
  ///
  /// In ur, this message translates to:
  /// **'Muft: {name}'**
  String bonusFreeGoods(String name);

  /// No description provided for @bonusSameItem.
  ///
  /// In ur, this message translates to:
  /// **'yehi maal'**
  String get bonusSameItem;

  /// No description provided for @bonusOtherItem.
  ///
  /// In ur, this message translates to:
  /// **'Doosra maal'**
  String get bonusOtherItem;

  /// No description provided for @bonusExplain.
  ///
  /// In ur, this message translates to:
  /// **'Har {buy} par {free} muft'**
  String bonusExplain(String buy, String free);

  /// No description provided for @slabsHeader.
  ///
  /// In ur, this message translates to:
  /// **'Tadaad par rate'**
  String get slabsHeader;

  /// No description provided for @slabHint.
  ///
  /// In ur, this message translates to:
  /// **'Slab ka rate sirf tab lagta hai jab gahak ki apni qeemat se kam ho.'**
  String get slabHint;

  /// No description provided for @slabFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ({unit})'**
  String slabFrom(String unit);

  /// No description provided for @slabRate.
  ///
  /// In ur, this message translates to:
  /// **'Rate (fi {unit})'**
  String slabRate(String unit);

  /// No description provided for @schemeProblemFigures.
  ///
  /// In ur, this message translates to:
  /// **'Koi raqam theek nahi likhi. Tadaad aur rate dobara dekhein.'**
  String get schemeProblemFigures;

  /// No description provided for @schemeProblemBonusEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Bonus mein lene aur muft dono ki tadaad likhein.'**
  String get schemeProblemBonusEmpty;

  /// No description provided for @schemeProblemSlabEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Har slab ki tadaad aur rate likhein.'**
  String get schemeProblemSlabEmpty;

  /// No description provided for @schemeProblemSlabTwice.
  ///
  /// In ur, this message translates to:
  /// **'Do slab aik hi raqam se shuru nahi ho sakte.'**
  String get schemeProblemSlabTwice;

  /// No description provided for @schemeProblemOutOfOrder.
  ///
  /// In ur, this message translates to:
  /// **'Bari slab ka rate ya discount behtar hona chahiye.'**
  String get schemeProblemOutOfOrder;

  /// No description provided for @schemeProblemPercent.
  ///
  /// In ur, this message translates to:
  /// **'Discount 0% se zyada aur 50% tak ho.'**
  String get schemeProblemPercent;

  /// No description provided for @purchaseFree.
  ///
  /// In ur, this message translates to:
  /// **'Muft / bonus ({unit})'**
  String purchaseFree(String unit);

  /// No description provided for @purchaseFreeOnLine.
  ///
  /// In ur, this message translates to:
  /// **'+ {what} muft'**
  String purchaseFreeOnLine(String what);

  /// No description provided for @purchaseFreeWrong.
  ///
  /// In ur, this message translates to:
  /// **'Muft tadaad theek nahi likhi.'**
  String get purchaseFreeWrong;

  /// No description provided for @qtyCountedAs.
  ///
  /// In ur, this message translates to:
  /// **'Yani {counted} ({figure})'**
  String qtyCountedAs(String counted, String figure);

  /// No description provided for @qtyNotUnderstood.
  ///
  /// In ur, this message translates to:
  /// **'Samajh nahi aaya. Aise likhein: 2 ctn 5, ya sirf 53.'**
  String get qtyNotUnderstood;

  /// No description provided for @qtyNotWhole.
  ///
  /// In ur, this message translates to:
  /// **'{unit} toot kar nahi bikta. Poora number likhein.'**
  String qtyNotWhole(String unit);

  /// No description provided for @qtyPriceNotEven.
  ///
  /// In ur, this message translates to:
  /// **'Rs {rate} ka {pack} aik {unit} ke poore paise nahi banta. Pehle {unit} ki qeemat likhein.'**
  String qtyPriceNotEven(String rate, String pack, String unit);

  /// No description provided for @qtyStepUp.
  ///
  /// In ur, this message translates to:
  /// **'+1 {unit}'**
  String qtyStepUp(String unit);

  /// No description provided for @qtyStepDown.
  ///
  /// In ur, this message translates to:
  /// **'−1 {unit}'**
  String qtyStepDown(String unit);

  /// No description provided for @qtyStepUpLabel.
  ///
  /// In ur, this message translates to:
  /// **'Aik {unit} aur'**
  String qtyStepUpLabel(String unit);

  /// No description provided for @qtyStepDownLabel.
  ///
  /// In ur, this message translates to:
  /// **'Aik {unit} kam'**
  String qtyStepDownLabel(String unit);

  /// No description provided for @qtyKeypadLetters.
  ///
  /// In ur, this message translates to:
  /// **'Haroof se likhein (2 ctn 5)'**
  String get qtyKeypadLetters;

  /// No description provided for @qtyKeypadNumbers.
  ///
  /// In ur, this message translates to:
  /// **'Sirf number'**
  String get qtyKeypadNumbers;

  /// No description provided for @qtyPriceEach.
  ///
  /// In ur, this message translates to:
  /// **'1 {unit} = Rs {price}'**
  String qtyPriceEach(String unit, String price);

  /// No description provided for @qtyPriceAbout.
  ///
  /// In ur, this message translates to:
  /// **'1 {unit} ≈ Rs {price}'**
  String qtyPriceAbout(String unit, String price);

  /// No description provided for @posStockWords.
  ///
  /// In ur, this message translates to:
  /// **'Stock: {qty}'**
  String posStockWords(String qty);

  /// No description provided for @mrpOnLine.
  ///
  /// In ur, this message translates to:
  /// **'MRP Rs {mrp}'**
  String mrpOnLine(String mrp);

  /// No description provided for @mrpAbove.
  ///
  /// In ur, this message translates to:
  /// **'chhapi qeemat se zyada'**
  String get mrpAbove;

  /// No description provided for @buyerNameTitle.
  ///
  /// In ur, this message translates to:
  /// **'Khareedar ka naam: Rs 1 lakh se bara bill'**
  String get buyerNameTitle;

  /// No description provided for @buyerNameRequiredHint.
  ///
  /// In ur, this message translates to:
  /// **'FBR ko Rs 1,00,000 se bare bill par khareedar ka naam chahiye.'**
  String get buyerNameRequiredHint;

  /// No description provided for @buyerNameWarnHint.
  ///
  /// In ur, this message translates to:
  /// **'Registered dukaan Rs 1,00,000 se bare bill par khareedar ka naam likhti hai. Gahak de to likh lein.'**
  String get buyerNameWarnHint;

  /// No description provided for @buyerName.
  ///
  /// In ur, this message translates to:
  /// **'Khareedar ka naam'**
  String get buyerName;

  /// No description provided for @buyerCnic.
  ///
  /// In ur, this message translates to:
  /// **'CNIC (agar dein)'**
  String get buyerCnic;

  /// No description provided for @buyerNameMissing.
  ///
  /// In ur, this message translates to:
  /// **'Pehle khareedar ka naam likhein: Rs 1,00,000 se bare bill par FBR ko chahiye.'**
  String get buyerNameMissing;

  /// No description provided for @buyerCnicWrong.
  ///
  /// In ur, this message translates to:
  /// **'CNIC 13 hindson ka hota hai, jaise 35202-1234567-1.'**
  String get buyerCnicWrong;

  /// No description provided for @serviceTaxTitle.
  ///
  /// In ur, this message translates to:
  /// **'Services par sales tax (soobah)'**
  String get serviceTaxTitle;

  /// No description provided for @serviceTaxHint.
  ///
  /// In ur, this message translates to:
  /// **'Repair, salon, darzi ya restaurant ke liye. Jo item service hain un par maal wale 18% ki jagah soobe ka tax lagta hai, aur card, wallet ya QR se bill dene par kam.'**
  String get serviceTaxHint;

  /// No description provided for @serviceTaxNone.
  ///
  /// In ur, this message translates to:
  /// **'Koi nahi'**
  String get serviceTaxNone;

  /// No description provided for @serviceTaxPra.
  ///
  /// In ur, this message translates to:
  /// **'PRA (Punjab)'**
  String get serviceTaxPra;

  /// No description provided for @serviceTaxSrb.
  ///
  /// In ur, this message translates to:
  /// **'SRB (Sindh)'**
  String get serviceTaxSrb;

  /// No description provided for @serviceTaxKpra.
  ///
  /// In ur, this message translates to:
  /// **'KPRA (Khyber Pakhtunkhwa)'**
  String get serviceTaxKpra;

  /// No description provided for @serviceTaxBra.
  ///
  /// In ur, this message translates to:
  /// **'BRA (Balochistan)'**
  String get serviceTaxBra;

  /// No description provided for @serviceTaxStandard.
  ///
  /// In ur, this message translates to:
  /// **'Naqad par rate (%)'**
  String get serviceTaxStandard;

  /// No description provided for @serviceTaxDigital.
  ///
  /// In ur, this message translates to:
  /// **'Card, wallet ya QR par rate (%)'**
  String get serviceTaxDigital;

  /// No description provided for @serviceTaxUnchecked.
  ///
  /// In ur, this message translates to:
  /// **'Is soobe ke rate check nahi kiye gaye: apne notice wale rate likhein.'**
  String get serviceTaxUnchecked;

  /// No description provided for @serviceTaxSave.
  ///
  /// In ur, this message translates to:
  /// **'Service tax save karein'**
  String get serviceTaxSave;

  /// No description provided for @serviceTaxSaved.
  ///
  /// In ur, this message translates to:
  /// **'Service tax save ho gaya'**
  String get serviceTaxSaved;

  /// No description provided for @serviceTaxRateWrong.
  ///
  /// In ur, this message translates to:
  /// **'Har rate 0 se 50 tak percent mein likhein.'**
  String get serviceTaxRateWrong;

  /// No description provided for @itemThirdSchedule.
  ///
  /// In ur, this message translates to:
  /// **'Third Schedule (chhapi qeemat par bikta hai)'**
  String get itemThirdSchedule;

  /// No description provided for @itemThirdScheduleHint.
  ///
  /// In ur, this message translates to:
  /// **'Sales tax MRP par lagta hai (MRP x 18/118), aur MRP se mehnga bechne par counter khabardar karta hai.'**
  String get itemThirdScheduleHint;

  /// No description provided for @itemThirdScheduleNeedsMrp.
  ///
  /// In ur, this message translates to:
  /// **'Third Schedule item ki MRP (chhapi qeemat) likhein.'**
  String get itemThirdScheduleNeedsMrp;

  /// No description provided for @itemService.
  ///
  /// In ur, this message translates to:
  /// **'Service hai (repair, salon, khana)'**
  String get itemService;

  /// No description provided for @itemServiceHint.
  ///
  /// In ur, this message translates to:
  /// **'Is par soobe ka tax (PRA, SRB) lagta hai, maal wala 18% nahi.'**
  String get itemServiceHint;

  /// No description provided for @fbrOfflineBadge.
  ///
  /// In ur, this message translates to:
  /// **'Offline bana: FBR ka intezar'**
  String get fbrOfflineBadge;

  /// No description provided for @fbrOverdueBadge.
  ///
  /// In ur, this message translates to:
  /// **'Der: connection aane ke 24 ghante baad bhi nahi gaya'**
  String get fbrOverdueBadge;

  /// No description provided for @fbrOfflineSummary.
  ///
  /// In ur, this message translates to:
  /// **'{count} bill offline bane, FBR ka intezar'**
  String fbrOfflineSummary(int count);

  /// No description provided for @fbrOverdueSummary.
  ///
  /// In ur, this message translates to:
  /// **'{count} connection aane ke 24 ghante baad bhi nahi gaye (FBR Rule 150XC). Abhi bhejein dabayein.'**
  String fbrOverdueSummary(int count);

  /// No description provided for @homeFbrOverdue.
  ///
  /// In ur, this message translates to:
  /// **'FBR: {count} offline bill der se. Abhi bhejein.'**
  String homeFbrOverdue(int count);

  /// No description provided for @photoStripTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kaghaz ki tasveerein'**
  String get photoStripTitle;

  /// No description provided for @photoAdd.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer lein'**
  String get photoAdd;

  /// No description provided for @photoFromCamera.
  ///
  /// In ur, this message translates to:
  /// **'Camera se tasveer khainchein'**
  String get photoFromCamera;

  /// No description provided for @photoFromGallery.
  ///
  /// In ur, this message translates to:
  /// **'Gallery se chunein'**
  String get photoFromGallery;

  /// No description provided for @photoOpen.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer {number} kholein'**
  String photoOpen(int number);

  /// No description provided for @photoAddedBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne lagayi · {when}'**
  String photoAddedBy(String name, String when);

  /// No description provided for @photoFromEarlier.
  ///
  /// In ur, this message translates to:
  /// **'Yeh tasveer pichhli entry par lagi thi, jise is entry ne theek kiya'**
  String get photoFromEarlier;

  /// No description provided for @photoRemoveConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh tasveer hata dein? Yeh \'Hatayi hui cheezein\' mein rahegi aur wahan se wapas laayi ja sakti hai.'**
  String get photoRemoveConfirm;

  /// No description provided for @photoRemoved.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer hata di. \'Hatayi hui cheezein\' se wapas la sakte hain.'**
  String get photoRemoved;

  /// No description provided for @photoFull.
  ///
  /// In ur, this message translates to:
  /// **'Is entry par {max} tasveerein lag chuki hain. Nayi lagane se pehle ek hatayein.'**
  String photoFull(int max);

  /// No description provided for @photoPapersNote.
  ///
  /// In ur, this message translates to:
  /// **'Yeh tasveerein (jaise CNIC ki copy) sirf isi phone par rehti hain. Kisi doosre phone ya server par nahi jaatin; backup mein sirf aap ke password se band ho kar jaati hain.'**
  String get photoPapersNote;

  /// No description provided for @photoCameraRefused.
  ///
  /// In ur, this message translates to:
  /// **'Camera nahi khul saka. Gallery se chun lein.'**
  String get photoCameraRefused;

  /// No description provided for @photosButton.
  ///
  /// In ur, this message translates to:
  /// **'Tasveerein'**
  String get photosButton;

  /// No description provided for @recycleKeptNote.
  ///
  /// In ur, this message translates to:
  /// **'Yahan se kuch khud nahi mitta. Har cheez jab chahein ek tap se wapas aa sakti hai, kyunke purana hisaab un ke baghair poora nahi.'**
  String get recycleKeptNote;

  /// No description provided for @recycleHiddenBy.
  ///
  /// In ur, this message translates to:
  /// **'{who} ne hataya · {when}'**
  String recycleHiddenBy(String who, String when);

  /// No description provided for @recyclePhotos.
  ///
  /// In ur, this message translates to:
  /// **'Tasveerein'**
  String get recyclePhotos;

  /// No description provided for @recyclePhotoFrom.
  ///
  /// In ur, this message translates to:
  /// **'{what} ki tasveer'**
  String recyclePhotoFrom(String what);

  /// No description provided for @recyclePhotoOfShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ka logo ya QR'**
  String get recyclePhotoOfShop;

  /// No description provided for @vanPutAway.
  ///
  /// In ur, this message translates to:
  /// **'Gaari hatayein'**
  String get vanPutAway;

  /// No description provided for @vanPutAwayConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh gaari list se hat jaye gi. Is ki bikri aur hisaab jaisa tha waisa rahega, aur \'Hatayi hui cheezein\' se wapas aa sakti hai.'**
  String get vanPutAwayConfirm;

  /// No description provided for @vanPutAwayDone.
  ///
  /// In ur, this message translates to:
  /// **'Gaari hata di gayi'**
  String get vanPutAwayDone;

  /// No description provided for @recipePutAway.
  ///
  /// In ur, this message translates to:
  /// **'Recipe hatayein'**
  String get recipePutAway;

  /// No description provided for @recipePutAwayConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh recipe list se hat jaye gi. Pehle banaya hua maal aur hisaab waise hi rahega, aur \'Hatayi hui cheezein\' se wapas aa sakti hai.'**
  String get recipePutAwayConfirm;

  /// No description provided for @recipePutAwayDone.
  ///
  /// In ur, this message translates to:
  /// **'Recipe hata di gayi'**
  String get recipePutAwayDone;

  /// No description provided for @goodsGivenRateLater.
  ///
  /// In ur, this message translates to:
  /// **'Maal diya, rate baad mein'**
  String get goodsGivenRateLater;

  /// No description provided for @goodsGivenTitle.
  ///
  /// In ur, this message translates to:
  /// **'Maal diya, bill baqi'**
  String get goodsGivenTitle;

  /// No description provided for @goodsGivenNotOwed.
  ///
  /// In ur, this message translates to:
  /// **'Yeh abhi udhaar mein shamil nahi. Rate lagne par bill banega.'**
  String get goodsGivenNotOwed;

  /// No description provided for @goodsGivenUnpriced.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheez bina rate ke} other{{count} cheezein bina rate ke}}'**
  String goodsGivenUnpriced(int count);

  /// No description provided for @goodsGivenRateMissing.
  ///
  /// In ur, this message translates to:
  /// **'rate baqi'**
  String get goodsGivenRateMissing;

  /// No description provided for @goodsGivenPrice.
  ///
  /// In ur, this message translates to:
  /// **'Rate lagayein'**
  String get goodsGivenPrice;

  /// No description provided for @goodsGivenBill.
  ///
  /// In ur, this message translates to:
  /// **'Bill banayein'**
  String get goodsGivenBill;

  /// No description provided for @goodsGivenMore.
  ///
  /// In ur, this message translates to:
  /// **'Aur maal diya'**
  String get goodsGivenMore;

  /// No description provided for @giveGoodsSaved.
  ///
  /// In ur, this message translates to:
  /// **'Maal likh liya: {docNo}, rate baad mein'**
  String giveGoodsSaved(String docNo);

  /// No description provided for @giveGoodsHint.
  ///
  /// In ur, this message translates to:
  /// **'Cheez aur miqdar likhein. Rate us din lagega jab hisaab hoga.'**
  String get giveGoodsHint;

  /// No description provided for @giveGoodsSearch.
  ///
  /// In ur, this message translates to:
  /// **'Cheez talash karein'**
  String get giveGoodsSearch;

  /// No description provided for @giveGoodsQty.
  ///
  /// In ur, this message translates to:
  /// **'Kitna'**
  String get giveGoodsQty;

  /// No description provided for @giveGoodsRemove.
  ///
  /// In ur, this message translates to:
  /// **'Hatayein'**
  String get giveGoodsRemove;

  /// No description provided for @giveGoodsNote.
  ///
  /// In ur, this message translates to:
  /// **'Note (marzi se)'**
  String get giveGoodsNote;

  /// No description provided for @giveGoodsSave.
  ///
  /// In ur, this message translates to:
  /// **'Maal de diya'**
  String get giveGoodsSave;

  /// No description provided for @giveGoodsNothing.
  ///
  /// In ur, this message translates to:
  /// **'Pehle koi cheez chunein.'**
  String get giveGoodsNothing;

  /// No description provided for @giveGoodsQtyMissing.
  ///
  /// In ur, this message translates to:
  /// **'Har cheez ki miqdar likhein.'**
  String get giveGoodsQtyMissing;

  /// No description provided for @giveGoodsSerial.
  ///
  /// In ur, this message translates to:
  /// **'Serial number wali cheez counter se, scan kar ke dein.'**
  String get giveGoodsSerial;

  /// No description provided for @statementUnpriced.
  ///
  /// In ur, this message translates to:
  /// **'Maal diya, rate baqi ({count}), is hisaab mein shamil nahi: {items}'**
  String statementUnpriced(int count, String items);

  /// No description provided for @priceGoodsHint.
  ///
  /// In ur, this message translates to:
  /// **'Aaj jo rate tay hua woh likhein. Bill counter par banega: wahan udhaar likhein ya paisay lein.'**
  String get priceGoodsHint;

  /// No description provided for @priceGoodsRate.
  ///
  /// In ur, this message translates to:
  /// **'Rate fi {unit}'**
  String priceGoodsRate(String unit);

  /// No description provided for @priceGoodsTotal.
  ///
  /// In ur, this message translates to:
  /// **'Kul'**
  String get priceGoodsTotal;

  /// No description provided for @priceGoodsBill.
  ///
  /// In ur, this message translates to:
  /// **'Counter par bill banayein'**
  String get priceGoodsBill;

  /// No description provided for @priceGoodsFree.
  ///
  /// In ur, this message translates to:
  /// **'Muft'**
  String get priceGoodsFree;

  /// No description provided for @priceGoodsRateMissing.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka rate likhein.'**
  String priceGoodsRateMissing(String name);

  /// No description provided for @priceGoodsNonePicked.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ek challan chunein.'**
  String get priceGoodsNonePicked;

  /// No description provided for @counterRateLater.
  ///
  /// In ur, this message translates to:
  /// **'Rate baad mein (maal de diya)'**
  String get counterRateLater;

  /// No description provided for @chaseUnpriced.
  ///
  /// In ur, this message translates to:
  /// **'Rate baqi: {parties} gahak, {lines} cheezein'**
  String chaseUnpriced(int parties, int lines);

  /// No description provided for @chaseUnpricedTitle.
  ///
  /// In ur, this message translates to:
  /// **'Maal diya, rate baqi'**
  String get chaseUnpricedTitle;

  /// No description provided for @chaseUnpricedSince.
  ///
  /// In ur, this message translates to:
  /// **'{date} se'**
  String chaseUnpricedSince(String date);

  /// No description provided for @sheetsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli sheets'**
  String get sheetsTitle;

  /// No description provided for @sheetsEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi wasooli sheet nahi'**
  String get sheetsEmpty;

  /// No description provided for @sheetsEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Route ya der wale gahak chun kar recovery wale ko numbered sheet dein.'**
  String get sheetsEmptyHint;

  /// No description provided for @sheetNew.
  ///
  /// In ur, this message translates to:
  /// **'Nayi wasooli sheet'**
  String get sheetNew;

  /// No description provided for @sheetCustomers.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak} other{{count} gahak}}'**
  String sheetCustomers(int count);

  /// No description provided for @sheetOut.
  ///
  /// In ur, this message translates to:
  /// **'Bahar hai'**
  String get sheetOut;

  /// No description provided for @sheetSettled.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi likh li'**
  String get sheetSettled;

  /// No description provided for @sheetCollector.
  ///
  /// In ur, this message translates to:
  /// **'Recovery wala'**
  String get sheetCollector;

  /// No description provided for @sheetCollectorName.
  ///
  /// In ur, this message translates to:
  /// **'Ya naam likhein'**
  String get sheetCollectorName;

  /// No description provided for @sheetCollectorMissing.
  ///
  /// In ur, this message translates to:
  /// **'Recovery wale ka naam chunein ya likhein.'**
  String get sheetCollectorMissing;

  /// No description provided for @sheetNoneTicked.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ek gahak chunein.'**
  String get sheetNoneTicked;

  /// No description provided for @sheetPickWho.
  ///
  /// In ur, this message translates to:
  /// **'Kis kis se wasooli?'**
  String get sheetPickWho;

  /// No description provided for @sheetTickAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab chunein'**
  String get sheetTickAll;

  /// No description provided for @sheetMake.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =0{Sheet banayein} =1{Sheet banayein · 1 gahak} other{Sheet banayein · {count} gahak}}'**
  String sheetMake(int count);

  /// No description provided for @sheetPaperTitle.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli sheet'**
  String get sheetPaperTitle;

  /// No description provided for @sheetCollectorLine.
  ///
  /// In ur, this message translates to:
  /// **'Recovery: {name}'**
  String sheetCollectorLine(String name);

  /// No description provided for @sheetPaperGot.
  ///
  /// In ur, this message translates to:
  /// **'Mila:'**
  String get sheetPaperGot;

  /// No description provided for @sheetExpected.
  ///
  /// In ur, this message translates to:
  /// **'Lena hai'**
  String get sheetExpected;

  /// No description provided for @sheetCollected.
  ///
  /// In ur, this message translates to:
  /// **'Wasool hua'**
  String get sheetCollected;

  /// No description provided for @sheetCash.
  ///
  /// In ur, this message translates to:
  /// **'Cash hawale karna hai'**
  String get sheetCash;

  /// No description provided for @sheetPromised.
  ///
  /// In ur, this message translates to:
  /// **'Wade'**
  String get sheetPromised;

  /// No description provided for @sheetColumnNo.
  ///
  /// In ur, this message translates to:
  /// **'Nambar'**
  String get sheetColumnNo;

  /// No description provided for @sheetColumnCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Gahak'**
  String get sheetColumnCustomer;

  /// No description provided for @sheetColumnBills.
  ///
  /// In ur, this message translates to:
  /// **'Bill'**
  String get sheetColumnBills;

  /// No description provided for @sheetColumnResult.
  ///
  /// In ur, this message translates to:
  /// **'Kya hua'**
  String get sheetColumnResult;

  /// No description provided for @sheetSettledBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne likha'**
  String sheetSettledBy(String name);

  /// No description provided for @sheetPaidLine.
  ///
  /// In ur, this message translates to:
  /// **'Pura diya {amount}'**
  String sheetPaidLine(String amount);

  /// No description provided for @sheetPartialLine.
  ///
  /// In ur, this message translates to:
  /// **'Kuch diya {amount}'**
  String sheetPartialLine(String amount);

  /// No description provided for @sheetPromiseLine.
  ///
  /// In ur, this message translates to:
  /// **'Wada: {date}'**
  String sheetPromiseLine(String date);

  /// No description provided for @sheetPromiseAmountLine.
  ///
  /// In ur, this message translates to:
  /// **'Wada: {date}, {amount}'**
  String sheetPromiseAmountLine(String date, String amount);

  /// No description provided for @outcomePaid.
  ///
  /// In ur, this message translates to:
  /// **'Pura diya'**
  String get outcomePaid;

  /// No description provided for @outcomePartial.
  ///
  /// In ur, this message translates to:
  /// **'Kuch diya'**
  String get outcomePartial;

  /// No description provided for @outcomePromise.
  ///
  /// In ur, this message translates to:
  /// **'Wada'**
  String get outcomePromise;

  /// No description provided for @outcomeShopClosed.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan band'**
  String get outcomeShopClosed;

  /// No description provided for @outcomeRefused.
  ///
  /// In ur, this message translates to:
  /// **'Inkaar'**
  String get outcomeRefused;

  /// No description provided for @sheetRecord.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi par likhein'**
  String get sheetRecord;

  /// No description provided for @sheetSave.
  ///
  /// In ur, this message translates to:
  /// **'Sab khaton par likhein'**
  String get sheetSave;

  /// No description provided for @sheetSaved.
  ///
  /// In ur, this message translates to:
  /// **'Wasooli likh li: Rs {amount} aaye'**
  String sheetSaved(String amount);

  /// No description provided for @sheetAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitne mile'**
  String get sheetAmount;

  /// No description provided for @sheetNote.
  ///
  /// In ur, this message translates to:
  /// **'Kya kaha (marzi se)'**
  String get sheetNote;

  /// No description provided for @sheetAmountMissing.
  ///
  /// In ur, this message translates to:
  /// **'{name}: kitne mile, likhein.'**
  String sheetAmountMissing(String name);

  /// No description provided for @sheetPromiseDayMissing.
  ///
  /// In ur, this message translates to:
  /// **'{name}: wade ka din chunein.'**
  String sheetPromiseDayMissing(String name);

  /// No description provided for @sheetCounts.
  ///
  /// In ur, this message translates to:
  /// **'Diye: {paid} · Wade: {promised} · Nahi diye: {notPaid} · Nahi gaye: {notReached}'**
  String sheetCounts(int paid, int promised, int notPaid, int notReached);

  /// No description provided for @pharmacyBatchMrp.
  ///
  /// In ur, this message translates to:
  /// **'MRP fi {unit}'**
  String pharmacyBatchMrp(String unit);

  /// No description provided for @pharmacyMedicineTitle.
  ///
  /// In ur, this message translates to:
  /// **'Dawai ki tafseel'**
  String get pharmacyMedicineTitle;

  /// No description provided for @pharmacyGeneric.
  ///
  /// In ur, this message translates to:
  /// **'Generic naam (salt)'**
  String get pharmacyGeneric;

  /// No description provided for @pharmacyGenericHint.
  ///
  /// In ur, this message translates to:
  /// **'Jaise Paracetamol'**
  String get pharmacyGenericHint;

  /// No description provided for @pharmacyStrength.
  ///
  /// In ur, this message translates to:
  /// **'Strength (taqat)'**
  String get pharmacyStrength;

  /// No description provided for @pharmacyManufacturer.
  ///
  /// In ur, this message translates to:
  /// **'Banane wali company'**
  String get pharmacyManufacturer;

  /// No description provided for @pharmacySchedule.
  ///
  /// In ur, this message translates to:
  /// **'Schedule (control wali dawai)'**
  String get pharmacySchedule;

  /// No description provided for @pharmacyScheduleNone.
  ///
  /// In ur, this message translates to:
  /// **'Schedule nahi'**
  String get pharmacyScheduleNone;

  /// No description provided for @pharmacyScheduleB.
  ///
  /// In ur, this message translates to:
  /// **'Schedule B'**
  String get pharmacyScheduleB;

  /// No description provided for @pharmacyScheduleD.
  ///
  /// In ur, this message translates to:
  /// **'Schedule D'**
  String get pharmacyScheduleD;

  /// No description provided for @pharmacyScheduleOther.
  ///
  /// In ur, this message translates to:
  /// **'Register wali aur dawai'**
  String get pharmacyScheduleOther;

  /// No description provided for @pharmacyScheduleNote.
  ///
  /// In ur, this message translates to:
  /// **'Sirf doctor ke nuskhe par bikti hai; har sale Schedule register mein likhi jati hai.'**
  String get pharmacyScheduleNote;

  /// No description provided for @pharmacySubstitutes.
  ///
  /// In ur, this message translates to:
  /// **'Isi salt ki dawaiyan: {label}'**
  String pharmacySubstitutes(String label);

  /// No description provided for @pharmacyNoSubstitutes.
  ///
  /// In ur, this message translates to:
  /// **'Is salt aur strength ki koi aur dawai nahi.'**
  String get pharmacyNoSubstitutes;

  /// No description provided for @pharmacyOffMrp.
  ///
  /// In ur, this message translates to:
  /// **'MRP (Rs {mrp}) se % kam'**
  String pharmacyOffMrp(String mrp);

  /// No description provided for @pharmacyOffMrpApply.
  ///
  /// In ur, this message translates to:
  /// **'Lagayein'**
  String get pharmacyOffMrpApply;

  /// No description provided for @pharmacyCannotSellTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh nahi bik sakti'**
  String get pharmacyCannotSellTitle;

  /// No description provided for @pharmacyMrpBlockedTitle.
  ///
  /// In ur, this message translates to:
  /// **'DRAP qeemat se zyada'**
  String get pharmacyMrpBlockedTitle;

  /// No description provided for @pharmacyMrpBlocked.
  ///
  /// In ur, this message translates to:
  /// **'{item}: Rs {charged} lag rahe hain, MRP sirf Rs {ceiling} ki ijazat deti hai. Dawai MRP se mehngi nahi bik sakti.'**
  String pharmacyMrpBlocked(String item, String charged, String ceiling);

  /// No description provided for @pharmacyRxTitle.
  ///
  /// In ur, this message translates to:
  /// **'Doctor ka nuskha'**
  String get pharmacyRxTitle;

  /// No description provided for @pharmacyRxFor.
  ///
  /// In ur, this message translates to:
  /// **'Schedule dawai: {names}. Sirf registered doctor ke nuskhe par bikti hai.'**
  String pharmacyRxFor(String names);

  /// No description provided for @pharmacyRxPatient.
  ///
  /// In ur, this message translates to:
  /// **'Mareez ka naam'**
  String get pharmacyRxPatient;

  /// No description provided for @pharmacyRxPatientAddress.
  ///
  /// In ur, this message translates to:
  /// **'Mareez ka pata'**
  String get pharmacyRxPatientAddress;

  /// No description provided for @pharmacyRxDoctor.
  ///
  /// In ur, this message translates to:
  /// **'Doctor ka naam'**
  String get pharmacyRxDoctor;

  /// No description provided for @pharmacyRxRegNo.
  ///
  /// In ur, this message translates to:
  /// **'Doctor ka PM&DC registration no.'**
  String get pharmacyRxRegNo;

  /// No description provided for @pharmacyRxRef.
  ///
  /// In ur, this message translates to:
  /// **'Nuskha no. ya hawala'**
  String get pharmacyRxRef;

  /// No description provided for @pharmacyRxPhoto.
  ///
  /// In ur, this message translates to:
  /// **'Nuskhe ki tasveer'**
  String get pharmacyRxPhoto;

  /// No description provided for @pharmacyRxPhotoTaken.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer lag gayi'**
  String get pharmacyRxPhotoTaken;

  /// No description provided for @pharmacyRxSave.
  ///
  /// In ur, this message translates to:
  /// **'Aage barhein'**
  String get pharmacyRxSave;

  /// No description provided for @pharmacyHoldTitle.
  ///
  /// In ur, this message translates to:
  /// **'Batch {batch}'**
  String pharmacyHoldTitle(String batch);

  /// No description provided for @pharmacyHeld.
  ///
  /// In ur, this message translates to:
  /// **'Roka hua: {reason}'**
  String pharmacyHeld(String reason);

  /// No description provided for @pharmacyHoldReason.
  ///
  /// In ur, this message translates to:
  /// **'Kyun roka?'**
  String get pharmacyHoldReason;

  /// No description provided for @pharmacyHoldReasonHint.
  ///
  /// In ur, this message translates to:
  /// **'DRAP recall, kharab carton…'**
  String get pharmacyHoldReasonHint;

  /// No description provided for @pharmacyHold.
  ///
  /// In ur, this message translates to:
  /// **'Rok dein'**
  String get pharmacyHold;

  /// No description provided for @pharmacyRelease.
  ///
  /// In ur, this message translates to:
  /// **'Dobara bechein'**
  String get pharmacyRelease;

  /// No description provided for @pharmacyHoldDone.
  ///
  /// In ur, this message translates to:
  /// **'Batch rok diya'**
  String get pharmacyHoldDone;

  /// No description provided for @pharmacyReleaseDone.
  ///
  /// In ur, this message translates to:
  /// **'Batch dobara bikne laga'**
  String get pharmacyReleaseDone;

  /// No description provided for @pharmacyNearExpiryTitle.
  ///
  /// In ur, this message translates to:
  /// **'Expiry qareeb — supplier war'**
  String get pharmacyNearExpiryTitle;

  /// No description provided for @pharmacyNearExpiryDays.
  ///
  /// In ur, this message translates to:
  /// **'{days} din'**
  String pharmacyNearExpiryDays(int days);

  /// No description provided for @pharmacyNearExpiryAll.
  ///
  /// In ur, this message translates to:
  /// **'Saare batch'**
  String get pharmacyNearExpiryAll;

  /// No description provided for @pharmacyNearExpiryEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Is muddat mein koi batch expire nahi ho raha.'**
  String get pharmacyNearExpiryEmpty;

  /// No description provided for @pharmacyNoSupplier.
  ///
  /// In ur, this message translates to:
  /// **'Kisi supplier se nahi'**
  String get pharmacyNoSupplier;

  /// No description provided for @pharmacyExpired.
  ///
  /// In ur, this message translates to:
  /// **'Expire ho chuka'**
  String get pharmacyExpired;

  /// No description provided for @pharmacyReturnPicked.
  ///
  /// In ur, this message translates to:
  /// **'{count} batch supplier ko wapas'**
  String pharmacyReturnPicked(int count);

  /// No description provided for @pharmacyReturnReason.
  ///
  /// In ur, this message translates to:
  /// **'Wajah'**
  String get pharmacyReturnReason;

  /// No description provided for @pharmacyReturnReasonDefault.
  ///
  /// In ur, this message translates to:
  /// **'Expiry ki wajah se wapsi'**
  String get pharmacyReturnReasonDefault;

  /// No description provided for @pharmacyReturnConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh {supplier} ko wapas bhejein? Laagat Rs {value}.'**
  String pharmacyReturnConfirm(String supplier, String value);

  /// No description provided for @pharmacyReturnSend.
  ///
  /// In ur, this message translates to:
  /// **'Wapas bhejein'**
  String get pharmacyReturnSend;

  /// No description provided for @pharmacyReturnDone.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi ho gayi: {nos}'**
  String pharmacyReturnDone(String nos);

  /// No description provided for @pharmacyReturnCredited.
  ///
  /// In ur, this message translates to:
  /// **'Un ke khate se Rs {amount} kam'**
  String pharmacyReturnCredited(String amount);

  /// No description provided for @pharmacyReturnRefunded.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} naqd wapas'**
  String pharmacyReturnRefunded(String amount);

  /// No description provided for @pharmacyReturnNote.
  ///
  /// In ur, this message translates to:
  /// **'Wapsi ki parchi bhejein'**
  String get pharmacyReturnNote;

  /// No description provided for @pharmacyShopOffMrp.
  ///
  /// In ur, this message translates to:
  /// **'Har dawai par MRP se % kam'**
  String get pharmacyShopOffMrp;

  /// No description provided for @pharmacyShopOffMrpNote.
  ///
  /// In ur, this message translates to:
  /// **'Har chhapi qeemat wali dawai bill par MRP se itni kam lagegi. MRP se zyada par bechna mana hai.'**
  String get pharmacyShopOffMrpNote;

  /// No description provided for @pharmacyBatchHeldScan.
  ///
  /// In ur, this message translates to:
  /// **'Batch {batch} roka hua hai: {reason}. Yeh na bechein.'**
  String pharmacyBatchHeldScan(String batch, String reason);

  /// No description provided for @reportGroupPharmacy.
  ///
  /// In ur, this message translates to:
  /// **'Pharmacy'**
  String get reportGroupPharmacy;

  /// No description provided for @reportScheduleRegister.
  ///
  /// In ur, this message translates to:
  /// **'Schedule B/D register'**
  String get reportScheduleRegister;

  /// No description provided for @reportScheduleRegisterHint.
  ///
  /// In ur, this message translates to:
  /// **'Har control wali dawai ki aamad o kharch, nuskhe ke saath'**
  String get reportScheduleRegisterHint;

  /// No description provided for @reportSaveView.
  ///
  /// In ur, this message translates to:
  /// **'Yeh view save karein'**
  String get reportSaveView;

  /// No description provided for @reportMyViews.
  ///
  /// In ur, this message translates to:
  /// **'Meri views'**
  String get reportMyViews;

  /// No description provided for @reportViewName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get reportViewName;

  /// No description provided for @reportViewNameHint.
  ///
  /// In ur, this message translates to:
  /// **'maslan Peer ki udhaar list'**
  String get reportViewNameHint;

  /// No description provided for @reportViewKeeps.
  ///
  /// In ur, this message translates to:
  /// **'Is report ka arsa, filter, tarteeb, aur table ya chart yaad rahega. Sirf is phone par, hisaab ki kitaab mein nahi.'**
  String get reportViewKeeps;

  /// No description provided for @reportViewSaved.
  ///
  /// In ur, this message translates to:
  /// **'Meri views mein save ho gaya: {name}'**
  String reportViewSaved(String name);

  /// No description provided for @reportViewRename.
  ///
  /// In ur, this message translates to:
  /// **'Naam badlein'**
  String get reportViewRename;

  /// No description provided for @reportViewDelete.
  ///
  /// In ur, this message translates to:
  /// **'View hatayein'**
  String get reportViewDelete;

  /// No description provided for @reportViewDeleteConfirm.
  ///
  /// In ur, this message translates to:
  /// **'View \"{name}\" hata dein? Report aur hisaab bilkul waise hi rahenge.'**
  String reportViewDeleteConfirm(String name);

  /// No description provided for @reportViewOptions.
  ///
  /// In ur, this message translates to:
  /// **'View ke options'**
  String get reportViewOptions;

  /// No description provided for @recurringAction.
  ///
  /// In ur, this message translates to:
  /// **'Har hafte / Har mahine banayein'**
  String get recurringAction;

  /// No description provided for @recurringActionHint.
  ///
  /// In ur, this message translates to:
  /// **'Isi gahak ka yehi bill, apne din par tayyar'**
  String get recurringActionHint;

  /// No description provided for @recurringNewTitle.
  ///
  /// In ur, this message translates to:
  /// **'Naya baar baar ka bill'**
  String get recurringNewTitle;

  /// No description provided for @recurringListTitle.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ke bill'**
  String get recurringListTitle;

  /// No description provided for @recurringFor.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka bill'**
  String recurringFor(String name);

  /// No description provided for @recurringFromBill.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} se naqal'**
  String recurringFromBill(String docNo);

  /// No description provided for @recurringEvery.
  ///
  /// In ur, this message translates to:
  /// **'Kab kab'**
  String get recurringEvery;

  /// No description provided for @recurringDaily.
  ///
  /// In ur, this message translates to:
  /// **'Roz'**
  String get recurringDaily;

  /// No description provided for @recurringWeekly.
  ///
  /// In ur, this message translates to:
  /// **'Har hafte'**
  String get recurringWeekly;

  /// No description provided for @recurringMonthly.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine'**
  String get recurringMonthly;

  /// No description provided for @recurringEveryFewDays.
  ///
  /// In ur, this message translates to:
  /// **'Har kuch din baad'**
  String get recurringEveryFewDays;

  /// No description provided for @recurringDaysField.
  ///
  /// In ur, this message translates to:
  /// **'Kitne din baad'**
  String get recurringDaysField;

  /// No description provided for @recurringDateField.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ki tareekh (1-31)'**
  String get recurringDateField;

  /// No description provided for @recurringMon.
  ///
  /// In ur, this message translates to:
  /// **'Peer'**
  String get recurringMon;

  /// No description provided for @recurringTue.
  ///
  /// In ur, this message translates to:
  /// **'Mangal'**
  String get recurringTue;

  /// No description provided for @recurringWed.
  ///
  /// In ur, this message translates to:
  /// **'Budh'**
  String get recurringWed;

  /// No description provided for @recurringThu.
  ///
  /// In ur, this message translates to:
  /// **'Jumeraat'**
  String get recurringThu;

  /// No description provided for @recurringFri.
  ///
  /// In ur, this message translates to:
  /// **'Juma'**
  String get recurringFri;

  /// No description provided for @recurringSat.
  ///
  /// In ur, this message translates to:
  /// **'Hafta'**
  String get recurringSat;

  /// No description provided for @recurringSun.
  ///
  /// In ur, this message translates to:
  /// **'Itwar'**
  String get recurringSun;

  /// No description provided for @recurringEveryWeekday.
  ///
  /// In ur, this message translates to:
  /// **'Har {day}'**
  String recurringEveryWeekday(String day);

  /// No description provided for @recurringEveryMonthDate.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine ki {date} tareekh'**
  String recurringEveryMonthDate(int date);

  /// No description provided for @recurringEveryNDays.
  ///
  /// In ur, this message translates to:
  /// **'Har {days} din baad'**
  String recurringEveryNDays(int days);

  /// No description provided for @recurringStart.
  ///
  /// In ur, this message translates to:
  /// **'Kab se'**
  String get recurringStart;

  /// No description provided for @recurringEnds.
  ///
  /// In ur, this message translates to:
  /// **'Kab tak'**
  String get recurringEnds;

  /// No description provided for @recurringEndNever.
  ///
  /// In ur, this message translates to:
  /// **'Jab tak band na karein'**
  String get recurringEndNever;

  /// No description provided for @recurringEndOn.
  ///
  /// In ur, this message translates to:
  /// **'Is tareekh tak'**
  String get recurringEndOn;

  /// No description provided for @recurringEndTimes.
  ///
  /// In ur, this message translates to:
  /// **'Itni dafa'**
  String get recurringEndTimes;

  /// No description provided for @recurringTimesField.
  ///
  /// In ur, this message translates to:
  /// **'Kul kitni dafa'**
  String get recurringTimesField;

  /// No description provided for @recurringEndOnDate.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak'**
  String recurringEndOnDate(String date);

  /// No description provided for @recurringTimesLeft.
  ///
  /// In ur, this message translates to:
  /// **'Kul {times} dafa'**
  String recurringTimesLeft(int times);

  /// No description provided for @recurringPrices.
  ///
  /// In ur, this message translates to:
  /// **'Rate'**
  String get recurringPrices;

  /// No description provided for @recurringPricesToday.
  ///
  /// In ur, this message translates to:
  /// **'Bill banne ke din ke rate'**
  String get recurringPricesToday;

  /// No description provided for @recurringPricesFixed.
  ///
  /// In ur, this message translates to:
  /// **'Isi bill ke rate'**
  String get recurringPricesFixed;

  /// No description provided for @recurringMaking.
  ///
  /// In ur, this message translates to:
  /// **'Kaise banega'**
  String get recurringMaking;

  /// No description provided for @recurringModeRemind.
  ///
  /// In ur, this message translates to:
  /// **'Sirf yaad dilayein'**
  String get recurringModeRemind;

  /// No description provided for @recurringModeAuto.
  ///
  /// In ur, this message translates to:
  /// **'Khud bana dein'**
  String get recurringModeAuto;

  /// No description provided for @recurringModeAutoHint.
  ///
  /// In ur, this message translates to:
  /// **'Home par \'Sab bana dein\' se gahak ke khate mein udhaar. Credit ki hadd, wapas aaya cheque ya stock ki kami ho to pehle poochha jata hai, jaise counter par.'**
  String get recurringModeAutoHint;

  /// No description provided for @recurringModeRemindHint.
  ///
  /// In ur, this message translates to:
  /// **'Us din Home par dikhega; \'Banayein\' se counter par khulega, dekh kar paisay lein.'**
  String get recurringModeRemindHint;

  /// No description provided for @recurringItems.
  ///
  /// In ur, this message translates to:
  /// **'Cheezein'**
  String get recurringItems;

  /// No description provided for @recurringAddItem.
  ///
  /// In ur, this message translates to:
  /// **'Cheez jorein'**
  String get recurringAddItem;

  /// No description provided for @recurringRemoveLine.
  ///
  /// In ur, this message translates to:
  /// **'{name} hatayein'**
  String recurringRemoveLine(String name);

  /// No description provided for @recurringItemGone.
  ///
  /// In ur, this message translates to:
  /// **'Ab nahi rakhi'**
  String get recurringItemGone;

  /// No description provided for @recurringQty.
  ///
  /// In ur, this message translates to:
  /// **'Tadaad'**
  String get recurringQty;

  /// No description provided for @recurringSave.
  ///
  /// In ur, this message translates to:
  /// **'Mehfooz karein'**
  String get recurringSave;

  /// No description provided for @recurringSaved.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ka bill mehfooz ho gaya'**
  String get recurringSaved;

  /// No description provided for @recurringNoCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill kisi gahak ke khate par banta hai. Is bill par koi gahak nahi.'**
  String get recurringNoCustomer;

  /// No description provided for @recurringNoLines.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ek cheez chahiye.'**
  String get recurringNoLines;

  /// No description provided for @recurringBadQty.
  ///
  /// In ur, this message translates to:
  /// **'{name} ki tadaad likhein.'**
  String recurringBadQty(String name);

  /// No description provided for @recurringBadEvery.
  ///
  /// In ur, this message translates to:
  /// **'Yeh din theek nahi.'**
  String get recurringBadEvery;

  /// No description provided for @recurringEndBeforeStart.
  ///
  /// In ur, this message translates to:
  /// **'Khatam hone ki tareekh shuru hone se pehle hai.'**
  String get recurringEndBeforeStart;

  /// No description provided for @recurringBadTimes.
  ///
  /// In ur, this message translates to:
  /// **'Kam az kam ek dafa to banega.'**
  String get recurringBadTimes;

  /// No description provided for @recurringProblemGone.
  ///
  /// In ur, this message translates to:
  /// **'{names} ab nahi rakhi. Counter par khol kar dekhein, ya is bill se hata dein.'**
  String recurringProblemGone(String names);

  /// No description provided for @recurringProblemSerial.
  ///
  /// In ur, this message translates to:
  /// **'{names} serial number se bikti hai. Yeh bill counter par banayein.'**
  String recurringProblemSerial(String names);

  /// No description provided for @recurringProblemUnit.
  ///
  /// In ur, this message translates to:
  /// **'{names}: is ki unit ab cheez ki unit mein nahi badalti.'**
  String recurringProblemUnit(String names);

  /// No description provided for @recurringProblemCustomerGone.
  ///
  /// In ur, this message translates to:
  /// **'Yeh gahak ab khate mein nahi.'**
  String get recurringProblemCustomerGone;

  /// No description provided for @recurringProblemAlreadyMade.
  ///
  /// In ur, this message translates to:
  /// **'Is din ka bill pehle hi ban chuka hai ({docNo}).'**
  String recurringProblemAlreadyMade(String docNo);

  /// No description provided for @recurringProblemAlreadyMadePlain.
  ///
  /// In ur, this message translates to:
  /// **'Is din ka bill pehle hi ban chuka hai.'**
  String get recurringProblemAlreadyMadePlain;

  /// No description provided for @recurringProblemNotKept.
  ///
  /// In ur, this message translates to:
  /// **'Yeh baar baar ka bill ab nahi rakha.'**
  String get recurringProblemNotKept;

  /// No description provided for @recurringWhySerial.
  ///
  /// In ur, this message translates to:
  /// **'{name} (serial wali cheez)'**
  String recurringWhySerial(String name);

  /// No description provided for @recurringDueTitle.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ke bill'**
  String get recurringDueTitle;

  /// No description provided for @recurringMakeOne.
  ///
  /// In ur, this message translates to:
  /// **'Banayein'**
  String get recurringMakeOne;

  /// No description provided for @recurringMakeAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab bana dein ({count})'**
  String recurringMakeAll(int count);

  /// No description provided for @recurringMissed.
  ///
  /// In ur, this message translates to:
  /// **'{count} din ke bill reh gaye ({from} – {to})'**
  String recurringMissed(int count, String from, String to);

  /// No description provided for @recurringDueSince.
  ///
  /// In ur, this message translates to:
  /// **'{date} se due'**
  String recurringDueSince(String date);

  /// No description provided for @recurringDueToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj due'**
  String get recurringDueToday;

  /// No description provided for @recurringByItself.
  ///
  /// In ur, this message translates to:
  /// **'Khud'**
  String get recurringByItself;

  /// No description provided for @recurringRemind.
  ///
  /// In ur, this message translates to:
  /// **'Yaad'**
  String get recurringRemind;

  /// No description provided for @recurringItemCount.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 cheez} other{{count} cheezein}}'**
  String recurringItemCount(int count);

  /// No description provided for @recurringKept.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ke bill: {count} · agla {date}'**
  String recurringKept(int count, String date);

  /// No description provided for @recurringKeptNoNext.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ke bill: {count}'**
  String recurringKeptNoNext(int count);

  /// No description provided for @recurringSeeAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab dekhein'**
  String get recurringSeeAll;

  /// No description provided for @recurringGoneWarn.
  ///
  /// In ur, this message translates to:
  /// **'Ab nahi rakhi: {names}'**
  String recurringGoneWarn(String names);

  /// No description provided for @recurringMissedTitle.
  ///
  /// In ur, this message translates to:
  /// **'{name}: {count} bill reh gaye'**
  String recurringMissedTitle(String name, int count);

  /// No description provided for @recurringMissedBody.
  ///
  /// In ur, this message translates to:
  /// **'In dinon app nahi khula: {dates}. Aap ke kahe baghair kuch nahi banta, aur jo bill ab bane ga woh aaj ki tareekh ka hoga.'**
  String recurringMissedBody(String dates);

  /// No description provided for @recurringMissedAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab banayein ({count})'**
  String recurringMissedAll(int count);

  /// No description provided for @recurringMissedLatest.
  ///
  /// In ur, this message translates to:
  /// **'Sirf aakhri wala ({date})'**
  String recurringMissedLatest(String date);

  /// No description provided for @recurringMissedSkip.
  ///
  /// In ur, this message translates to:
  /// **'Koi nahi, chhor dein'**
  String get recurringMissedSkip;

  /// No description provided for @recurringAsk.
  ///
  /// In ur, this message translates to:
  /// **'Poochhein'**
  String get recurringAsk;

  /// No description provided for @recurringResultsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ke bill'**
  String get recurringResultsTitle;

  /// No description provided for @recurringMadeLine.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} · {name} · Rs {amount}'**
  String recurringMadeLine(String docNo, String name, String amount);

  /// No description provided for @recurringHeldOverLimit.
  ///
  /// In ur, this message translates to:
  /// **'{name}: credit ki hadd Rs {limit}, is bill ke baad Rs {after}.'**
  String recurringHeldOverLimit(String name, String limit, String after);

  /// No description provided for @recurringHeldBounced.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka cheque wapas aaya tha aur paisay abhi baqi hain.'**
  String recurringHeldBounced(String name);

  /// No description provided for @recurringHeldShort.
  ///
  /// In ur, this message translates to:
  /// **'{name}: {items} ka stock kam hai.'**
  String recurringHeldShort(String name, String items);

  /// No description provided for @recurringMakeAnyway.
  ///
  /// In ur, this message translates to:
  /// **'Phir bhi banayein'**
  String get recurringMakeAnyway;

  /// No description provided for @recurringNotMade.
  ///
  /// In ur, this message translates to:
  /// **'{name}: nahi bana. {why}'**
  String recurringNotMade(String name, String why);

  /// No description provided for @recurringNothingToMake.
  ///
  /// In ur, this message translates to:
  /// **'Abhi banane ko kuch nahi.'**
  String get recurringNothingToMake;

  /// No description provided for @recurringEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi baar baar ka bill nahi'**
  String get recurringEmpty;

  /// No description provided for @recurringEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ka koi bill kholein aur upar ke nuqton mein \'Har hafte / Har mahine banayein\' chunein, ya us ke khate se shuru karein.'**
  String get recurringEmptyHint;

  /// No description provided for @recurringPaused.
  ///
  /// In ur, this message translates to:
  /// **'Ruka hua'**
  String get recurringPaused;

  /// No description provided for @recurringActive.
  ///
  /// In ur, this message translates to:
  /// **'Chal raha hai'**
  String get recurringActive;

  /// No description provided for @recurringEnded.
  ///
  /// In ur, this message translates to:
  /// **'Khatam'**
  String get recurringEnded;

  /// No description provided for @recurringNext.
  ///
  /// In ur, this message translates to:
  /// **'Agla: {date}'**
  String recurringNext(String date);

  /// No description provided for @recurringNoNext.
  ///
  /// In ur, this message translates to:
  /// **'Aage koi din nahi'**
  String get recurringNoNext;

  /// No description provided for @recurringPause.
  ///
  /// In ur, this message translates to:
  /// **'Rokein'**
  String get recurringPause;

  /// No description provided for @recurringResume.
  ///
  /// In ur, this message translates to:
  /// **'Phir chalayein'**
  String get recurringResume;

  /// No description provided for @recurringEnd.
  ///
  /// In ur, this message translates to:
  /// **'Khatam karein'**
  String get recurringEnd;

  /// No description provided for @recurringEdit.
  ///
  /// In ur, this message translates to:
  /// **'Badlein'**
  String get recurringEdit;

  /// No description provided for @recurringEndConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Yeh bill ab kabhi due nahi hoga. Is ke bane hue bill waise hi rahenge.'**
  String get recurringEndConfirm;

  /// No description provided for @recurringEndedDone.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ka bill khatam'**
  String get recurringEndedDone;

  /// No description provided for @recurringPausedDone.
  ///
  /// In ur, this message translates to:
  /// **'Rok diya. Phir chalane tak due nahi hoga.'**
  String get recurringPausedDone;

  /// No description provided for @recurringResumedDone.
  ///
  /// In ur, this message translates to:
  /// **'Aaj se phir chal raha hai'**
  String get recurringResumedDone;

  /// No description provided for @recurringHistory.
  ///
  /// In ur, this message translates to:
  /// **'Is ke bane hue bill'**
  String get recurringHistory;

  /// No description provided for @recurringHistoryEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi bill nahi bana'**
  String get recurringHistoryEmpty;

  /// No description provided for @recurringHistoryFor.
  ///
  /// In ur, this message translates to:
  /// **'{date} ka'**
  String recurringHistoryFor(String date);

  /// No description provided for @recurringHistoryLate.
  ///
  /// In ur, this message translates to:
  /// **'{forDate} ka, {madeOn} ko bana'**
  String recurringHistoryLate(String forDate, String madeOn);

  /// No description provided for @recurringCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Mansookh'**
  String get recurringCancelled;

  /// No description provided for @recurringOnKhata.
  ///
  /// In ur, this message translates to:
  /// **'Baar baar ke bill'**
  String get recurringOnKhata;

  /// No description provided for @recurringNewForParty.
  ///
  /// In ur, this message translates to:
  /// **'Naya baar baar ka bill'**
  String get recurringNewForParty;

  /// No description provided for @recurringOnCounter.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka {date} wala bill'**
  String recurringOnCounter(String name, String date);

  /// No description provided for @recurringPickDate.
  ///
  /// In ur, this message translates to:
  /// **'Tareekh chunein'**
  String get recurringPickDate;

  /// No description provided for @businessKindMobile.
  ///
  /// In ur, this message translates to:
  /// **'Mobile shop'**
  String get businessKindMobile;

  /// No description provided for @mobileSearchTitle.
  ///
  /// In ur, this message translates to:
  /// **'Phone dhoondein'**
  String get mobileSearchTitle;

  /// No description provided for @mobileSearchLabel.
  ///
  /// In ur, this message translates to:
  /// **'IMEI (poora, ya aakhri hindsay)'**
  String get mobileSearchLabel;

  /// No description provided for @mobileSearchHint.
  ///
  /// In ur, this message translates to:
  /// **'maslan 43809'**
  String get mobileSearchHint;

  /// No description provided for @mobileSearchTypeMore.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 1 ya IMEI 2 ke kam az kam 3 hindsay likhein. Number dabbe par hai, ya phone par *#06# milayein.'**
  String get mobileSearchTypeMore;

  /// No description provided for @mobileSearchNone.
  ///
  /// In ur, this message translates to:
  /// **'Kisi phone ke IMEI mein {digits} nahi'**
  String mobileSearchNone(String digits);

  /// No description provided for @mobileInShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan mein'**
  String get mobileInShop;

  /// No description provided for @mobileNotInShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan mein nahi'**
  String get mobileNotInShop;

  /// No description provided for @mobileBuyUsedTitle.
  ///
  /// In ur, this message translates to:
  /// **'Purana phone khareedein'**
  String get mobileBuyUsedTitle;

  /// No description provided for @mobileQistPlansTitle.
  ///
  /// In ur, this message translates to:
  /// **'Qist wale phone'**
  String get mobileQistPlansTitle;

  /// No description provided for @mobileStoryGone.
  ///
  /// In ur, this message translates to:
  /// **'Yeh phone ab khaate mein nahi.'**
  String get mobileStoryGone;

  /// No description provided for @mobileAddImei2.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 2 likhein'**
  String get mobileAddImei2;

  /// No description provided for @mobilePtaTitle.
  ///
  /// In ur, this message translates to:
  /// **'PTA'**
  String get mobilePtaTitle;

  /// No description provided for @mobilePtaApproved.
  ///
  /// In ur, this message translates to:
  /// **'PTA approved'**
  String get mobilePtaApproved;

  /// No description provided for @mobilePtaValidUnapproved.
  ///
  /// In ur, this message translates to:
  /// **'Theek hai, PTA approved nahi'**
  String get mobilePtaValidUnapproved;

  /// No description provided for @mobilePtaNonCompliant.
  ///
  /// In ur, this message translates to:
  /// **'Non-compliant (block ho sakta hai)'**
  String get mobilePtaNonCompliant;

  /// No description provided for @mobilePtaUnknown.
  ///
  /// In ur, this message translates to:
  /// **'PTA check nahi kiya'**
  String get mobilePtaUnknown;

  /// No description provided for @mobilePtaCheckedOn.
  ///
  /// In ur, this message translates to:
  /// **'{status} · {date} ko likha'**
  String mobilePtaCheckedOn(String status, String date);

  /// No description provided for @mobilePtaBlockedNote.
  ///
  /// In ur, this message translates to:
  /// **'PTA ke mutabiq non-compliant phone 60 din mein block ho jata hai. Bechne se pehle customer ko batayein.'**
  String get mobilePtaBlockedNote;

  /// No description provided for @mobilePtaCheck.
  ///
  /// In ur, this message translates to:
  /// **'8484 par check karein'**
  String get mobilePtaCheck;

  /// No description provided for @mobilePtaWriteAnswer.
  ///
  /// In ur, this message translates to:
  /// **'PTA ka jawab likhein'**
  String get mobilePtaWriteAnswer;

  /// No description provided for @mobilePtaHow.
  ///
  /// In ur, this message translates to:
  /// **'Aap ki messages app khulegi, IMEI 8484 ko likha hua. Send aap apni SIM se dabayein; PTA SMS se jawab dega, woh yahan likh dein. Yeh app khud kuch nahi bhejti.'**
  String get mobilePtaHow;

  /// No description provided for @mobilePtaNoSmsApp.
  ///
  /// In ur, this message translates to:
  /// **'Messages app nahi khuli. {imei} khud SMS se 8484 par bhejein.'**
  String mobilePtaNoSmsApp(String imei);

  /// No description provided for @mobilePtaAnswerTitle.
  ///
  /// In ur, this message translates to:
  /// **'PTA ne kya jawab diya?'**
  String get mobilePtaAnswerTitle;

  /// No description provided for @mobilePtaUnverifiedNote.
  ///
  /// In ur, this message translates to:
  /// **'Yeh PTA ke jawab akhbaar ke mutabiq hain; is app ne PTA ke apne qawaid se inhein check nahi kiya.'**
  String get mobilePtaUnverifiedNote;

  /// No description provided for @mobilePtaWarnTitle.
  ///
  /// In ur, this message translates to:
  /// **'PTA non-compliant'**
  String get mobilePtaWarnTitle;

  /// No description provided for @mobilePtaWarnBody.
  ///
  /// In ur, this message translates to:
  /// **'{item} ({imei}) PTA ke hisaab se non-compliant likha hai. PTA ke mutabiq aise phone 60 din mein block ho jate hain. Sirf tab bechein jab customer ko pata ho.'**
  String mobilePtaWarnBody(String item, String imei);

  /// No description provided for @mobilePtaWarnSellAnyway.
  ///
  /// In ur, this message translates to:
  /// **'Bechein, customer ko pata hai'**
  String get mobilePtaWarnSellAnyway;

  /// No description provided for @mobileWarrantyTitle.
  ///
  /// In ur, this message translates to:
  /// **'Warranty'**
  String get mobileWarrantyTitle;

  /// No description provided for @mobileWarrantyNone.
  ///
  /// In ur, this message translates to:
  /// **'Is phone par koi warranty nahi di gayi.'**
  String get mobileWarrantyNone;

  /// No description provided for @mobileWarrantyTill.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak warranty'**
  String mobileWarrantyTill(String date);

  /// No description provided for @mobileInWarranty.
  ///
  /// In ur, this message translates to:
  /// **'Warranty mein'**
  String get mobileInWarranty;

  /// No description provided for @mobileOutOfWarranty.
  ///
  /// In ur, this message translates to:
  /// **'Warranty khatam'**
  String get mobileOutOfWarranty;

  /// No description provided for @mobileWarrantyBrand.
  ///
  /// In ur, this message translates to:
  /// **'Company warranty'**
  String get mobileWarrantyBrand;

  /// No description provided for @mobileWarrantyShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ki warranty'**
  String get mobileWarrantyShop;

  /// No description provided for @mobileClaimAdd.
  ///
  /// In ur, this message translates to:
  /// **'Warranty claim likhein'**
  String get mobileClaimAdd;

  /// No description provided for @mobileClaimNote.
  ///
  /// In ur, this message translates to:
  /// **'Kya kharabi hai, aur kya kiya'**
  String get mobileClaimNote;

  /// No description provided for @mobileClaimHint.
  ///
  /// In ur, this message translates to:
  /// **'Screen band, Samsung centre bheja'**
  String get mobileClaimHint;

  /// No description provided for @mobileQistOpenPlan.
  ///
  /// In ur, this message translates to:
  /// **'Is ka qist plan dekhein'**
  String get mobileQistOpenPlan;

  /// No description provided for @mobileSellerTitle.
  ///
  /// In ur, this message translates to:
  /// **'Kis se khareeda'**
  String get mobileSellerTitle;

  /// No description provided for @mobileStoryTitle.
  ///
  /// In ur, this message translates to:
  /// **'Phone ki kahani'**
  String get mobileStoryTitle;

  /// No description provided for @mobileStoryEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi tak is phone ka koi len den nahi.'**
  String get mobileStoryEmpty;

  /// No description provided for @mobileEventWalkIn.
  ///
  /// In ur, this message translates to:
  /// **'walk-in'**
  String get mobileEventWalkIn;

  /// No description provided for @mobileEventBought.
  ///
  /// In ur, this message translates to:
  /// **'{who} se khareeda'**
  String mobileEventBought(String who);

  /// No description provided for @mobileEventSold.
  ///
  /// In ur, this message translates to:
  /// **'{who} ko becha'**
  String mobileEventSold(String who);

  /// No description provided for @mobileEventReturned.
  ///
  /// In ur, this message translates to:
  /// **'{who} wapas laye'**
  String mobileEventReturned(String who);

  /// No description provided for @mobileEventSentBack.
  ///
  /// In ur, this message translates to:
  /// **'{who} ko wapas bheja'**
  String mobileEventSentBack(String who);

  /// No description provided for @mobileEventMoved.
  ///
  /// In ur, this message translates to:
  /// **'Doosri jagah bheja'**
  String get mobileEventMoved;

  /// No description provided for @mobileEventAdjusted.
  ///
  /// In ur, this message translates to:
  /// **'Stock theek kiya'**
  String get mobileEventAdjusted;

  /// No description provided for @mobileEventCancelled.
  ///
  /// In ur, this message translates to:
  /// **'mansookh'**
  String get mobileEventCancelled;

  /// No description provided for @mobileImeiEmpty.
  ///
  /// In ur, this message translates to:
  /// **'IMEI likhein: 15 hindsay, dabbe par ya *#06# se.'**
  String get mobileImeiEmpty;

  /// No description provided for @mobileImeiNotDigits.
  ///
  /// In ur, this message translates to:
  /// **'IMEI mein sirf hindsay hote hain.'**
  String get mobileImeiNotDigits;

  /// No description provided for @mobileImeiLength.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 15 hindson ka hota hai; is mein {count} hain.'**
  String mobileImeiLength(int count);

  /// No description provided for @mobileImeiMistyped.
  ///
  /// In ur, this message translates to:
  /// **'IMEI {digits} ghalat likha hai: aakhri hindsa {last} hona chahiye. Dabbe se ya *#06# se dobara likhein.'**
  String mobileImeiMistyped(String digits, String last);

  /// No description provided for @mobileImeiSameTwice.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 2 aur IMEI 1 ek hi hain. Ek SIM wale phone mein IMEI 2 khaali chhorein.'**
  String get mobileImeiSameTwice;

  /// No description provided for @mobileSellerCnic.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ka CNIC'**
  String get mobileSellerCnic;

  /// No description provided for @mobileSellerKnown.
  ///
  /// In ur, this message translates to:
  /// **'Pehle bhi phone de chuke hain, {name} ke naam se'**
  String mobileSellerKnown(String name);

  /// No description provided for @mobileSellerName.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ka naam'**
  String get mobileSellerName;

  /// No description provided for @mobileSellerPhone.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ka phone number'**
  String get mobileSellerPhone;

  /// No description provided for @mobilePhotosStayHere.
  ///
  /// In ur, this message translates to:
  /// **'CNIC aur phone ki tasveerein isi phone aur is ke backup mein rehti hain. Kisi aur counter ya kahin aur nahi jaatin.'**
  String get mobilePhotosStayHere;

  /// No description provided for @mobilePhoneTitle.
  ///
  /// In ur, this message translates to:
  /// **'Phone'**
  String get mobilePhoneTitle;

  /// No description provided for @mobileNoModels.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi model IMEI se nahi rakha. Pehle Maal mein model banayein, \"Serial / IMEI se\" ke saath.'**
  String get mobileNoModels;

  /// No description provided for @mobileModel.
  ///
  /// In ur, this message translates to:
  /// **'Model'**
  String get mobileModel;

  /// No description provided for @mobileImei1.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 1'**
  String get mobileImei1;

  /// No description provided for @mobileImei2.
  ///
  /// In ur, this message translates to:
  /// **'IMEI 2'**
  String get mobileImei2;

  /// No description provided for @mobileImei2Hint.
  ///
  /// In ur, this message translates to:
  /// **'Sirf do SIM wale mein'**
  String get mobileImei2Hint;

  /// No description provided for @mobileCondition.
  ///
  /// In ur, this message translates to:
  /// **'Haalat'**
  String get mobileCondition;

  /// No description provided for @mobileConditionHint.
  ///
  /// In ur, this message translates to:
  /// **'Peechhe se toota, dabba charger nahi'**
  String get mobileConditionHint;

  /// No description provided for @mobilePaidTitle.
  ///
  /// In ur, this message translates to:
  /// **'Ada kiya'**
  String get mobilePaidTitle;

  /// No description provided for @mobilePricePaid.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ko diye'**
  String get mobilePricePaid;

  /// No description provided for @mobilePaidFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kahan se diye'**
  String get mobilePaidFrom;

  /// No description provided for @mobileBuySave.
  ///
  /// In ur, this message translates to:
  /// **'Khareedein aur stock mein daalein'**
  String get mobileBuySave;

  /// No description provided for @mobileSellerNameNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ka naam likhein.'**
  String get mobileSellerNameNeeded;

  /// No description provided for @mobileCnicBad.
  ///
  /// In ur, this message translates to:
  /// **'CNIC 13 hindson ka hota hai: 12345-1234567-1.'**
  String get mobileCnicBad;

  /// No description provided for @mobileModelNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Phone ka model chunein.'**
  String get mobileModelNeeded;

  /// No description provided for @mobilePriceNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Phone ke kitne diye, likhein.'**
  String get mobilePriceNeeded;

  /// No description provided for @mobileBuyFailed.
  ///
  /// In ur, this message translates to:
  /// **'Phone nahi khareeda gaya. Kuch save nahi hua.'**
  String get mobileBuyFailed;

  /// No description provided for @mobileBuyDone.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} par khareeda, IMEI ke saath stock mein aur purane phone register mein. Ab tasveerein lagayein.'**
  String mobileBuyDone(String docNo);

  /// No description provided for @mobileCnicPhoto.
  ///
  /// In ur, this message translates to:
  /// **'Bechne wale ke CNIC ki tasveer'**
  String get mobileCnicPhoto;

  /// No description provided for @mobilePhonePhoto.
  ///
  /// In ur, this message translates to:
  /// **'Phone ki tasveer'**
  String get mobilePhonePhoto;

  /// No description provided for @mobileOpenStory.
  ///
  /// In ur, this message translates to:
  /// **'Phone ki kahani dekhein'**
  String get mobileOpenStory;

  /// No description provided for @mobileCounterPick.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke phone jin ke IMEI mein {digits} hai'**
  String mobileCounterPick(String digits);

  /// No description provided for @mobileQistSell.
  ///
  /// In ur, this message translates to:
  /// **'Qist par bechein'**
  String get mobileQistSell;

  /// No description provided for @mobileQistNeedsCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Pehle customer chunein: qistein un ke khaate mein jayengi.'**
  String get mobileQistNeedsCustomer;

  /// No description provided for @mobileQistPhones.
  ///
  /// In ur, this message translates to:
  /// **'Maal'**
  String get mobileQistPhones;

  /// No description provided for @mobileQistMarkup.
  ///
  /// In ur, this message translates to:
  /// **'Qist ka munafa (Rs)'**
  String get mobileQistMarkup;

  /// No description provided for @mobileQistMarkupNote.
  ///
  /// In ur, this message translates to:
  /// **'Bill par alag line mein chhapega, total ke andar: customer dekhta hai ke qist ka kitna zyada hai.'**
  String get mobileQistMarkupNote;

  /// No description provided for @mobileQistDown.
  ///
  /// In ur, this message translates to:
  /// **'Abhi naqd advance (Rs)'**
  String get mobileQistDown;

  /// No description provided for @mobileQistCount.
  ///
  /// In ur, this message translates to:
  /// **'Qistein'**
  String get mobileQistCount;

  /// No description provided for @mobileQistDay.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine ki tareekh'**
  String get mobileQistDay;

  /// No description provided for @mobileQistBillTotal.
  ///
  /// In ur, this message translates to:
  /// **'Bill ka total'**
  String get mobileQistBillTotal;

  /// No description provided for @mobileQistDownNow.
  ///
  /// In ur, this message translates to:
  /// **'Advance'**
  String get mobileQistDownNow;

  /// No description provided for @mobileQistOnQist.
  ///
  /// In ur, this message translates to:
  /// **'Qist par'**
  String get mobileQistOnQist;

  /// No description provided for @mobileQistEach.
  ///
  /// In ur, this message translates to:
  /// **'{count} x Rs {amount}'**
  String mobileQistEach(int count, String amount);

  /// No description provided for @mobileQistEachLast.
  ///
  /// In ur, this message translates to:
  /// **'{count} x Rs {amount}, phir Rs {last}'**
  String mobileQistEachLast(int count, String amount, String last);

  /// No description provided for @mobileQistFromTo.
  ///
  /// In ur, this message translates to:
  /// **'{from} se {to} tak'**
  String mobileQistFromTo(String from, String to);

  /// No description provided for @mobileQistGuarantor.
  ///
  /// In ur, this message translates to:
  /// **'Zamin (agar ho)'**
  String get mobileQistGuarantor;

  /// No description provided for @mobileQistGuarantorName.
  ///
  /// In ur, this message translates to:
  /// **'Zamin ka naam'**
  String get mobileQistGuarantorName;

  /// No description provided for @mobileQistGuarantorCnic.
  ///
  /// In ur, this message translates to:
  /// **'Zamin ka CNIC'**
  String get mobileQistGuarantorCnic;

  /// No description provided for @mobileQistGuarantorPhone.
  ///
  /// In ur, this message translates to:
  /// **'Zamin ka phone'**
  String get mobileQistGuarantorPhone;

  /// No description provided for @mobileQistSave.
  ///
  /// In ur, this message translates to:
  /// **'Qist par save karein'**
  String get mobileQistSave;

  /// No description provided for @mobileQistCountBad.
  ///
  /// In ur, this message translates to:
  /// **'1 se {max} qiston tak.'**
  String mobileQistCountBad(int max);

  /// No description provided for @mobileQistDayBad.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ki tareekh 1 se 31 tak.'**
  String get mobileQistDayBad;

  /// No description provided for @mobileQistDownBad.
  ///
  /// In ur, this message translates to:
  /// **'Advance ke baad qist ke liye kuch baqi hona chahiye.'**
  String get mobileQistDownBad;

  /// No description provided for @mobileQistPlanTitle.
  ///
  /// In ur, this message translates to:
  /// **'Qist plan'**
  String get mobileQistPlanTitle;

  /// No description provided for @mobileQistGone.
  ///
  /// In ur, this message translates to:
  /// **'Yeh qist plan ab khaate mein nahi.'**
  String get mobileQistGone;

  /// No description provided for @mobileQistRunning.
  ///
  /// In ur, this message translates to:
  /// **'Chal raha hai'**
  String get mobileQistRunning;

  /// No description provided for @mobileQistOverdue.
  ///
  /// In ur, this message translates to:
  /// **'Der ho gayi'**
  String get mobileQistOverdue;

  /// No description provided for @mobileQistPaidOff.
  ///
  /// In ur, this message translates to:
  /// **'Poora ada'**
  String get mobileQistPaidOff;

  /// No description provided for @mobileQistClosed.
  ///
  /// In ur, this message translates to:
  /// **'Pehle band'**
  String get mobileQistClosed;

  /// No description provided for @mobileQistCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Bill mansookh'**
  String get mobileQistCancelled;

  /// No description provided for @mobileQistMarkupIncluded.
  ///
  /// In ur, this message translates to:
  /// **'Munafa shamil'**
  String get mobileQistMarkupIncluded;

  /// No description provided for @mobileQistPaid.
  ///
  /// In ur, this message translates to:
  /// **'Ab tak ada'**
  String get mobileQistPaid;

  /// No description provided for @mobileQistLeft.
  ///
  /// In ur, this message translates to:
  /// **'Baqi'**
  String get mobileQistLeft;

  /// No description provided for @mobileQistOverdueAmount.
  ///
  /// In ur, this message translates to:
  /// **'Der wali raqam'**
  String get mobileQistOverdueAmount;

  /// No description provided for @mobileQistGuarantorIs.
  ///
  /// In ur, this message translates to:
  /// **'Zamin: {name}'**
  String mobileQistGuarantorIs(String name);

  /// No description provided for @mobileQistClosedOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} ko pehle band: baqi ab wajib'**
  String mobileQistClosedOn(String date);

  /// No description provided for @mobileQistSchedule.
  ///
  /// In ur, this message translates to:
  /// **'Qistein'**
  String get mobileQistSchedule;

  /// No description provided for @mobileQistInstalmentPaid.
  ///
  /// In ur, this message translates to:
  /// **'Ada'**
  String get mobileQistInstalmentPaid;

  /// No description provided for @mobileQistInstalmentLate.
  ///
  /// In ur, this message translates to:
  /// **'{days} din der · Rs {amount} baqi'**
  String mobileQistInstalmentLate(int days, String amount);

  /// No description provided for @mobileQistInstalmentToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj wajib · Rs {amount}'**
  String mobileQistInstalmentToday(String amount);

  /// No description provided for @mobileQistInstalmentPart.
  ///
  /// In ur, this message translates to:
  /// **'Kuch ada · Rs {amount} baqi'**
  String mobileQistInstalmentPart(String amount);

  /// No description provided for @mobileQistInstalmentDue.
  ///
  /// In ur, this message translates to:
  /// **'Aane wali'**
  String get mobileQistInstalmentDue;

  /// No description provided for @mobileQistHowPaid.
  ///
  /// In ur, this message translates to:
  /// **'Paisay customer ke khaate par lein: har wasooli sab se purani qist pehle ada karti hai.'**
  String get mobileQistHowPaid;

  /// No description provided for @mobileQistCloseEarly.
  ///
  /// In ur, this message translates to:
  /// **'Plan pehle band karein'**
  String get mobileQistCloseEarly;

  /// No description provided for @mobileQistCloseConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Plan ke baqi Rs {amount} aaj hi poore wajib ho jayenge, khaate par. Jaldi dene ki riayat khaate par settlement discount se dein.'**
  String mobileQistCloseConfirm(String amount);

  /// No description provided for @mobileQistCloseNote.
  ///
  /// In ur, this message translates to:
  /// **'Wajah (agar ho)'**
  String get mobileQistCloseNote;

  /// No description provided for @mobileQistShowOpen.
  ///
  /// In ur, this message translates to:
  /// **'Chal rahe'**
  String get mobileQistShowOpen;

  /// No description provided for @mobileQistShowAll.
  ///
  /// In ur, this message translates to:
  /// **'Sab'**
  String get mobileQistShowAll;

  /// No description provided for @mobileQistNone.
  ///
  /// In ur, this message translates to:
  /// **'Yahan qist par koi phone nahi'**
  String get mobileQistNone;

  /// No description provided for @mobileQistNoneHint.
  ///
  /// In ur, this message translates to:
  /// **'Counter par paisay wali sheet se qist par bechein.'**
  String get mobileQistNoneHint;

  /// No description provided for @mobileQistPaidOf.
  ///
  /// In ur, this message translates to:
  /// **'{count} mein se {paid} ada'**
  String mobileQistPaidOf(int paid, int count);

  /// No description provided for @mobileQistLeftAmount.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} baqi'**
  String mobileQistLeftAmount(String amount);

  /// No description provided for @mobileQistOverdueShort.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} der'**
  String mobileQistOverdueShort(String amount);

  /// No description provided for @mobileQistNext.
  ///
  /// In ur, this message translates to:
  /// **'agli {date}'**
  String mobileQistNext(String date);

  /// No description provided for @mobileWarrantyMonths.
  ///
  /// In ur, this message translates to:
  /// **'Warranty (mahine)'**
  String get mobileWarrantyMonths;

  /// No description provided for @mobileWarrantyWhose.
  ///
  /// In ur, this message translates to:
  /// **'Kis ki warranty'**
  String get mobileWarrantyWhose;

  /// No description provided for @mobileWarrantyNote.
  ///
  /// In ur, this message translates to:
  /// **'Har bill par khatam hone ki tareekh chhapegi: \"Warranty till 3 Apr 2027\". Khaali ka matlab koi warranty nahi.'**
  String get mobileWarrantyNote;

  /// No description provided for @mobileWarrantyMonthsBad.
  ///
  /// In ur, this message translates to:
  /// **'1 se 120 mahine, ya khaali chhorein.'**
  String get mobileWarrantyMonthsBad;

  /// No description provided for @reportGroupMobile.
  ///
  /// In ur, this message translates to:
  /// **'Mobile shop'**
  String get reportGroupMobile;

  /// No description provided for @reportUsedPhones.
  ///
  /// In ur, this message translates to:
  /// **'Khareede gaye purane phone'**
  String get reportUsedPhones;

  /// No description provided for @reportUsedPhonesHint.
  ///
  /// In ur, this message translates to:
  /// **'Har purana phone, bechne wale ke CNIC aur IMEI ke saath'**
  String get reportUsedPhonesHint;

  /// No description provided for @reportQistInstalments.
  ///
  /// In ur, this message translates to:
  /// **'Qistein'**
  String get reportQistInstalments;

  /// No description provided for @reportQistInstalmentsHint.
  ///
  /// In ur, this message translates to:
  /// **'Har qist wala phone: ada, baqi, der wali'**
  String get reportQistInstalmentsHint;

  /// No description provided for @bonusSentOnChallan.
  ///
  /// In ur, this message translates to:
  /// **'Bonus / muft (challan par gaya): {what}'**
  String bonusSentOnChallan(String what);

  /// No description provided for @reportExpectedCollections.
  ///
  /// In ur, this message translates to:
  /// **'Is hafte ki wasooli'**
  String get reportExpectedCollections;

  /// No description provided for @reportExpectedCollectionsHint.
  ///
  /// In ur, this message translates to:
  /// **'Agle 7 din: kis ka bill ya qist due hai, kis ne kab dene ka wada kiya'**
  String get reportExpectedCollectionsHint;

  /// No description provided for @homeMonthlyBillsDue.
  ///
  /// In ur, this message translates to:
  /// **'Mahana bill: {count} baqi, Rs {amount} — {names}'**
  String homeMonthlyBillsDue(int count, String amount, String names);

  /// No description provided for @trailSharedWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp par bheja'**
  String get trailSharedWhatsApp;

  /// No description provided for @trailSharedPdf.
  ///
  /// In ur, this message translates to:
  /// **'PDF bheji'**
  String get trailSharedPdf;

  /// No description provided for @trailSharedPicture.
  ///
  /// In ur, this message translates to:
  /// **'Tasveer bheji'**
  String get trailSharedPicture;

  /// No description provided for @importFieldGeneric.
  ///
  /// In ur, this message translates to:
  /// **'Generic / salt'**
  String get importFieldGeneric;

  /// No description provided for @importSecondUnitPack.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezen pack ke saath aayengi: {pack}'**
  String importSecondUnitPack(String count, String pack);

  /// No description provided for @sheetChequeNoMissing.
  ///
  /// In ur, this message translates to:
  /// **'{name}: cheque ka number likhein'**
  String sheetChequeNoMissing(String name);

  /// No description provided for @homeUdhaarKhata.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar Khata'**
  String get homeUdhaarKhata;

  /// No description provided for @homeUdhaarKhataOwed.
  ///
  /// In ur, this message translates to:
  /// **'{count, plural, =1{1 gahak se lena hai} other{{count} gahak se lena hai}}'**
  String homeUdhaarKhataOwed(int count);

  /// No description provided for @homeUdhaarKhataClear.
  ///
  /// In ur, this message translates to:
  /// **'Kisi se kuch lena nahi'**
  String get homeUdhaarKhataClear;

  /// No description provided for @homeUdhaarKhataLate.
  ///
  /// In ur, this message translates to:
  /// **'Der wala: Rs {amount}'**
  String homeUdhaarKhataLate(String amount);

  /// No description provided for @staffBookTitle.
  ///
  /// In ur, this message translates to:
  /// **'Staff ki kitaab'**
  String get staffBookTitle;

  /// No description provided for @staffRulesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Staff ki kitaab ke usool'**
  String get staffRulesTitle;

  /// No description provided for @staffAdd.
  ///
  /// In ur, this message translates to:
  /// **'Naya mulazim'**
  String get staffAdd;

  /// No description provided for @staffEdit.
  ///
  /// In ur, this message translates to:
  /// **'Tafseel badlein'**
  String get staffEdit;

  /// No description provided for @staffRegisterToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki hazri'**
  String get staffRegisterToday;

  /// No description provided for @staffRegisterTitle.
  ///
  /// In ur, this message translates to:
  /// **'Hazri register'**
  String get staffRegisterTitle;

  /// No description provided for @staffAdvancesOwedTotal.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi jo wapas aani hai'**
  String get staffAdvancesOwedTotal;

  /// No description provided for @staffEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi mulazim nahi'**
  String get staffEmpty;

  /// No description provided for @staffEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Jinhein tankhwah dete hain unhein shamil karein: salesman, helper, rider, munshi. Unhein phone chalana zaroori nahi.'**
  String get staffEmptyHint;

  /// No description provided for @staffLeftOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} ko chhor gaya'**
  String staffLeftOn(String date);

  /// No description provided for @staffAdvanceOwedChip.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi Rs {amount}'**
  String staffAdvanceOwedChip(String amount);

  /// No description provided for @staffKaamSalesman.
  ///
  /// In ur, this message translates to:
  /// **'Salesman'**
  String get staffKaamSalesman;

  /// No description provided for @staffKaamHelper.
  ///
  /// In ur, this message translates to:
  /// **'Helper'**
  String get staffKaamHelper;

  /// No description provided for @staffKaamRider.
  ///
  /// In ur, this message translates to:
  /// **'Rider'**
  String get staffKaamRider;

  /// No description provided for @staffKaamMunshi.
  ///
  /// In ur, this message translates to:
  /// **'Munshi'**
  String get staffKaamMunshi;

  /// No description provided for @staffKaamOther.
  ///
  /// In ur, this message translates to:
  /// **'Koi aur kaam'**
  String get staffKaamOther;

  /// No description provided for @staffMarkPresent.
  ///
  /// In ur, this message translates to:
  /// **'Haazir'**
  String get staffMarkPresent;

  /// No description provided for @staffMarkLate.
  ///
  /// In ur, this message translates to:
  /// **'Der se'**
  String get staffMarkLate;

  /// No description provided for @staffMarkHalfDay.
  ///
  /// In ur, this message translates to:
  /// **'Aadha din'**
  String get staffMarkHalfDay;

  /// No description provided for @staffMarkPaidLeave.
  ///
  /// In ur, this message translates to:
  /// **'Chutti (tankhwah ke saath)'**
  String get staffMarkPaidLeave;

  /// No description provided for @staffMarkUnpaidLeave.
  ///
  /// In ur, this message translates to:
  /// **'Chutti (bina tankhwah)'**
  String get staffMarkUnpaidLeave;

  /// No description provided for @staffMarkAbsent.
  ///
  /// In ur, this message translates to:
  /// **'Ghair haazir'**
  String get staffMarkAbsent;

  /// No description provided for @staffMarkShortPresent.
  ///
  /// In ur, this message translates to:
  /// **'H'**
  String get staffMarkShortPresent;

  /// No description provided for @staffMarkShortLate.
  ///
  /// In ur, this message translates to:
  /// **'D'**
  String get staffMarkShortLate;

  /// No description provided for @staffMarkShortPaidLeave.
  ///
  /// In ur, this message translates to:
  /// **'C'**
  String get staffMarkShortPaidLeave;

  /// No description provided for @staffMarkShortUnpaidLeave.
  ///
  /// In ur, this message translates to:
  /// **'BC'**
  String get staffMarkShortUnpaidLeave;

  /// No description provided for @staffMarkShortAbsent.
  ///
  /// In ur, this message translates to:
  /// **'G'**
  String get staffMarkShortAbsent;

  /// No description provided for @staffPayMonthly.
  ///
  /// In ur, this message translates to:
  /// **'Mahana Rs {amount}'**
  String staffPayMonthly(String amount);

  /// No description provided for @staffPayDaily.
  ///
  /// In ur, this message translates to:
  /// **'Dihari Rs {amount}'**
  String staffPayDaily(String amount);

  /// No description provided for @staffRegisterRestMarked.
  ///
  /// In ur, this message translates to:
  /// **'{count} ki hazri lag gayi'**
  String staffRegisterRestMarked(int count);

  /// No description provided for @staffDayBefore.
  ///
  /// In ur, this message translates to:
  /// **'Pichla din'**
  String get staffDayBefore;

  /// No description provided for @staffDayAfter.
  ///
  /// In ur, this message translates to:
  /// **'Agla din'**
  String get staffDayAfter;

  /// No description provided for @staffPickDay.
  ///
  /// In ur, this message translates to:
  /// **'Din chunein'**
  String get staffPickDay;

  /// No description provided for @staffRegisterEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Us din koi mulazim nahi tha'**
  String get staffRegisterEmpty;

  /// No description provided for @staffRegisterRestPresent.
  ///
  /// In ur, this message translates to:
  /// **'Baqi sab haazir'**
  String get staffRegisterRestPresent;

  /// No description provided for @staffRegisterNotMarked.
  ///
  /// In ur, this message translates to:
  /// **'Abhi hazri nahi lagi'**
  String get staffRegisterNotMarked;

  /// No description provided for @staffRegisterMarkedBy.
  ///
  /// In ur, this message translates to:
  /// **'{mark}, {name} ne lagayi'**
  String staffRegisterMarkedBy(String mark, String name);

  /// No description provided for @staffRateInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah raqam mein likhein, jaise 25000'**
  String get staffRateInvalid;

  /// No description provided for @staffSaved.
  ///
  /// In ur, this message translates to:
  /// **'Save ho gaya'**
  String get staffSaved;

  /// No description provided for @staffHidden.
  ///
  /// In ur, this message translates to:
  /// **'{name} recycle bin mein chala gaya'**
  String staffHidden(String name);

  /// No description provided for @staffName.
  ///
  /// In ur, this message translates to:
  /// **'Naam'**
  String get staffName;

  /// No description provided for @staffKaam.
  ///
  /// In ur, this message translates to:
  /// **'Kaam'**
  String get staffKaam;

  /// No description provided for @staffBasisMonthly.
  ///
  /// In ur, this message translates to:
  /// **'Mahana tankhwah'**
  String get staffBasisMonthly;

  /// No description provided for @staffBasisDaily.
  ///
  /// In ur, this message translates to:
  /// **'Dihari'**
  String get staffBasisDaily;

  /// No description provided for @staffSalary.
  ///
  /// In ur, this message translates to:
  /// **'Mahana tankhwah (Rs)'**
  String get staffSalary;

  /// No description provided for @staffDayWage.
  ///
  /// In ur, this message translates to:
  /// **'Ek din ki dihari (Rs)'**
  String get staffDayWage;

  /// No description provided for @staffJoinedLabel.
  ///
  /// In ur, this message translates to:
  /// **'Kab se kaam par hai'**
  String get staffJoinedLabel;

  /// No description provided for @staffPhone.
  ///
  /// In ur, this message translates to:
  /// **'Phone (WhatsApp par slip ke liye)'**
  String get staffPhone;

  /// No description provided for @staffCnic.
  ///
  /// In ur, this message translates to:
  /// **'CNIC (marzi se)'**
  String get staffCnic;

  /// No description provided for @staffSignIn.
  ///
  /// In ur, this message translates to:
  /// **'Is app par uska apna login (marzi se)'**
  String get staffSignIn;

  /// No description provided for @staffSignInNone.
  ///
  /// In ur, this message translates to:
  /// **'App nahi chalata'**
  String get staffSignInNone;

  /// No description provided for @staffNote.
  ///
  /// In ur, this message translates to:
  /// **'Note'**
  String get staffNote;

  /// No description provided for @staffHasLeft.
  ///
  /// In ur, this message translates to:
  /// **'Kaam chhor gaya'**
  String get staffHasLeft;

  /// No description provided for @staffHide.
  ///
  /// In ur, this message translates to:
  /// **'Recycle bin mein dalein'**
  String get staffHide;

  /// No description provided for @staffSave.
  ///
  /// In ur, this message translates to:
  /// **'Save karein'**
  String get staffSave;

  /// No description provided for @staffAdvanceCancelTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh peshgi cancel karein'**
  String get staffAdvanceCancelTitle;

  /// No description provided for @staffAdvanceCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi cancel ho gayi ({number})'**
  String staffAdvanceCancelled(String number);

  /// No description provided for @staffCancelReason.
  ///
  /// In ur, this message translates to:
  /// **'Kyun? (entry ke saath rahega)'**
  String get staffCancelReason;

  /// No description provided for @staffCancelConfirm.
  ///
  /// In ur, this message translates to:
  /// **'Cancel karein'**
  String get staffCancelConfirm;

  /// No description provided for @staffJoinedOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} se'**
  String staffJoinedOn(String date);

  /// No description provided for @staffSignsInAs.
  ///
  /// In ur, this message translates to:
  /// **'App par {name} ke naam se'**
  String staffSignsInAs(String name);

  /// No description provided for @staffCnicShown.
  ///
  /// In ur, this message translates to:
  /// **'CNIC {cnic}'**
  String staffCnicShown(String cnic);

  /// No description provided for @staffAdvanceOwed.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi baqi'**
  String get staffAdvanceOwed;

  /// No description provided for @staffGiveAdvance.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi dein'**
  String get staffGiveAdvance;

  /// No description provided for @staffMonthBefore.
  ///
  /// In ur, this message translates to:
  /// **'Pichla mahina'**
  String get staffMonthBefore;

  /// No description provided for @staffMonthAfter.
  ///
  /// In ur, this message translates to:
  /// **'Agla mahina'**
  String get staffMonthAfter;

  /// No description provided for @staffMonthWages.
  ///
  /// In ur, this message translates to:
  /// **'{days} din ki tankhwah'**
  String staffMonthWages(String days);

  /// No description provided for @staffMonthPaid.
  ///
  /// In ur, this message translates to:
  /// **'{number} par di gayi'**
  String staffMonthPaid(String number);

  /// No description provided for @staffPayMonth.
  ///
  /// In ur, this message translates to:
  /// **'{month} ki tankhwah dein'**
  String staffPayMonth(String month);

  /// No description provided for @staffNotMarkedCount.
  ///
  /// In ur, this message translates to:
  /// **'Hazri nahi lagi'**
  String get staffNotMarkedCount;

  /// No description provided for @staffSlips.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah ki slips'**
  String get staffSlips;

  /// No description provided for @staffSlipCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Cancel'**
  String get staffSlipCancelled;

  /// No description provided for @staffAdvanceGiven.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi di'**
  String get staffAdvanceGiven;

  /// No description provided for @staffAdvanceRecovered.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah se kati'**
  String get staffAdvanceRecovered;

  /// No description provided for @staffAdvanceGivenCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi cancel'**
  String get staffAdvanceGivenCancelled;

  /// No description provided for @staffAdvanceRecoveryCancelled.
  ///
  /// In ur, this message translates to:
  /// **'Slip cancel, peshgi phir baqi'**
  String get staffAdvanceRecoveryCancelled;

  /// No description provided for @staffAdvances.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi'**
  String get staffAdvances;

  /// No description provided for @staffAdvanceOwedAfter.
  ///
  /// In ur, this message translates to:
  /// **'Is ke baad baqi: Rs {amount}'**
  String staffAdvanceOwedAfter(String amount);

  /// No description provided for @staffAmountInvalid.
  ///
  /// In ur, this message translates to:
  /// **'Raqam likhein, jaise 2000'**
  String get staffAmountInvalid;

  /// No description provided for @staffAdvanceSaved.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi de di ({number})'**
  String staffAdvanceSaved(String number);

  /// No description provided for @staffAdvanceTitle.
  ///
  /// In ur, this message translates to:
  /// **'{name} ko peshgi'**
  String staffAdvanceTitle(String name);

  /// No description provided for @staffAdvanceAmount.
  ///
  /// In ur, this message translates to:
  /// **'Kitni raqam (Rs)'**
  String get staffAdvanceAmount;

  /// No description provided for @staffPaidFrom.
  ///
  /// In ur, this message translates to:
  /// **'Kahan se di'**
  String get staffPaidFrom;

  /// No description provided for @staffAdvanceHint.
  ///
  /// In ur, this message translates to:
  /// **'Yeh tankhwah se wapas katti hai, har mahine jitni aap chahein.'**
  String get staffAdvanceHint;

  /// No description provided for @staffCorrectReasonNeeded.
  ///
  /// In ur, this message translates to:
  /// **'Likhein slip kyun theek ho rahi hai'**
  String get staffCorrectReasonNeeded;

  /// No description provided for @staffRuleDaily.
  ///
  /// In ur, this message translates to:
  /// **'Dihari Rs {amount}: har din jo aaya, aadha din aadhi'**
  String staffRuleDaily(String amount);

  /// No description provided for @staffRuleCalendar.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} mahana; ek din 1/{days} (mahine ke din)'**
  String staffRuleCalendar(String amount, int days);

  /// No description provided for @staffRuleThirty.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} mahana; ek din 1/30 (30 din ka mahina)'**
  String staffRuleThirty(String amount);

  /// No description provided for @staffSalaryTitle.
  ///
  /// In ur, this message translates to:
  /// **'{name}: {month}'**
  String staffSalaryTitle(String name, String month);

  /// No description provided for @staffCorrectTitle.
  ///
  /// In ur, this message translates to:
  /// **'{number} theek karein'**
  String staffCorrectTitle(String number);

  /// No description provided for @staffOnPayroll.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine {days} din kaam par'**
  String staffOnPayroll(int days);

  /// No description provided for @staffUnmarkedPaid.
  ///
  /// In ur, this message translates to:
  /// **'{count} din hazri nahi lagi: kaam ke din gine gaye'**
  String staffUnmarkedPaid(int count);

  /// No description provided for @staffUnmarkedUnpaid.
  ///
  /// In ur, this message translates to:
  /// **'{count} din hazri nahi lagi: dihari mein nahi gine gaye'**
  String staffUnmarkedUnpaid(int count);

  /// No description provided for @staffBasePay.
  ///
  /// In ur, this message translates to:
  /// **'{days} din ki tankhwah'**
  String staffBasePay(String days);

  /// No description provided for @staffLines.
  ///
  /// In ur, this message translates to:
  /// **'Bonus, overtime aur katoti'**
  String get staffLines;

  /// No description provided for @staffLineRemove.
  ///
  /// In ur, this message translates to:
  /// **'Hatayein'**
  String get staffLineRemove;

  /// No description provided for @staffLineLabel.
  ///
  /// In ur, this message translates to:
  /// **'Kis cheez ka (jaise Eid bonus)'**
  String get staffLineLabel;

  /// No description provided for @staffLineAmount.
  ///
  /// In ur, this message translates to:
  /// **'Raqam (Rs)'**
  String get staffLineAmount;

  /// No description provided for @staffLineAdd.
  ///
  /// In ur, this message translates to:
  /// **'Shamil karein'**
  String get staffLineAdd;

  /// No description provided for @staffLineBonus.
  ///
  /// In ur, this message translates to:
  /// **'Bonus'**
  String get staffLineBonus;

  /// No description provided for @staffLineOvertime.
  ///
  /// In ur, this message translates to:
  /// **'Overtime'**
  String get staffLineOvertime;

  /// No description provided for @staffLineDeduction.
  ///
  /// In ur, this message translates to:
  /// **'Katoti'**
  String get staffLineDeduction;

  /// No description provided for @staffAdvanceOwedNow.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi baqi: Rs {amount}'**
  String staffAdvanceOwedNow(String amount);

  /// No description provided for @staffRecover.
  ///
  /// In ur, this message translates to:
  /// **'Is mahine kitni katein (Rs)'**
  String get staffRecover;

  /// No description provided for @staffGross.
  ///
  /// In ur, this message translates to:
  /// **'Bonus samet tankhwah'**
  String get staffGross;

  /// No description provided for @staffDeductions.
  ///
  /// In ur, this message translates to:
  /// **'Katoti'**
  String get staffDeductions;

  /// No description provided for @staffRecoveredShort.
  ///
  /// In ur, this message translates to:
  /// **'Peshgi kati'**
  String get staffRecoveredShort;

  /// No description provided for @staffInHand.
  ///
  /// In ur, this message translates to:
  /// **'Haath mein'**
  String get staffInHand;

  /// No description provided for @staffCorrectReason.
  ///
  /// In ur, this message translates to:
  /// **'Kyun theek ho rahi hai?'**
  String get staffCorrectReason;

  /// No description provided for @staffPaySave.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah dein'**
  String get staffPaySave;

  /// No description provided for @staffCorrectSave.
  ///
  /// In ur, this message translates to:
  /// **'Theek karke dein'**
  String get staffCorrectSave;

  /// No description provided for @staffSlipMessage.
  ///
  /// In ur, this message translates to:
  /// **'{shop}\n{month} ki tankhwah: {name}\nDin: {days}\nTankhwah: Rs {gross}\nKatoti aur peshgi: Rs {cuts}\nHaath mein: Rs {net}\nSlip {slip}'**
  String staffSlipMessage(
    String shop,
    String name,
    String month,
    String days,
    String gross,
    String cuts,
    String net,
    String slip,
  );

  /// No description provided for @staffSlipCancelTitle.
  ///
  /// In ur, this message translates to:
  /// **'Yeh slip cancel karein'**
  String get staffSlipCancelTitle;

  /// No description provided for @staffSlipCancelDone.
  ///
  /// In ur, this message translates to:
  /// **'Slip cancel ho gayi ({number})'**
  String staffSlipCancelDone(String number);

  /// No description provided for @staffSlipPdf.
  ///
  /// In ur, this message translates to:
  /// **'Slip (PDF)'**
  String get staffSlipPdf;

  /// No description provided for @staffSlipCancelledWhy.
  ///
  /// In ur, this message translates to:
  /// **'Cancel: {reason}'**
  String staffSlipCancelledWhy(String reason);

  /// No description provided for @staffSlipReplacedBy.
  ///
  /// In ur, this message translates to:
  /// **'{number} se theek ki gayi'**
  String staffSlipReplacedBy(String number);

  /// No description provided for @staffSlipDays.
  ///
  /// In ur, this message translates to:
  /// **'{employed} mein se {days} din ki tankhwah'**
  String staffSlipDays(String days, int employed);

  /// No description provided for @staffSlipPaidOn.
  ///
  /// In ur, this message translates to:
  /// **'{date} ko {from} se, {name} ne di'**
  String staffSlipPaidOn(String date, String from, String name);

  /// No description provided for @staffSlipWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp par bhejein'**
  String get staffSlipWhatsApp;

  /// No description provided for @staffSlipCorrect.
  ///
  /// In ur, this message translates to:
  /// **'Yeh slip theek karein'**
  String get staffSlipCorrect;

  /// No description provided for @staffDayRuleHint.
  ///
  /// In ur, this message translates to:
  /// **'Mahana tankhwah mein ek din kaise gina jaye, ghair haazri ki katoti ke liye.'**
  String get staffDayRuleHint;

  /// No description provided for @staffDayRuleThirty.
  ///
  /// In ur, this message translates to:
  /// **'30 din ka mahina'**
  String get staffDayRuleThirty;

  /// No description provided for @staffDayRuleThirtyHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mahine ek din tankhwah ka 30wan hissa. Poora mahina, poori tankhwah.'**
  String get staffDayRuleThirtyHint;

  /// No description provided for @staffDayRuleCalendar.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ke asal din'**
  String get staffDayRuleCalendar;

  /// No description provided for @staffDayRuleCalendarHint.
  ///
  /// In ur, this message translates to:
  /// **'Ek din mahine ke apne dinon ka hissa: February mein 1/28, October mein 1/31.'**
  String get staffDayRuleCalendarHint;

  /// No description provided for @staffCashierMarks.
  ///
  /// In ur, this message translates to:
  /// **'Cashier hazri laga sakta hai'**
  String get staffCashierMarks;

  /// No description provided for @staffCashierMarksHint.
  ///
  /// In ur, this message translates to:
  /// **'Woh sirf naam aur hazri dekhega, kisi ki tankhwah nahi.'**
  String get staffCashierMarksHint;

  /// No description provided for @staffWhoSeesPay.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah, peshgi aur slips sirf owner, manager aur accountant dekh sakte hain.'**
  String get staffWhoSeesPay;

  /// No description provided for @staffRulesOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Yeh usool sirf owner badal sakta hai.'**
  String get staffRulesOwnerOnly;

  /// No description provided for @reportGroupStaff.
  ///
  /// In ur, this message translates to:
  /// **'Staff'**
  String get reportGroupStaff;

  /// No description provided for @reportStaffAttendance.
  ///
  /// In ur, this message translates to:
  /// **'Hazri ka khulasa'**
  String get reportStaffAttendance;

  /// No description provided for @reportStaffAttendanceHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mulazim: haazir, der se, aadha din, chutti aur ghair haazir'**
  String get reportStaffAttendanceHint;

  /// No description provided for @reportSalaryRegister.
  ///
  /// In ur, this message translates to:
  /// **'Tankhwah register'**
  String get reportSalaryRegister;

  /// No description provided for @reportSalaryRegisterHint.
  ///
  /// In ur, this message translates to:
  /// **'Har slip: tankhwah, katoti, peshgi kati, di gayi'**
  String get reportSalaryRegisterHint;

  /// No description provided for @reportStaffAdvances.
  ///
  /// In ur, this message translates to:
  /// **'Baqi peshgi'**
  String get reportStaffAdvances;

  /// No description provided for @reportStaffAdvancesHint.
  ///
  /// In ur, this message translates to:
  /// **'Har mulazim ki kitni peshgi abhi baqi hai'**
  String get reportStaffAdvancesHint;

  /// No description provided for @settingsLoyalty.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty points aur munafa'**
  String get settingsLoyalty;

  /// No description provided for @loyaltyTitle.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty points'**
  String get loyaltyTitle;

  /// No description provided for @loyaltyIntro.
  ///
  /// In ur, this message translates to:
  /// **'Gahak har bill par points kamata hai — sirf jo ada kiya us par, udhaar par tab jab ada ho — aur agle bill par discount ke taur par istemal karta hai.'**
  String get loyaltyIntro;

  /// No description provided for @loyaltyOn.
  ///
  /// In ur, this message translates to:
  /// **'Points dein'**
  String get loyaltyOn;

  /// No description provided for @loyaltyEarnPoints.
  ///
  /// In ur, this message translates to:
  /// **'Points'**
  String get loyaltyEarnPoints;

  /// No description provided for @loyaltyEarnPer.
  ///
  /// In ur, this message translates to:
  /// **'Har itne Rs par'**
  String get loyaltyEarnPer;

  /// No description provided for @loyaltyRedeemPoints.
  ///
  /// In ur, this message translates to:
  /// **'Itne points'**
  String get loyaltyRedeemPoints;

  /// No description provided for @loyaltyRedeemValue.
  ///
  /// In ur, this message translates to:
  /// **'Itne Rs ke barabar'**
  String get loyaltyRedeemValue;

  /// No description provided for @loyaltyExpiry.
  ///
  /// In ur, this message translates to:
  /// **'Itne mahine baad khatam (0 = kabhi nahi)'**
  String get loyaltyExpiry;

  /// No description provided for @loyaltyCap.
  ///
  /// In ur, this message translates to:
  /// **'Bill ka zyada se zyada % points se'**
  String get loyaltyCap;

  /// No description provided for @loyaltyRuleNow.
  ///
  /// In ur, this message translates to:
  /// **'Rs {per} par {earn} points · {pts} points = Rs {worth} · {back} wapas'**
  String loyaltyRuleNow(
    String earn,
    String per,
    String pts,
    String worth,
    String back,
  );

  /// No description provided for @loyaltyRuleOff.
  ///
  /// In ur, this message translates to:
  /// **'Abhi points nahi diye ja rahe.'**
  String get loyaltyRuleOff;

  /// No description provided for @loyaltySaved.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty ka qaida save — agle bill se'**
  String get loyaltySaved;

  /// No description provided for @loyaltyOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty ka qaida sirf maalik badal sakta hai.'**
  String get loyaltyOwnerOnly;

  /// No description provided for @loyaltyBooksNote.
  ///
  /// In ur, this message translates to:
  /// **'Points khata ke saath ek wada hain. Istemal hone par us bill par discount ban kar kitab mein jate hain.'**
  String get loyaltyBooksNote;

  /// No description provided for @loyaltyProblemFigures.
  ///
  /// In ur, this message translates to:
  /// **'Har figure likhein, sifar se zyada.'**
  String get loyaltyProblemFigures;

  /// No description provided for @loyaltyProblemTooGenerous.
  ///
  /// In ur, this message translates to:
  /// **'Ye points kamaye gaye paison ka aadhe se zyada wapas dete hain — figures check karein.'**
  String get loyaltyProblemTooGenerous;

  /// No description provided for @loyaltyProblemCap.
  ///
  /// In ur, this message translates to:
  /// **'Bill ka hissa 1% se 100% tak.'**
  String get loyaltyProblemCap;

  /// No description provided for @loyaltyProblemExpiry.
  ///
  /// In ur, this message translates to:
  /// **'Mahine 0 se 120 tak.'**
  String get loyaltyProblemExpiry;

  /// No description provided for @loyaltyProblemNotEnough.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ke paas itne points nahi.'**
  String get loyaltyProblemNotEnough;

  /// No description provided for @loyaltyProblemOverCap.
  ///
  /// In ur, this message translates to:
  /// **'Is bill ka itna hissa points se nahi.'**
  String get loyaltyProblemOverCap;

  /// No description provided for @loyaltyProblemOff.
  ///
  /// In ur, this message translates to:
  /// **'Points band hain.'**
  String get loyaltyProblemOff;

  /// No description provided for @loyaltyProblemNoCustomer.
  ///
  /// In ur, this message translates to:
  /// **'Points sirf apne gahak ke bill par lagte hain.'**
  String get loyaltyProblemNoCustomer;

  /// No description provided for @loyaltyProblemMismatch.
  ///
  /// In ur, this message translates to:
  /// **'Points ki qeemat badal gayi — hata kar dobara lagayein.'**
  String get loyaltyProblemMismatch;

  /// No description provided for @loyaltyHeld.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty: {points} points (Rs {worth})'**
  String loyaltyHeld(String points, String worth);

  /// No description provided for @loyaltyUse.
  ///
  /// In ur, this message translates to:
  /// **'Points istemal karein'**
  String get loyaltyUse;

  /// No description provided for @loyaltyHowMany.
  ///
  /// In ur, this message translates to:
  /// **'Kitne points'**
  String get loyaltyHowMany;

  /// No description provided for @loyaltyAtMost.
  ///
  /// In ur, this message translates to:
  /// **'Is bill par zyada se zyada {max}'**
  String loyaltyAtMost(String max);

  /// No description provided for @loyaltyApply.
  ///
  /// In ur, this message translates to:
  /// **'Points lagayein'**
  String get loyaltyApply;

  /// No description provided for @loyaltyApplied.
  ///
  /// In ur, this message translates to:
  /// **'{points} points istemal: Rs {worth} kam'**
  String loyaltyApplied(String points, String worth);

  /// No description provided for @loyaltyTakeOff.
  ///
  /// In ur, this message translates to:
  /// **'Points hatayein'**
  String get loyaltyTakeOff;

  /// No description provided for @loyaltyWillEarn.
  ///
  /// In ur, this message translates to:
  /// **'Is bill par {points} points milenge'**
  String loyaltyWillEarn(String points);

  /// No description provided for @loyaltyWillEarnWhenPaid.
  ///
  /// In ur, this message translates to:
  /// **'Is bill par {points} points milenge jab ada hoga'**
  String loyaltyWillEarnWhenPaid(String points);

  /// No description provided for @khataPoints.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty points: {points} (Rs {worth})'**
  String khataPoints(String points, String worth);

  /// No description provided for @khataPointsExpiring.
  ///
  /// In ur, this message translates to:
  /// **'{points} points {date} ko khatam honge'**
  String khataPointsExpiring(String points, String date);

  /// No description provided for @khataPointsSummary.
  ///
  /// In ur, this message translates to:
  /// **'Mile {earned} · istemal {redeemed} · khatam {expired}'**
  String khataPointsSummary(String earned, String redeemed, String expired);

  /// No description provided for @partyPricesTitle.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ke apne rate'**
  String get partyPricesTitle;

  /// No description provided for @partyPricesCount.
  ///
  /// In ur, this message translates to:
  /// **'Apne rate: {count} cheezen'**
  String partyPricesCount(int count);

  /// No description provided for @partyPricesNone.
  ///
  /// In ur, this message translates to:
  /// **'Abhi koi apna rate nahi'**
  String get partyPricesNone;

  /// No description provided for @partyPricesIntro.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ke saath har cheez ka tay shuda rate. Counter par yehi lagta hai — thok, VIP aur slab se pehle; cashier ka likha rate is se bhi pehle, aur is par unka mustaqil discount dobara nahi katta.'**
  String get partyPricesIntro;

  /// No description provided for @partyPricesAdd.
  ///
  /// In ur, this message translates to:
  /// **'Cheez ka rate rakhein'**
  String get partyPricesAdd;

  /// No description provided for @partyPriceRate.
  ///
  /// In ur, this message translates to:
  /// **'Rate (fi {unit})'**
  String partyPriceRate(String unit);

  /// No description provided for @partyPriceRemove.
  ///
  /// In ur, this message translates to:
  /// **'Rate hatayein'**
  String get partyPriceRemove;

  /// No description provided for @partyPriceSaved.
  ///
  /// In ur, this message translates to:
  /// **'Rate rakh diya'**
  String get partyPriceSaved;

  /// No description provided for @partyPricesOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ka rate sirf maalik, manager ya munshi rakh sakte hain.'**
  String get partyPricesOwnerOnly;

  /// No description provided for @lineOwnRate.
  ///
  /// In ur, this message translates to:
  /// **'{name} ka rate'**
  String lineOwnRate(String name);

  /// No description provided for @lineKeepRate.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ke liye yehi rate rakhein'**
  String get lineKeepRate;

  /// No description provided for @lineRateKept.
  ///
  /// In ur, this message translates to:
  /// **'{name} ke liye rate rakh diya'**
  String lineRateKept(String name);

  /// No description provided for @lineRateNotCarried.
  ///
  /// In ur, this message translates to:
  /// **'Ye rate cheez ki apni unit mein theek nahi baithta'**
  String get lineRateNotCarried;

  /// No description provided for @marginBill.
  ///
  /// In ur, this message translates to:
  /// **'Munafa Rs {amount} ({pct})'**
  String marginBill(String amount, String pct);

  /// No description provided for @marginBelowCost.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat se kam'**
  String get marginBelowCost;

  /// No description provided for @marginLine.
  ///
  /// In ur, this message translates to:
  /// **'Is cheez par munafa Rs {amount} ({pct})'**
  String marginLine(String amount, String pct);

  /// No description provided for @marginLineLoss.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat se kam: Rs {amount} ka nuqsan'**
  String marginLineLoss(String amount);

  /// No description provided for @marginHeader.
  ///
  /// In ur, this message translates to:
  /// **'Bill banate waqt munafa'**
  String get marginHeader;

  /// No description provided for @marginSwitch.
  ///
  /// In ur, this message translates to:
  /// **'Counter par bill ka munafa dikhayein'**
  String get marginSwitch;

  /// No description provided for @marginSwitchHint.
  ///
  /// In ur, this message translates to:
  /// **'Sirf maalik, manager aur munshi ko nazar aata hai; cashier ko kabhi nahi.'**
  String get marginSwitchHint;

  /// No description provided for @reportLoyalty.
  ///
  /// In ur, this message translates to:
  /// **'Loyalty points'**
  String get reportLoyalty;

  /// No description provided for @reportLoyaltyHint.
  ///
  /// In ur, this message translates to:
  /// **'Har gahak ke points: mile, istemal, khatam aur baqi'**
  String get reportLoyaltyHint;

  /// No description provided for @partyPriceEach.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} fi {unit}'**
  String partyPriceEach(String amount, String unit);

  /// No description provided for @reportRatioAnalysis.
  ///
  /// In ur, this message translates to:
  /// **'Nisbatain (ratio analysis)'**
  String get reportRatioAnalysis;

  /// No description provided for @reportRatioAnalysisHint.
  ///
  /// In ur, this message translates to:
  /// **'Nafa %, maal kitni baar bika, udhaar aur dene ke din, current ratio, aur kharch ke muqable mein paisa — pichle arse ke saath'**
  String get reportRatioAnalysisHint;

  /// No description provided for @reportNeedsAttention.
  ///
  /// In ur, this message translates to:
  /// **'Dhyan dein'**
  String get reportNeedsAttention;

  /// No description provided for @reportNeedsAttentionHint.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki har gadbad: minus stock ya paisa, purana udhaar, bank le jaane wale cheque, cancel bill, laagat se kam bikri, expire maal, FBR'**
  String get reportNeedsAttentionHint;

  /// No description provided for @reportAbc.
  ///
  /// In ur, this message translates to:
  /// **'ABC darja-bandi'**
  String get reportAbc;

  /// No description provided for @reportAbcHint.
  ///
  /// In ur, this message translates to:
  /// **'Kaun si chand cheezen sab se zyada bikri laati hain: A, B aur C darje, unke hisse ke saath'**
  String get reportAbcHint;

  /// No description provided for @reportFilterValuation.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat kis par'**
  String get reportFilterValuation;

  /// No description provided for @reportValuationCost.
  ///
  /// In ur, this message translates to:
  /// **'Laagat par (khaata)'**
  String get reportValuationCost;

  /// No description provided for @reportValuationCostTax.
  ///
  /// In ur, this message translates to:
  /// **'Laagat + tax'**
  String get reportValuationCostTax;

  /// No description provided for @reportValuationSale.
  ///
  /// In ur, this message translates to:
  /// **'Bechne ki qeemat'**
  String get reportValuationSale;

  /// No description provided for @reportValuationSaleTax.
  ///
  /// In ur, this message translates to:
  /// **'Bechne ki qeemat + tax'**
  String get reportValuationSaleTax;

  /// No description provided for @reportFilterAbcBasis.
  ///
  /// In ur, this message translates to:
  /// **'Darja kis se'**
  String get reportFilterAbcBasis;

  /// No description provided for @reportAbcBySales.
  ///
  /// In ur, this message translates to:
  /// **'Bikri'**
  String get reportAbcBySales;

  /// No description provided for @reportAbcByProfit.
  ///
  /// In ur, this message translates to:
  /// **'Nafa'**
  String get reportAbcByProfit;

  /// No description provided for @reportFilterAbcBands.
  ///
  /// In ur, this message translates to:
  /// **'Darjon ki had'**
  String get reportFilterAbcBands;

  /// No description provided for @reportFilterAbcBandsValue.
  ///
  /// In ur, this message translates to:
  /// **'A {a}% · B {b}%'**
  String reportFilterAbcBandsValue(int a, int b);

  /// No description provided for @reportAbcLineA.
  ///
  /// In ur, this message translates to:
  /// **'A darja kahan khatam (kul ka %)'**
  String get reportAbcLineA;

  /// No description provided for @reportAbcLineB.
  ///
  /// In ur, this message translates to:
  /// **'B darja kahan khatam (kul ka %)'**
  String get reportAbcLineB;

  /// No description provided for @reportAbcLinesWrong.
  ///
  /// In ur, this message translates to:
  /// **'A, B se kam ho, dono 1 se 100 tak'**
  String get reportAbcLinesWrong;

  /// No description provided for @reportFilterLateDays.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar kitne din late'**
  String get reportFilterLateDays;

  /// No description provided for @reportColumns.
  ///
  /// In ur, this message translates to:
  /// **'Columns'**
  String get reportColumns;

  /// No description provided for @reportColumnsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Columns dikhayein aur tarteeb dein'**
  String get reportColumnsTitle;

  /// No description provided for @reportColumnsHint.
  ///
  /// In ur, this message translates to:
  /// **'Tick hata kar column chhupayein, teer se upar neeche karein. Is phone par is report ke liye yaad rahega, aur saved view mein bhi.'**
  String get reportColumnsHint;

  /// No description provided for @reportColumnUp.
  ///
  /// In ur, this message translates to:
  /// **'{name} upar'**
  String reportColumnUp(String name);

  /// No description provided for @reportColumnDown.
  ///
  /// In ur, this message translates to:
  /// **'{name} neeche'**
  String reportColumnDown(String name);

  /// No description provided for @reportColumnsReset.
  ///
  /// In ur, this message translates to:
  /// **'Sab columns, asal tarteeb mein'**
  String get reportColumnsReset;

  /// No description provided for @reportColumnFilter.
  ///
  /// In ur, this message translates to:
  /// **'Column par filter'**
  String get reportColumnFilter;

  /// No description provided for @reportColumnFilterPick.
  ///
  /// In ur, this message translates to:
  /// **'Kaun sa column?'**
  String get reportColumnFilterPick;

  /// No description provided for @reportColumnContains.
  ///
  /// In ur, this message translates to:
  /// **'Is mein ho'**
  String get reportColumnContains;

  /// No description provided for @reportColumnAtLeast.
  ///
  /// In ur, this message translates to:
  /// **'Kam se kam'**
  String get reportColumnAtLeast;

  /// No description provided for @reportColumnAtMost.
  ///
  /// In ur, this message translates to:
  /// **'Zyada se zyada'**
  String get reportColumnAtMost;

  /// No description provided for @reportColumnFilterValue.
  ///
  /// In ur, this message translates to:
  /// **'Qeemat'**
  String get reportColumnFilterValue;

  /// No description provided for @reportColumnFilterApply.
  ///
  /// In ur, this message translates to:
  /// **'Lagayein'**
  String get reportColumnFilterApply;

  /// No description provided for @reportColumnFilterBad.
  ///
  /// In ur, this message translates to:
  /// **'Number likhein'**
  String get reportColumnFilterBad;

  /// No description provided for @reportColumnFilterContainsChip.
  ///
  /// In ur, this message translates to:
  /// **'{column}: \"{text}\"'**
  String reportColumnFilterContainsChip(String column, String text);

  /// No description provided for @reportColumnFilterAtLeastChip.
  ///
  /// In ur, this message translates to:
  /// **'{column} ≥ {value}'**
  String reportColumnFilterAtLeastChip(String column, String value);

  /// No description provided for @reportColumnFilterAtMostChip.
  ///
  /// In ur, this message translates to:
  /// **'{column} ≤ {value}'**
  String reportColumnFilterAtMostChip(String column, String value);

  /// No description provided for @reportAgeingBuckets.
  ///
  /// In ur, this message translates to:
  /// **'Hisse: {label} din'**
  String reportAgeingBuckets(String label);

  /// No description provided for @reportAgeingTitle.
  ///
  /// In ur, this message translates to:
  /// **'Umar ke hisse'**
  String get reportAgeingTitle;

  /// No description provided for @reportAgeingHint.
  ///
  /// In ur, this message translates to:
  /// **'Har hissa kitne din par khatam ho, jaise 15, 30, 60. Udhaar kitna purana, suppliers ka baqaya aur adaigi ki tareekh wala udhaar inhi se banenge, is phone par.'**
  String get reportAgeingHint;

  /// No description provided for @reportAgeingField.
  ///
  /// In ur, this message translates to:
  /// **'Din'**
  String get reportAgeingField;

  /// No description provided for @reportAgeingBad.
  ///
  /// In ur, this message translates to:
  /// **'Paanch tak number, har agla pichle se bara'**
  String get reportAgeingBad;

  /// No description provided for @reportAgeingReset.
  ///
  /// In ur, this message translates to:
  /// **'Wapas 30, 60, 90'**
  String get reportAgeingReset;

  /// No description provided for @reportChartThisPeriod.
  ///
  /// In ur, this message translates to:
  /// **'Yeh arsa'**
  String get reportChartThisPeriod;

  /// No description provided for @reportChartPeriodBefore.
  ///
  /// In ur, this message translates to:
  /// **'Pichla arsa: {amount}'**
  String reportChartPeriodBefore(String amount);

  /// No description provided for @reportChartPickedBefore.
  ///
  /// In ur, this message translates to:
  /// **'{label}: {amount} · pehle {before}'**
  String reportChartPickedBefore(String label, String amount, String before);

  /// No description provided for @receiptOfferTitle.
  ///
  /// In ur, this message translates to:
  /// **'{name} ko raseed bhejein?'**
  String receiptOfferTitle(String name);

  /// No description provided for @receiptOfferWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp par raseed'**
  String get receiptOfferWhatsApp;

  /// No description provided for @receiptOfferPdf.
  ///
  /// In ur, this message translates to:
  /// **'Bill ki PDF'**
  String get receiptOfferPdf;

  /// No description provided for @receiptOfferPicture.
  ///
  /// In ur, this message translates to:
  /// **'Bill ki tasveer'**
  String get receiptOfferPicture;

  /// No description provided for @receiptOfferLater.
  ///
  /// In ur, this message translates to:
  /// **'Abhi nahi'**
  String get receiptOfferLater;

  /// No description provided for @receiptOfferFromNow.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ko aage se'**
  String get receiptOfferFromNow;

  /// No description provided for @receiptOfferAsk.
  ///
  /// In ur, this message translates to:
  /// **'Har dafa poochhein'**
  String get receiptOfferAsk;

  /// No description provided for @receiptOfferAuto.
  ///
  /// In ur, this message translates to:
  /// **'Khud bhejein'**
  String get receiptOfferAuto;

  /// No description provided for @receiptOfferNever.
  ///
  /// In ur, this message translates to:
  /// **'Kabhi nahi'**
  String get receiptOfferNever;

  /// No description provided for @receiptOfferNote.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp aap ke phone par isi gahak ki chat par khulega, message likha hua. Send aap khud dabayenge — app khud kabhi kuch nahi bhejta.'**
  String get receiptOfferNote;

  /// No description provided for @receiptOfferNoWhatsApp.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp nahi khula'**
  String get receiptOfferNoWhatsApp;

  /// No description provided for @receiptOfferKept.
  ///
  /// In ur, this message translates to:
  /// **'{name}: {choice}'**
  String receiptOfferKept(String name, String choice);

  /// No description provided for @settingsReceiptOffer.
  ///
  /// In ur, this message translates to:
  /// **'Gahak ko raseed'**
  String get settingsReceiptOffer;

  /// No description provided for @receiptOfferSettingsIntro.
  ///
  /// In ur, this message translates to:
  /// **'Bill, wusooli, maal wapsi aur supplier ki adaigi ke foran baad us ki zabaan mein WhatsApp message: kya hua aur ab hisaab kitna hai. Sirf jin ka mobile number hai; aam gahak ko kabhi nahi.'**
  String get receiptOfferSettingsIntro;

  /// No description provided for @receiptOfferDefaultTitle.
  ///
  /// In ur, this message translates to:
  /// **'Jin ka alag nahi chuna'**
  String get receiptOfferDefaultTitle;

  /// No description provided for @receiptOfferAskHint.
  ///
  /// In ur, this message translates to:
  /// **'Har dafa poochha jayega: WhatsApp, PDF ya abhi nahi'**
  String get receiptOfferAskHint;

  /// No description provided for @receiptOfferAutoHint.
  ///
  /// In ur, this message translates to:
  /// **'WhatsApp khud khulega, message likha hua; Send aap dabayenge'**
  String get receiptOfferAutoHint;

  /// No description provided for @receiptOfferNeverHint.
  ///
  /// In ur, this message translates to:
  /// **'Kuch nahi poochha jayega'**
  String get receiptOfferNeverHint;

  /// No description provided for @receiptOfferPerParty.
  ///
  /// In ur, this message translates to:
  /// **'Har gahak ka alag: gahak ke form mein, ya raseed bhejte waqt'**
  String get receiptOfferPerParty;

  /// No description provided for @receiptOfferSaved.
  ///
  /// In ur, this message translates to:
  /// **'Mehfooz ho gaya'**
  String get receiptOfferSaved;

  /// No description provided for @partyReceiptOffer.
  ///
  /// In ur, this message translates to:
  /// **'Paisay ki raseed WhatsApp par'**
  String get partyReceiptOffer;

  /// No description provided for @partyReceiptOfferShop.
  ///
  /// In ur, this message translates to:
  /// **'Abhi dukan ki setting chal rahi hai'**
  String get partyReceiptOfferShop;

  /// No description provided for @billThemeLandscape.
  ///
  /// In ur, this message translates to:
  /// **'Landscape (wholesale)'**
  String get billThemeLandscape;

  /// No description provided for @billThemeLandscapeHint.
  ///
  /// In ur, this message translates to:
  /// **'Safha leta hua: HS code, unit, discount aur har line ka tax — registered dukan ke liye poora sales tax invoice'**
  String get billThemeLandscapeHint;

  /// No description provided for @billThemeRuled.
  ///
  /// In ur, this message translates to:
  /// **'Bill book'**
  String get billThemeRuled;

  /// No description provided for @billThemeRuledHint.
  ///
  /// In ur, this message translates to:
  /// **'Stationer ki bill book jaisa: border, M/s ki line, khaane, dastkhat'**
  String get billThemeRuledHint;

  /// No description provided for @billThemeElegant.
  ///
  /// In ur, this message translates to:
  /// **'Nafees'**
  String get billThemeElegant;

  /// No description provided for @billThemeElegantHint.
  ///
  /// In ur, this message translates to:
  /// **'Serif likhai aur baareek lakeerein, dafatir aur showroom ke liye'**
  String get billThemeElegantHint;

  /// No description provided for @billThemeMinimal.
  ///
  /// In ur, this message translates to:
  /// **'Halka'**
  String get billThemeMinimal;

  /// No description provided for @billThemeMinimalHint.
  ///
  /// In ur, this message translates to:
  /// **'Na rang ki patti na dabbe: naam, cheezen, total'**
  String get billThemeMinimalHint;

  /// No description provided for @billDesignNotTaxInvoice.
  ///
  /// In ur, this message translates to:
  /// **'Yeh design sales tax invoice ki har tafseel nahi chhapta. Registered dukan ke bill ke liye Sales tax invoice ya Landscape chunein.'**
  String get billDesignNotTaxInvoice;

  /// No description provided for @billDesignSlip.
  ///
  /// In ur, this message translates to:
  /// **'Thermal slip ka andaaz'**
  String get billDesignSlip;

  /// No description provided for @billSlipStandard.
  ///
  /// In ur, this message translates to:
  /// **'Aam'**
  String get billSlipStandard;

  /// No description provided for @billSlipStandardHint.
  ///
  /// In ur, this message translates to:
  /// **'Jaisi hamesha chhapti hai'**
  String get billSlipStandardHint;

  /// No description provided for @billSlipCompact.
  ///
  /// In ur, this message translates to:
  /// **'Compact'**
  String get billSlipCompact;

  /// No description provided for @billSlipCompactHint.
  ///
  /// In ur, this message translates to:
  /// **'Kam kaghaz: har cheez ek line mein jahan aa sake, faltu lakeerein nahi'**
  String get billSlipCompactHint;

  /// No description provided for @billSlipBigTotal.
  ///
  /// In ur, this message translates to:
  /// **'Bara total'**
  String get billSlipBigTotal;

  /// No description provided for @billSlipBigTotalHint.
  ///
  /// In ur, this message translates to:
  /// **'Total aur baqaya dugne size mein, buzurg gahakon ke liye'**
  String get billSlipBigTotalHint;

  /// No description provided for @billDesignPerPaper.
  ///
  /// In ur, this message translates to:
  /// **'Har kaghaz ka design'**
  String get billDesignPerPaper;

  /// No description provided for @billDesignPerPaperHint.
  ///
  /// In ur, this message translates to:
  /// **'Quotation, challan aur purchase order ka alag design; warna bill wala. Paisay ki raseed ka apna ek design hai.'**
  String get billDesignPerPaperHint;

  /// No description provided for @billDesignSameAsBill.
  ///
  /// In ur, this message translates to:
  /// **'Bill jaisa'**
  String get billDesignSameAsBill;

  /// No description provided for @billDesignDocQuotation.
  ///
  /// In ur, this message translates to:
  /// **'Quotation ka design'**
  String get billDesignDocQuotation;

  /// No description provided for @billDesignDocChallan.
  ///
  /// In ur, this message translates to:
  /// **'Delivery challan ka design'**
  String get billDesignDocChallan;

  /// No description provided for @billDesignDocOrder.
  ///
  /// In ur, this message translates to:
  /// **'Purchase order ka design'**
  String get billDesignDocOrder;

  /// No description provided for @controlSettingsTitle.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar, din band aur counter ke qaide'**
  String get controlSettingsTitle;

  /// No description provided for @creditRulesHeader.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ke qaide'**
  String get creditRulesHeader;

  /// No description provided for @creditRulesIntro.
  ///
  /// In ur, this message translates to:
  /// **'Jab gahak kisi qaide se aage jaye to payment sheet kya kare. Khabardar: bata deti hai, cashier aage barh sakta hai. Rok: udhaar nahi hota (cash phir bhi le sakte hain), jab tak malik PIN aur wajah na de.'**
  String get creditRulesIntro;

  /// No description provided for @creditModeOff.
  ///
  /// In ur, this message translates to:
  /// **'Band'**
  String get creditModeOff;

  /// No description provided for @creditModeWarn.
  ///
  /// In ur, this message translates to:
  /// **'Khabardar'**
  String get creditModeWarn;

  /// No description provided for @creditModeBlock.
  ///
  /// In ur, this message translates to:
  /// **'Rok'**
  String get creditModeBlock;

  /// No description provided for @creditModeShop.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ka qaida'**
  String get creditModeShop;

  /// No description provided for @creditLimitRule.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ki hadd se ziyada'**
  String get creditLimitRule;

  /// No description provided for @creditBillsRule.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar par ziyada se ziyada bill'**
  String get creditBillsRule;

  /// No description provided for @creditDaysRule.
  ///
  /// In ur, this message translates to:
  /// **'Sab se purana baqi bill, din'**
  String get creditDaysRule;

  /// No description provided for @creditBounceRule.
  ///
  /// In ur, this message translates to:
  /// **'Cheque bounce ke baad, jab tak ada na ho'**
  String get creditBounceRule;

  /// No description provided for @creditEmptyHint.
  ///
  /// In ur, this message translates to:
  /// **'Khali: yeh qaida nahi'**
  String get creditEmptyHint;

  /// No description provided for @creditSaved.
  ///
  /// In ur, this message translates to:
  /// **'Udhaar ke qaide save ho gaye'**
  String get creditSaved;

  /// No description provided for @creditOwnerOnly.
  ///
  /// In ur, this message translates to:
  /// **'Yeh qaide sirf malik badal sakta hai.'**
  String get creditOwnerOnly;

  /// No description provided for @creditFiguresBad.
  ///
  /// In ur, this message translates to:
  /// **'Poore number likhein, ya khana khali chhor dein.'**
  String get creditFiguresBad;

  /// No description provided for @partyCreditShopRules.
  ///
  /// In ur, this message translates to:
  /// **'Dukaan ke qaide'**
  String get partyCreditShopRules;

  /// No description provided for @partyCreditOwnRules.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ke apne qaide'**
  String get partyCreditOwnRules;

  /// No description provided for @partyCreditTemp.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} {date} tak'**
  String partyCreditTemp(String amount, String date);

  /// No description provided for @partyCreditTempLapsed.
  ///
  /// In ur, this message translates to:
  /// **'Waqti hadd Rs {amount} {date} ke baad khatam'**
  String partyCreditTempLapsed(String amount, String date);

  /// No description provided for @partyCreditTempHeader.
  ///
  /// In ur, this message translates to:
  /// **'Waqti hadd'**
  String get partyCreditTempHeader;

  /// No description provided for @partyCreditTempHint.
  ///
  /// In ur, this message translates to:
  /// **'Chuni hui tareekh tak credit limit ki jagah, phir khud khatam ho jati hai.'**
  String get partyCreditTempHint;

  /// No description provided for @partyCreditTempAmount.
  ///
  /// In ur, this message translates to:
  /// **'Waqti hadd, Rs'**
  String get partyCreditTempAmount;

  /// No description provided for @partyCreditTempPick.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri din: {date}'**
  String partyCreditTempPick(String date);

  /// No description provided for @partyCreditTempNone.
  ///
  /// In ur, this message translates to:
  /// **'Aakhri din chunein'**
  String get partyCreditTempNone;

  /// No description provided for @partyCreditTempClear.
  ///
  /// In ur, this message translates to:
  /// **'Hata dein'**
  String get partyCreditTempClear;

  /// No description provided for @partyCreditStanding.
  ///
  /// In ur, this message translates to:
  /// **'Rs {amount} baqi, {bills} bill; sab se purana {days} din ka'**
  String partyCreditStanding(String amount, int bills, int days);

  /// No description provided for @partyCreditClear.
  ///
  /// In ur, this message translates to:
  /// **'Kisi bill par kuch baqi nahi'**
  String get partyCreditClear;

  /// No description provided for @partyCreditNoRule.
  ///
  /// In ur, this message translates to:
  /// **'Is par nahi'**
  String get partyCreditNoRule;

  /// No description provided for @partyCreditOwn.
  ///
  /// In ur, this message translates to:
  /// **'Apna'**
  String get partyCreditOwn;

  /// No description provided for @partyCreditSaveFirst.
  ///
  /// In ur, this message translates to:
  /// **'Pehle gahak save karein; phir apne udhaar ke qaide.'**
  String get partyCreditSaveFirst;

  /// No description provided for @creditBlockedTitle.
  ///
  /// In ur, this message translates to:
  /// **'Is gahak ka udhaar band hai'**
  String get creditBlockedTitle;

  /// No description provided for @creditBlockedHint.
  ///
  /// In ur, this message translates to:
  /// **'Cash, card ya wallet phir bhi le sakte hain. Malik apne PIN aur wajah se yeh ek bill guzaar sakta hai.'**
  String get creditBlockedHint;

  /// No description provided for @creditOwnerAllow.
  ///
  /// In ur, this message translates to:
  /// **'Malik ki ijazat (PIN)'**
  String get creditOwnerAllow;

  /// No description provided for @creditRaiseToday.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ke liye hadd barha kar save karein'**
  String get creditRaiseToday;

  /// No description provided for @creditBillsLine.
  ///
  /// In ur, this message translates to:
  /// **'Is samait {count} bill udhaar par; hadd {most}'**
  String creditBillsLine(int count, int most);

  /// No description provided for @creditDaysLine.
  ///
  /// In ur, this message translates to:
  /// **'{days} din purana bill baqi; hadd {most} din'**
  String creditDaysLine(int days, int most);

  /// No description provided for @creditTempLimitLine.
  ///
  /// In ur, this message translates to:
  /// **'Waqti hadd Rs {limit} ({date} tak) se ziyada; is bill se Rs {after}'**
  String creditTempLimitLine(String limit, String date, String after);

  /// No description provided for @creditOwnerRefused.
  ///
  /// In ur, this message translates to:
  /// **'Malik ne ijazat nahi di: udhaar band hai. Paisay lein, ya bill udhaar se hata dein.'**
  String get creditOwnerRefused;

  /// No description provided for @approvalOwnerTitle.
  ///
  /// In ur, this message translates to:
  /// **'Malik ki ijazat'**
  String get approvalOwnerTitle;

  /// No description provided for @approvalOwnerBody.
  ///
  /// In ur, this message translates to:
  /// **'Yeh sirf malik apne PIN aur wajah se guzaar sakta hai.'**
  String get approvalOwnerBody;

  /// No description provided for @approvalOwnerStock.
  ///
  /// In ur, this message translates to:
  /// **'{date} ki ginti: {count} cheezein kitaab se mukhtalif. Farq kitaab mein daal dein?'**
  String approvalOwnerStock(String date, int count);

  /// No description provided for @autoLockHeader.
  ///
  /// In ur, this message translates to:
  /// **'Din khud band hon'**
  String get autoLockHeader;

  /// No description provided for @autoLockIntro.
  ///
  /// In ur, this message translates to:
  /// **'Kitaab band hone ki tareekh roz khud aage barhti hai, taake malik ke PIN aur wajah ke baghair purani tareekh ki koi entry na ho.'**
  String get autoLockIntro;

  /// No description provided for @autoLockOff.
  ///
  /// In ur, this message translates to:
  /// **'Band: malik khud kitaab band karta hai'**
  String get autoLockOff;

  /// No description provided for @autoLockOlder.
  ///
  /// In ur, this message translates to:
  /// **'Khule dinon se purane din'**
  String get autoLockOlder;

  /// No description provided for @autoLockAtClose.
  ///
  /// In ur, this message translates to:
  /// **'Har din, galla ginne ke baad'**
  String get autoLockAtClose;

  /// No description provided for @autoLockDays.
  ///
  /// In ur, this message translates to:
  /// **'Kitne din khule rahein'**
  String get autoLockDays;

  /// No description provided for @autoLockNow.
  ///
  /// In ur, this message translates to:
  /// **'{date} tak band'**
  String autoLockNow(String date);

  /// No description provided for @autoLockSaved.
  ///
  /// In ur, this message translates to:
  /// **'Save ho gaya: din qaide ke mutabiq khud band honge'**
  String get autoLockSaved;

  /// No description provided for @stockCheckTitle.
  ///
  /// In ur, this message translates to:
  /// **'Stock ki ginti'**
  String get stockCheckTitle;

  /// No description provided for @stockCheckIntro.
  ///
  /// In ur, this message translates to:
  /// **'Roz kuch cheezein ittefaqan chuni jati hain (tez bikne wali aur mehngi ziyada, ek cheez do din lagatar nahi), shelf par gin lein. Farq kitaab mein tab jata hai jab malik manzoor kare.'**
  String get stockCheckIntro;

  /// No description provided for @stockCheckSize.
  ///
  /// In ur, this message translates to:
  /// **'Har ginti mein cheezein'**
  String get stockCheckSize;

  /// No description provided for @stockCheckDaily.
  ///
  /// In ur, this message translates to:
  /// **'Roz khud ginti chunein'**
  String get stockCheckDaily;

  /// No description provided for @stockCheckPick.
  ///
  /// In ur, this message translates to:
  /// **'Abhi ginti ke liye cheezein chunein'**
  String get stockCheckPick;

  /// No description provided for @stockCheckNone.
  ///
  /// In ur, this message translates to:
  /// **'Koi ginti khuli nahi. Nayi chunein.'**
  String get stockCheckNone;

  /// No description provided for @stockCheckOf.
  ///
  /// In ur, this message translates to:
  /// **'{date} ki ginti'**
  String stockCheckOf(String date);

  /// No description provided for @stockCheckShelf.
  ///
  /// In ur, this message translates to:
  /// **'Shelf par'**
  String get stockCheckShelf;

  /// No description provided for @stockCheckBooks.
  ///
  /// In ur, this message translates to:
  /// **'Kitaab: {qty}'**
  String stockCheckBooks(String qty);

  /// No description provided for @stockCheckDiff.
  ///
  /// In ur, this message translates to:
  /// **'Farq {qty}'**
  String stockCheckDiff(String qty);

  /// No description provided for @stockCheckDiffValue.
  ///
  /// In ur, this message translates to:
  /// **'Farq {qty} (Rs {value})'**
  String stockCheckDiffValue(String qty, String value);

  /// No description provided for @stockCheckKeep.
  ///
  /// In ur, this message translates to:
  /// **'Ginti rakhein'**
  String get stockCheckKeep;

  /// No description provided for @stockCheckPost.
  ///
  /// In ur, this message translates to:
  /// **'Malik manzoor kare: farq kitaab mein'**
  String get stockCheckPost;

  /// No description provided for @stockCheckPosted.
  ///
  /// In ur, this message translates to:
  /// **'Farq kitaab mein daal diya'**
  String get stockCheckPosted;

  /// No description provided for @stockCheckDrop.
  ///
  /// In ur, this message translates to:
  /// **'Yeh ginti chhor dein'**
  String get stockCheckDrop;

  /// No description provided for @stockCheckReasonLabel.
  ///
  /// In ur, this message translates to:
  /// **'Wajah?'**
  String get stockCheckReasonLabel;

  /// No description provided for @stockCheckHistory.
  ///
  /// In ur, this message translates to:
  /// **'Pichli gintiyan'**
  String get stockCheckHistory;

  /// No description provided for @stockCheckShrinkage.
  ///
  /// In ur, this message translates to:
  /// **'Mahine ka nuqsan'**
  String get stockCheckShrinkage;

  /// No description provided for @stockCheckShrinkLine.
  ///
  /// In ur, this message translates to:
  /// **'{month}: Rs {short} kam, Rs {over} ziyada, Rs {net} nuqsan ({checks} gintiyan)'**
  String stockCheckShrinkLine(
    String month,
    String short,
    String over,
    String net,
    int checks,
  );

  /// No description provided for @stockCheckStatusOpen.
  ///
  /// In ur, this message translates to:
  /// **'Ginti jari'**
  String get stockCheckStatusOpen;

  /// No description provided for @stockCheckStatusCounted.
  ///
  /// In ur, this message translates to:
  /// **'Gin li, malik ka intezar'**
  String get stockCheckStatusCounted;

  /// No description provided for @stockCheckStatusPosted.
  ///
  /// In ur, this message translates to:
  /// **'Kitaab mein'**
  String get stockCheckStatusPosted;

  /// No description provided for @stockCheckStatusDropped.
  ///
  /// In ur, this message translates to:
  /// **'Chhor di'**
  String get stockCheckStatusDropped;

  /// No description provided for @stockCheckHomeLine.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki ginti: {count} cheezein baqi'**
  String stockCheckHomeLine(int count);

  /// No description provided for @stockCheckHomeWaiting.
  ///
  /// In ur, this message translates to:
  /// **'Aaj ki ginti ho gayi: malik ka intezar'**
  String get stockCheckHomeWaiting;

  /// No description provided for @stockCheckItems.
  ///
  /// In ur, this message translates to:
  /// **'{count} cheezein'**
  String stockCheckItems(int count);

  /// No description provided for @cashierModeHeader.
  ///
  /// In ur, this message translates to:
  /// **'Cashier mode'**
  String get cashierModeHeader;

  /// No description provided for @cashierModeIntro.
  ///
  /// In ur, this message translates to:
  /// **'Salesman bill banata hai; cashier paisay le kar print karta hai. Salesman ka bill cashier ke paas intezar karta hai, aur paisay milne tak na stock hilta hai na kitaab.'**
  String get cashierModeIntro;

  /// No description provided for @cashierModeOn.
  ///
  /// In ur, this message translates to:
  /// **'Counter cashier mode mein chalayein'**
  String get cashierModeOn;

  /// No description provided for @cashierModeSalesmen.
  ///
  /// In ur, this message translates to:
  /// **'Salesman: bill banate hain, paisay nahi lete'**
  String get cashierModeSalesmen;

  /// No description provided for @cashierModeNoStaff.
  ///
  /// In ur, this message translates to:
  /// **'Pehle Staff mein apne PIN ke saath staff shamil karein.'**
  String get cashierModeNoStaff;

  /// No description provided for @cashierModeSaved.
  ///
  /// In ur, this message translates to:
  /// **'Cashier mode save ho gaya'**
  String get cashierModeSaved;

  /// No description provided for @cashierSendToCashier.
  ///
  /// In ur, this message translates to:
  /// **'Cashier ko bhejein'**
  String get cashierSendToCashier;

  /// No description provided for @cashierSent.
  ///
  /// In ur, this message translates to:
  /// **'{docNo} cashier ko bhej diya'**
  String cashierSent(String docNo);

  /// No description provided for @cashierHoldTitle.
  ///
  /// In ur, this message translates to:
  /// **'Cashier ke liye bill'**
  String get cashierHoldTitle;

  /// No description provided for @cashierHoldHint.
  ///
  /// In ur, this message translates to:
  /// **'Cashier paisay le kar bill print karega. Tab tak stock se kuch nahi nikalta.'**
  String get cashierHoldHint;

  /// No description provided for @cashierQueueTitle.
  ///
  /// In ur, this message translates to:
  /// **'Cashier counter'**
  String get cashierQueueTitle;

  /// No description provided for @cashierQueueEmpty.
  ///
  /// In ur, this message translates to:
  /// **'Koi bill intezar mein nahi'**
  String get cashierQueueEmpty;

  /// No description provided for @cashierMadeBy.
  ///
  /// In ur, this message translates to:
  /// **'{name} ne {time} par banaya'**
  String cashierMadeBy(String name, String time);

  /// No description provided for @cashierTakeMoney.
  ///
  /// In ur, this message translates to:
  /// **'Paisay le kar bill banayein'**
  String get cashierTakeMoney;

  /// No description provided for @cashierDrop.
  ///
  /// In ur, this message translates to:
  /// **'Hata dein: gahak chala gaya'**
  String get cashierDrop;

  /// No description provided for @cashierHomeLine.
  ///
  /// In ur, this message translates to:
  /// **'{count} bill cashier ke paas intezar mein'**
  String cashierHomeLine(int count);

  /// No description provided for @cashierSalesmanNote.
  ///
  /// In ur, this message translates to:
  /// **'Cashier mode: aap ke bill cashier ko jaate hain, paisay woh leta hai.'**
  String get cashierSalesmanNote;
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
