/// Exact, integer-only money arithmetic for Bazaar Ledger.
///
/// Three value types, no floating point anywhere:
///
/// * [Money] — whole **paisa**. Every amount stored, summed or printed.
/// * [Qty]   — whole **thousandths of a base unit**. Weights, counts, volumes.
/// * [Rate]  — whole **milli-paisa per base unit**. Unit prices, which need
///   three digits more precision than the amounts they produce.
///
/// The one place the three meet is [Rate.amountFor], which multiplies a rate
/// by a quantity and lands on an exact paisa amount.
///
/// This package deliberately has **zero dependencies**. Nothing above it may
/// reintroduce a `double` for money — the previous build did, and then hid the
/// resulting drift behind a `> 0.01` tolerance in its ledger balance check.
library;

export 'src/money.dart';
export 'src/qty.dart';
export 'src/rate.dart';
export 'src/rounding.dart';
