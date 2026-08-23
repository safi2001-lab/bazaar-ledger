/// Build-time configuration: the handful of identifiers this app needs from
/// outside itself.
///
/// Supplied with `--dart-define-from-file=config/app_config.json`, which is
/// gitignored; `config/app_config.example.json` is committed and documents
/// every key. Nothing here is read from an asset, a file on the device, or a
/// network call — assets ship inside the APK where anyone can read them, and
/// there is no server to fetch anything from.
///
/// None of these are secrets, and that is not an accident:
///
///   * An Android OAuth client has no client secret. Google identifies the
///     app by package name plus signing-certificate fingerprint, with PKCE.
///     A secret would need somewhere to live, and the only safe somewhere is
///     a server — which this product does not have and will not have.
///   * The Play Billing key is Google's PUBLIC key. It verifies that a
///     purchase payload was signed by Google; it cannot mint one.
///
/// So a leaked config file here is not a breach. It is still gitignored,
/// because a client ID belongs to whoever owns the Play listing and this
/// repository may outlive that.
///
/// Every field is empty until it is supplied, and every consumer must treat
/// empty as "this feature is not configured on this build" and degrade to
/// something honest — never a crash, and never a screen that pretends the
/// feature is working.
abstract final class AppConfig {
  /// OAuth client ID for Google Drive backup (M5).
  ///
  /// Scope is `drive.appdata` and nothing else: a private per-app folder the
  /// shopkeeper can see the size of and delete, which we cannot read anything
  /// else from. That scope is classified non-sensitive, so it needs no Google
  /// app verification and no CASA security assessment — the reason Drive is
  /// the chosen backup target and OneDrive is not.
  ///
  /// From Google Cloud Console → Credentials → OAuth 2.0 Client IDs →
  /// Android. It wants the package name (`pk.bazaarledger`) and the SHA-1 of
  /// the signing certificate; with Play App Signing, take that SHA-1 from the
  /// Play Console signing page, not from the local keystore.
  static const googleOAuthClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

  /// The base64 RSA public key from Play Console → Monetisation setup (M9).
  ///
  /// Every purchase Google returns is signed with the matching private key.
  /// Entitlement is written only after that signature verifies on the device.
  /// The previous build's paywall called `activateTier()` on a button tap
  /// with no purchase at all, and someone had flipped the default tier to
  /// `platinum`; verifying the signature is what makes that class of mistake
  /// impossible rather than merely absent.
  static const playBillingPublicKey =
      String.fromEnvironment('PLAY_BILLING_PUBLIC_KEY');

  /// True when Drive backup can be offered at all on this build.
  ///
  /// A build with no client ID still backs up locally and still shares a file
  /// through the OS — the Drive switch is simply not shown, rather than shown
  /// and broken.
  static bool get hasDriveBackup => googleOAuthClientId.isNotEmpty;

  /// True when subscriptions can be verified on this build.
  ///
  /// Without the key, entitlement stays at whatever the device already holds
  /// and no purchase can be accepted. It must never fall open: a build that
  /// cannot verify a purchase must refuse to grant one, not assume the best.
  static bool get hasPlayBilling => playBillingPublicKey.isNotEmpty;

  /// What is missing, in words, for the diagnostics screen.
  ///
  /// A shopkeeper never sees this. Whoever is holding the phone when a
  /// feature is mysteriously absent does, and "GOOGLE_OAUTH_CLIENT_ID is not
  /// set in this build" is a better answer than a switch that does nothing.
  static List<String> get missing => [
        if (!hasDriveBackup) 'GOOGLE_OAUTH_CLIENT_ID',
        if (!hasPlayBilling) 'PLAY_BILLING_PUBLIC_KEY',
      ];
}
