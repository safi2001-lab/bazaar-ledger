# What leaves the phone

This product's central claim is that a shopkeeper's books stay on their phone.
That claim is worth exactly as much as its precision, so this page states what
is true, what changed, and where the edges are.

Last checked against primary sources on **24 August 2026**.

---

## The claim, stated precisely

**No shop data reaches any server. Not ours — we operate none — and not
anybody's.** No invoice, no customer name, no balance, no item, no price, no
photograph, no barcode a shopkeeper scanned, no ledger entry, ever leaves the
device except when the shopkeeper themselves exports or shares it.

Every earlier, broader formulation is now wrong and must not be used:

- ~~"the app makes no network call"~~ — false since ML Kit was added.
- ~~"the app cannot phone anywhere"~~ — false since `INTERNET` was declared for
  the LAN printer.

## What the app itself sends: nothing

There is no backend. There is no account. The billing path makes no network
call of any kind, and a sale completes identically on a phone in airplane mode.
`INTERNET` exists because Android gates the creation of **any** socket behind
it, including one to a thermal printer at `192.168.x.x` on the shop's own
wi-fi.

## What Google's ML Kit sends, and why it is here

Adding camera barcode scanning brought in `com.google.mlkit:barcode-scanning`,
which depends on Google's Firelog transport (`transport-backend-cct`,
`transport-runtime`). Those libraries batch telemetry to
`firebaselogging.googleapis.com` roughly every fifteen minutes.

