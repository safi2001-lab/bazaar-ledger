# Releasing Bazaar Ledger to Google Play

Everything in the code is done. A release needs only credentials that
belong to whoever owns the Play listing, and they all go in as
**environment variables**, as GitHub Actions secrets in CI or a `.env`
file on a laptop. None of them is ever committed. `.env.example` lists every
one.

| Secret | What it unlocks | Where it comes from |
|---|---|---|
| `UPLOAD_KEYSTORE_BASE64`, `UPLOAD_STORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, `UPLOAD_KEY_PASSWORD` | Signing the bundle | Step 1 |
| `PLAY_BILLING_PUBLIC_KEY` | Selling the plans | Step 3 |
| `GOOGLE_OAUTH_CLIENT_ID` | Daily Google Drive backup | Step 4 |
| `PLAY_SERVICE_ACCOUNT_JSON` (optional) | CI uploads to Play by itself | Step 6 |

Add each one in GitHub: **Settings › Secrets and variables › Actions › New
repository secret**, named exactly as above.

---

## 1. The upload key (once, and keep it forever)

```sh
keytool -genkeypair -v -keystore upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 upload.jks        # → UPLOAD_KEYSTORE_BASE64 (macOS: base64 -i upload.jks)
```

Store `upload.jks` and its passwords somewhere safe outside the repository,
such as a password manager. Play App Signing (step 2) holds the real app
signing key, so a lost upload key can be reset through Play support, but
it takes days.

Once these four secrets are set, the **Tier B** CI job also starts running
its release checks (signing, the merged permission list, 16 KB alignment,
size) on every push instead of skipping them.

## 2. The Play Console app

1. [Play Console](https://play.google.com/console) › **Create app**.
   Name it *Bazaar Ledger*, App, Free (the app is free and the plans are
   in-app subscriptions).
2. Package name: **`pk.bazaarledger`**. It is fixed by the first upload
   and cannot change.
3. **App integrity › App signing**: accept Play App Signing.

## 3. The subscriptions → `PLAY_BILLING_PUBLIC_KEY`

1. **Monetise › Products › Subscriptions › Create subscription**, three
   times, with exactly these product IDs (the app looks for them):

   | Product ID | Name | Base plan | Price |
   |---|---|---|---|
   | `plan_silver` | Silver | yearly, auto-renewing | Rs 1,999 |
   | `plan_gold` | Gold | yearly, auto-renewing | Rs 3,499 |
   | `plan_platinum` | Platinum | yearly, auto-renewing | Rs 5,999 |

   Activate each base plan. A price changed in Play Console shows in the
   app as Play sends it; the rupee figures in the app are only shown
   before Play answers.
2. **Monetise › Monetisation setup › Licensing**: copy the base64 public
   key → secret `PLAY_BILLING_PUBLIC_KEY`.
3. To test buying without paying, add testers under **Settings › License
   testing**. Their purchases are free and renew every few minutes.

The app checks Google's signature on every purchase on the phone. Without
this key a build sells nothing and every phone is on Free.

## 4. Google Drive backup → `GOOGLE_OAUTH_CLIENT_ID`

1. [Google Cloud Console](https://console.cloud.google.com): create (or
   pick) a project › **APIs & Services › Library** › enable **Google Drive
   API**.
2. **OAuth consent screen**: External, app name *Bazaar Ledger*, your
   support email, scope `.../auth/drive.appdata` only (non-sensitive, so no
   verification review). **Publish to production.** While it is in
   Testing, Google stops refreshing access after 7 days.
3. **Credentials › Create credentials › OAuth client ID › Android**:
   package `pk.bazaarledger`, SHA-1 from **Play Console › App integrity ›
   App signing key certificate**. Use that SHA-1, not your upload key's,
   or sign-in fails on every Play-installed phone. Add a second Android
   client with the upload key's SHA-1 (`keytool -list -v -keystore
   upload.jks`) if you also sideload release builds.
4. Copy the client ID → secret `GOOGLE_OAUTH_CLIENT_ID`.

## 5. Store listing and policy

- **Privacy policy URL**: `docs/privacy_policy.md`. Replace `CONTACT_EMAIL`
  with your support address, then publish it. GitHub Pages works, or the
  file's github.com address if the repository is public.
- **Data safety**: answer from the "Play Data Safety form" section of
  `docs/what_leaves_the_phone.md`:
  - App info and performance, and Device or other IDs (ML Kit diagnostics):
    collected, not shared.
  - Financial info: purchase history through Google Play.
  - Files and docs: transferred at the user's direction (Drive backup),
    encrypted.
  - Encryption in transit: yes. Users can request deletion: yes (on the
    phone).
- **Content rating** questionnaire: a business tool, no user-generated
  content shared publicly.
- **Target audience**: 18+.
- **App access**: all features reachable without a login. Paid features
  can be reviewed with a license tester account (step 3).
- Screenshots: run the APK from the "phone apk" workflow. On that build,
  *Settings › Plan* has a test switch that opens every plan, so every
  screen can be captured.

## 6. Build and upload

**From GitHub (recommended).** Go to **Actions › release › Run workflow** and
enter a version such as `1.0.0`, or push a tag `v1.0.0`. The workflow:

1. writes the credentials from secrets (`tool/release_env.dart --release`
   refuses if any are missing);
2. runs the analyzer, the architecture check and every test;
3. builds `app-release.aab`, signed, obfuscated, with a version code that
   rises on every run;
4. keeps the bundle, R8 mapping and Dart symbols as the run's artifact for
   90 days;
5. if `PLAY_SERVICE_ACCOUNT_JSON` is set, uploads it to the **internal
   testing** track. Create that service account in Google Cloud, grant it
   *Release to testing tracks* in **Play Console › Users and permissions**,
   and paste its JSON key as the secret.

Without the service account, download the `.aab` from the run and upload it
in **Play Console › Testing › Internal testing › Create release**.

**From a laptop.**

```sh
cp .env.example .env        # fill it in
dart run tool/release_env.dart --release
flutter build appbundle --release \
  --dart-define-from-file=config/app_config.json \
  --obfuscate --split-debug-info=build/symbols
```

The first upload must be done by hand in Play Console, because Play only
accepts API uploads after an app has one release. Then go from internal
testing to closed testing, and to production when ready. New personal
developer accounts must run a closed test with at least 12 testers for 14
days before production is unlocked.

## 7. After release

- Plans are checked again whenever the app comes to the front and Play is
  reachable. A cancelled or lapsed subscription returns the phone to Free
  within 30 days even if it never goes online. Nothing a shop made is ever
  locked.
- FBR Digital Invoicing is configured per shop in the app (*Settings › Tax
  › FBR*) with the token PRAL issues that shop. It is not a release
  secret.
