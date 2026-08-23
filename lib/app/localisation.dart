import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Roman Urdu is the default, and it is written in Latin script.
///
/// That is not a compromise. Every Pakistani khata competitor — DigiKhata,
/// Easy Khata, Udhaar Book, CreditBook — ships an English-only interface and
/// then writes Roman Urdu in their own marketing copy, because Roman Urdu in
/// Latin script is what shopkeepers read. National literacy is 60.65% and
/// rural literacy is 51.6%, and somebody who cannot read fluently cannot read
/// Nastaliq either.
///
/// Flutter ships an `ur` localisation, but it is Urdu script and right to
/// left. Using it directly would mirror the whole layout and put Nastaliq on
/// every Material button. So the three delegates below claim `ur` and hand
/// back the English implementations: our own strings come from the ARB files,
/// the chrome stays Latin, and the layout stays left to right.
///
/// When real Nastaliq arrives it becomes a third locale with its own ARB and
/// its own RTL delegates. Nothing here has to be rewritten for that.
const List<Locale> supportedLocales = [Locale('ur'), Locale('en')];

const List<LocalizationsDelegate<dynamic>> chromeDelegates = [
  _RomanUrduMaterialDelegate(),
  _RomanUrduCupertinoDelegate(),
  _RomanUrduWidgetsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class _RomanUrduMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _RomanUrduMaterialDelegate();

  @override
  bool isSupported(Locale locale) => _isRomanUrdu(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_) => false;
}

class _RomanUrduCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _RomanUrduCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => _isRomanUrdu(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_) => false;
}

class _RomanUrduWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _RomanUrduWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => _isRomanUrdu(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(
        const DefaultWidgetsLocalizations(),
      );

  @override
  bool shouldReload(_) => false;
}

/// Roman Urdu is `ur` with no script subtag. A future `ur_Arab` is real Urdu
/// and must fall through to the global delegates.
bool _isRomanUrdu(Locale locale) =>
    locale.languageCode == 'ur' && locale.scriptCode == null;
