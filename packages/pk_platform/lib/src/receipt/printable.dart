/// What a thermal printer's own font can and cannot say.
///
/// ## The problem, precisely
///
/// A thermal printer draws text from a ROM font selected by a code page. It
/// is a lookup table of 256 glyphs and nothing else: no shaping engine, no
/// bidirectional algorithm, no fallback. The community ESC/POS capability
/// database catalogues seventy encodings across every printer family in
/// common use and **not one of them is Urdu**.
///
/// The near miss is CP1256, which does contain the Arabic letters Urdu is
/// written with, and reaching for it is the obvious mistake. It fails three
/// ways at once and each is enough on its own:
///
///   * **No shaping.** Arabic script is cursive and every letter has up to
///     four contextual forms. A code page holds the isolated forms, so
///     `کتاب` prints as four disconnected shapes — legible to nobody.
///   * **No bidi.** The printer emits left to right, so an Urdu line comes
///     out reversed, and a line mixing Urdu with a price comes out
///     interleaved wrongly.
///   * **No Urdu letters.** CP1256 is Arabic, not Urdu: `ٹ ڈ ڑ ں ے` and the
///     Urdu `ہ` are simply absent.
///
/// So there is no byte sequence this app could send that would print Urdu.
/// The only way a printer puts Urdu on paper is as a picture — `GS v 0`,
/// raster mode — with the shaping and the bidi done here, by a text engine
/// that has both.
///
/// ## Why this matters even though the receipt is Roman Urdu
///
/// Every string this app owns is Roman Urdu in Latin script, so the fast path
/// covers the whole template. What it does not cover is the shop's own words:
/// the shop name, its address, an item typed as `چاول` rather than `chawal`,
/// a customer's name. That is free text, and a shopkeeper who types their
/// shop name in Urdu is not doing anything unreasonable.
///
/// Before this, such a line printed as a row of question marks — the encoder
/// replaces what it cannot represent rather than emitting a byte the printer
/// would draw as a random glyph, which is the right call and still leaves the
/// shopkeeper holding a receipt with `??????` where their shop name should
/// be. Silent, wrong, and blamed on the printer.
library;

/// Whether [value] survives the printer's Latin font intact.
///
/// The encoder folds a handful of typographic characters — curly quotes, en
/// and em dashes, the real minus sign, a non-breaking space — onto their
/// ASCII equivalents, and those foldings are lossless enough to print. So
/// they count as printable here: rasterising a line because it contains a
/// smart apostrophe would be a picture where crisp font text would do.
///
/// Anything else outside printable ASCII is not printable, and the caller
/// must draw it rather than spell it.
bool isPrintableLatin(String value) {
  for (final rune in value.runes) {
    if (rune == 0x0A) continue;
    if (rune >= 0x20 && rune <= 0x7E) continue;
    if (_folded.contains(rune)) continue;
    return false;
  }
  return true;
}

const _folded = <int>{
  0x2014, // em dash
  0x2013, // en dash
  0x2018, 0x2019, // curly single quotes
  0x201C, 0x201D, // curly double quotes
  0x2212, // minus sign
  0x00A0, // non-breaking space
};
