import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A build with nothing configured must still be a working shop.
///
/// These identifiers arrive late: an OAuth client ID cannot exist before
/// there is a Play listing to bind it to, and the Billing key cannot exist
/// before there is a Monetisation setup page. Everything up to that point is
/// built and tested against a build that has neither.
///
/// So the contract is that absence is a normal state, not a broken one. The
/// counter rings bills, the books balance, receipts print. What is missing is
/// missing visibly, in the diagnostics list, rather than as a switch that
/// does nothing when a shopkeeper taps it.
void main() {
  test('an unconfigured build offers neither feature', () {
    // The suite runs with no --dart-define, which is exactly the state of
    // every build made before the Play listing exists.
    expect(AppConfig.googleOAuthClientId, isEmpty);
    expect(AppConfig.playBillingPublicKey, isEmpty);
    expect(AppConfig.hasDriveBackup, isFalse);
    expect(AppConfig.hasPlayBilling, isFalse);
  });

  test('and says which identifier it is missing', () {
    expect(
      AppConfig.missing,
      containsAll(<String>[
        'GOOGLE_OAUTH_CLIENT_ID',
        'PLAY_BILLING_PUBLIC_KEY',
      ]),
      reason: 'a feature that is absent must say why it is absent',
    );
  });

  test('billing never falls open', () {
    // The failure mode that matters. A build that cannot verify a purchase
    // must refuse to grant entitlement, not assume the best — the previous
    // build called `activateTier()` on a button tap with no purchase at all,
    // and its default tier had been flipped to `platinum`.
    expect(
      AppConfig.hasPlayBilling,
      isFalse,
      reason: 'no key means no verification means no entitlement, ever',
    );
  });
}
