# Bazaar Ledger — Privacy Policy

_Effective: 1 October 2026_

Bazaar Ledger is a billing, khata and stock app for shops. It is built so
that a shop's books stay on the shop's own phone. This policy says exactly
what leaves the phone, when, and why. The technical detail behind every
line is in [what_leaves_the_phone.md](what_leaves_the_phone.md).

## The short version

- **We run no server and keep no copy of your data.** There is no account
  with us. Bills, customers, khatas, stock, prices and cheques are stored on
  your phone, encrypted, and nowhere else unless you send them.
- **Nothing is sold, shared for advertising, or used to profile you.** The
  app has no ads and no analytics of its own.

## What stays on your phone

Everything you enter: your shop's details, items, customers and suppliers,
bills, payments, cheques, stock, staff names and their PINs (stored as
hashes), photos of items, and settings. The database is encrypted with a key
kept in Android's keystore.

## What leaves your phone, and only when you choose it

| When | What goes | Where |
|---|---|---|
| You share a bill, report or backup | That file | Wherever you send it in Android's share sheet (WhatsApp, email, Drive…) |
| You turn on the daily Google Drive backup (paid plans) | Your books, **sealed with a passphrase only you know** | A private app folder in **your own** Google Drive. Google cannot open it and neither can we. |
| You connect another counter on your shop's wi-fi | The shop's books | Your other phone on the same wi-fi network, directly. Nothing goes over the internet. |
| A sales-tax-registered shop turns on FBR Digital Invoicing (Platinum) | Each new bill's invoice details (your NTN/STRN, the buyer's name and NTN, items, HS codes, quantities, prices, tax) | FBR's Digital Invoicing gateway, or the integrator address you enter, as the law requires |
| You print to a network printer | The receipt | The printer on your own network |
| You buy a plan | Nothing about your shop | Google Play handles the payment. The app asks Play which plan your Google account has. |

## Third-party services

- **Google Play Billing**, to buy a plan. Payment details go to Google, not
  to us. [Google's privacy policy](https://policies.google.com/privacy)
  applies.
- **Google Sign-In and Google Drive**, only if you turn on Drive backup. The
  app asks for access to its own app folder (`drive.appdata`) and nothing
  else on your Drive, and never for your name or email.
- **Google ML Kit barcode scanning** reads barcodes on the phone. The images
  never leave the phone. ML Kit sends Google anonymous diagnostic data
  (performance and an installation identifier). This is Google's, not
  ours, and is described in Google's ML Kit terms.

## Permissions

- **Camera**: to scan barcodes, asked for the first time you tap scan.
- **Nearby devices / Bluetooth**: to print on a paired Bluetooth printer.
- **Internet**: for a network printer, wi-fi counters, Drive backup, FBR
  and Google Play. The app works fully offline without it.
- **Photos**: through Android's own photo picker, which needs no
  permission. Only the photo you pick is read.

## Children

The app is for shopkeepers running a business and is not directed at
children under 13.

## Deleting your data

Uninstalling the app deletes everything on the phone. Backups you made or
shared, and the Drive app folder, are in places you control: delete them
there (Google Drive › Settings › Manage apps › Bazaar Ledger › Delete hidden
app data). We hold nothing to delete.

## Changes

If this policy changes, the new version is published at the same address
with a new effective date before the app that needs it is released.

## Contact

Questions about privacy: **CONTACT_EMAIL**
