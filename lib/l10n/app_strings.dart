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
  /// **'Charge'**
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
  /// **'PDF bill ka andaaz: design, rang, logo aur payment QR. Thermal slip waisi hi rehti hai; us par sirf baqaya, neeche ki likhai aur QR ka faisla yahan hota hai.'**
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