**What Google receives** — per Google's own [ML Kit data
disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and
[ML Kit Terms of Service](https://developers.google.com/ml-kit/terms):

- device manufacturer, model, OS version and build, available ML accelerators
- this app's package name and version
- performance metrics such as latency
- device and per-installation identifiers, for diagnostics
- API configuration — image format, resolution
- event types (initialisation, detection) and error codes

**What Google does not receive**, stated verbatim in those Terms:

> "processing of the input data (e.g. images, video, text) fully happens
> on-device, and ML Kit does not send that data and the resultant outputs to
> Google servers."

So: no camera frames, no barcode contents, no item this app matched, and
nothing whatsoever from the ledger.

### There is no opt-out, and claims that there is are wrong

Standalone ML Kit — the `com.google.mlkit:*` artifacts, not Firebase — offers
no documented way to disable this. `MlKit` exposes exactly one public method,
`initialize(Context)`. There is no logging API.

Four flags are commonly cited and none of them work here:

| Flag | Reality |
|---|---|
| `firebase_data_collection_default_enabled` | A Firebase SDK flag. This app has no Firebase and no `google-services.json`. |
| `com.google.mlkit.vision.DEPENDENCIES` | Real, but it triggers install-time model download for the **unbundled** variant. We use bundled. Adding it would be wrong. |
| `com.google.android.gms.vision.DEPENDENCIES` | The deprecated Mobile Vision equivalent. No effect. |
| `google_analytics_automatic_screen_reporting_enabled` | Firebase Analytics. Unrelated. |

Excluding the datatransport libraries in Gradle is **not** a supported route.
They are hard compile-scope dependencies of `com.google.mlkit:common`, and the
documented failure mode is `NoClassDefFoundError` — which would surface the
first time a shopkeeper taps scan, on a real device, having passed every host
test. That is precisely the failure class this project keeps finding in itself,
so it is not being done blind.

One documented option remains open and is **not yet taken**: removing
`MlKitInitProvider` with `tools:node="remove"` and calling `MlKit.initialize()`
lazily, so a shop that never scans never initialises ML Kit at all. That fits
this architecture well — many shops use a USB gun and never open the camera —
but its actual effect on telemetry volume is unverified, and getting it wrong
breaks scanning on a handset rather than in a test. It waits for a device.

### Why ML Kit is bundled and not downloaded

The unbundled variant is about 3 MB smaller and fetches its model through Play
Services on first use. Google's own documentation says requests made before
that download completes "produce no results" — silently. That first use is a
shopkeeper at a counter with a customer waiting, on a connection Pakistan lost
9,735 hours of in 2024.

The bundled model is statically linked and, per Google, "available
immediately". **A phone that has never had a network connection will scan
barcodes.** The only thing a missing network affects is whether a telemetry
batch succeeds, and a failed telemetry POST does not impede scanning.

## Handing a message to WhatsApp

The khata can open WhatsApp on a customer's chat with a payment reminder
already typed. This is worth stating precisely, because it is the one place
the app puts a customer's name and balance in front of another application.

**Nothing is sent by this app.** There is no WhatsApp account, no Business
API, no token and no endpoint. `whatsapp://send?phone=…&text=…` is an Android
intent: it resolves to the app already installed on the phone, and hands it a
string exactly the way a share does. What happens next is between the
shopkeeper and WhatsApp, under WhatsApp's own privacy policy — the same as if
they had typed it themselves.

**Deliberately never `wa.me/…`.** That URL is the recipe every tutorial gives
and it is wrong for this app: with WhatsApp absent it opens a browser to
Meta's servers, which is a network request this product does not make on a
shopkeeper's behalf. The fallback is the system share sheet, which reaches
SMS — still common in this market — and needs no network at all.

The `<queries>` block naming `com.whatsapp` and `com.whatsapp.w4b` exists so
`canLaunchUrl` can answer whether WhatsApp is there before the button offers
itself. On Android 11 and above it returns false without that block however
installed WhatsApp is. It is narrow on purpose: `QUERY_ALL_PACKAGES` is a
Play-restricted permission requiring a declaration review, and this needs to
see two packages.

## Backups

A backup is the whole database, and it is the one file this app makes
specifically so that it can leave the phone. So it is worth being exact.

**The app sends it nowhere.** *Settings → Backup* seals the books into a
`.pkbak` file and hands it to Android's own share sheet. Where it goes next —
WhatsApp to the shopkeeper's own number, Google Drive, a USB stick — is chosen
there, by them, exactly as if they had shared a photo. There is no backup
server, no account, and no automatic upload; `android:allowBackup="false"`
still keeps the live database out of Google's Auto Backup.

**The file is useless without its passphrase.** Argon2id (19 MiB, two passes)
turns the passphrase into a key, and AES-256-GCM seals the data. Whoever holds
the file — Google, WhatsApp, whoever finds the USB stick — sees a date, a
schema number and an app version, and nothing else: no shop name, no customer,
no amount. The file name is only a date for the same reason. There is no
recovery: a forgotten passphrase is a backup nobody can open, and the screen
says so before the backup is made.

**Restoring replaces, but never deletes.** The books a restore replaces are
kept beside it as `bazaar_ledger.sqlite.before-restore`.

## Demand notices for bounced cheques

The cheque drawer can draw up the Section 489-F demand notice for a cheque the
bank returned. It carries more about a customer than anything else the app
produces: name, address, phone and CNIC from the khata, the cheque's number,
bank and amount, and the bank's remarks. So, precisely:

**The app sends it nowhere.** The notice is rendered on the phone into a PDF
in the app's temporary directory and handed to Android's share sheet, the same
as a shared bill. Where it goes — a printer, an advocate on WhatsApp, the
shop's own email — is chosen there, by the shopkeeper. Nothing is filed, served
or uploaded by the app, and there is no legal-services integration of any
kind.

## Permissions, and where each comes from

| Permission | Source | Prompts? | Why |
|---|---|---|---|
| `INTERNET` | this app, and ML Kit's transport | no | Android gates every socket behind it, including one to a LAN printer |
| `CAMERA` | this app | yes, on first scan | reading a barcode off a packet |
| `ACCESS_NETWORK_STATE` | ML Kit's transport | no | normal permission; reads connectivity state, grants no network access |
| `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, and the two legacy ones | the printer plugin | yes, if a shop uses a Bluetooth printer | talking to an already-paired printer |
| `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core` | never | signature-level, grantable only to this app's own key; security hardening, not a capability |

Deliberately absent, and asserted absent by tests:

- **`READ_MEDIA_IMAGES`** — item photographs go through Android's system Photo
  Picker, which needs no permission at all. Play restricts this one to apps
  whose core function the picker cannot serve.
- **Any `LOCATION` permission** — `BLUETOOTH_SCAN` carries `neverForLocation`
  precisely so finding a printer never becomes a location request.
- `RECORD_AUDIO`, `QUERY_ALL_PACKAGES`, `MANAGE_EXTERNAL_STORAGE`.

`ACCESS_NETWORK_STATE` never prompts, but it **is** visible on the Play listing
under *About this app → App info → See more*, labelled "view network
connections". A shopkeeper who looks will find it, so it is allowlisted in
`tool/android_gates.dart` with its reason attached rather than tolerated
quietly.

## Play Data Safety form

Google is explicit that an SDK's collection is the developer's to declare:

> "You must reflect data collection or sharing carried out by such third-party
> code in the Data safety form."

So the form must say, at minimum:

- **App info and performance / Diagnostics** — collected, for Analytics and App
  functionality. Not shared. Encrypted in transit.
- **Device or other IDs** — ML Kit collects a per-installation diagnostic
  identifier. Google publishes no ruling on whether this must be declared;
  declare it. Over-disclosure is never a policy violation and under-disclosure
  is.

Nothing else. No camera images, no barcode contents, no financial data, no
customer data, no location.

**The listing copy should get ahead of this.** An app whose pitch is that
nothing leaves the phone, showing "Diagnostics: collected" on its Data Safety
card, invites exactly the wrong conclusion. Say it plainly: *diagnostic data
from Google's on-device scanning library; your hisaab never leaves the phone.*
