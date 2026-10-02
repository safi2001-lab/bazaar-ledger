# Competitor research appendix: Pakistan rules, Pakistani apps, and the evidence log (2 Oct 2026)

This file is the companion to `docs/competitor_research.md`. It keeps everything the research session found
that the main document does not carry, so none of it is lost:

1. Pakistan rules an invoice and report engine has to honour (FBR, provinces, DRAP, PTA)
2. How Pakistani shops actually work (what to model)
3. Pakistani khata, billing and POS apps, one by one
4. Mistakes the competition made (from 1–2★ reviews)
5. Review-mining numbers
6. Detail notes on Zoho, Marg, Tally, myBillBook, Swipe and Khatabook that the main doc only summarises
7. What Bazaar Ledger already has (checked in the code on 2 Oct 2026, after M32)
8. Evidence log: every Vyapar page, screenshot, video and code bundle used, and what each proved
9. Searches that found nothing, and blocked sources
10. Raw data and how to regenerate it

**Tags:** [V] verified this session from an official page, screenshot, code bundle or the vendor's own video;
[R] from user reviews; [K] recalled or third-party, not confirmed; [unverified] a single weak source.

---

## 1. Pakistan rules the invoice and report engine has to honour

### 1.1 FBR: ordinary registered-person tax invoice (s.23 Sales Tax Act)
Every registered seller's invoice needs: serial number; supplier name, address and registration number;
recipient name, address and registration number; date; description and quantity; value excluding tax;
sales tax; value including tax ([pkrevenue](https://pkrevenue.com/sales-tax-act-1990-requirement-of-issuing-tax-invoice/)).
**All of this can be produced fully offline.**

### 1.2 FBR: Tier-1 retailers and integrated POS
Source for this section unless marked: [FBR POS Booklet 2025](https://download1.fbr.gov.pk/Docs/202551615541769POSBooklet.pdf).

- **Tier-1 retailer (s.2(43A)):** a unit of a national or international chain; a shop in an air-conditioned
  mall, plaza or centre (kiosks excluded); electricity bill over **Rs 1.2 million** in the last 12 months;
  a wholesaler-cum-retailer in bulk import; a retailer that has a bank card-payment POS; 236G/236H withholding
  above a notified threshold; others the Board prescribes.
  - Finance Act 2026 reportedly adds a **turnover over Rs 200 million** test and drops the card-POS clause
    ([pkrevenue](https://pkrevenue.com/finance-act-2026-redefines-tier-1-retailer-under-sales-tax-law/)) **[verify against the gazetted Act]**.
  - Most kiryana, pharmacy and mobile shops are **not** Tier-1. Some wholesalers and bigger stores are.
- **What an integrated POS must do (Rule 150R(4)):** generate, store and analyse invoice data; digitally sign
  the invoice; send it to FBR and receive the **FBR invoice number**; print a **QR code of that number**;
  do day, week and month **closings**; **log every adjustment, modification or cancellation**; alert on malpractice.
  FBR may also require card/QR acceptance, CCTV and an "Integrated with FBR" sign with the software registration number.
- **Particulars on an integrated invoice (Rule 150R(13)):**
  (a) FBR invoice number, format `XXXXXX-DDMMYYHHMMSS-0001`; (b) QR code, 7×7 mm; (c) POS / e-invoicing software
  registration number; (d) FBR digital invoicing logo; (e–g) seller name, address, registration number;
  (h–j) buyer name, address, registration number; (k) date; (l) tax period; (m) description; (n) quantity;
  (o) value excluding tax; (p) sales tax rate; (q) sales tax amount; (r) tax withheld; (s) extra tax;
  (t) further tax; (u) FED in sales-tax mode; (v) total discount; (w) invoice reference number; (x) HS code;
  (y) unit of measure; (z) SRO / serial number. Items (s), (t), (u) and (z) need not appear on retail
  invoices to the general public.
- **Offline invoices (Rule 150XC):** invoices issued during an internet or power failure must be
  **"clearly identified as invoices issued in the offline mode and uploaded within 24 hours of restoration"**
  (booklet; [EY summary](https://taxnews.ey.com/news/2025-0376-pakistan-amends-sales-tax-rules-for-implementation-of-electronic-invoicing)).
  Records are kept **6 years**. Debit and credit notes are electronic too.
- **POS service fee:** Re 1 per invoice (s.76), collected from the customer by Tier-1 retailers
  ([Business Recorder](https://www.brecorder.com/news/amp/40113971)).
- **Buyer's name** is required when one invoice exceeds **Rs 100,000**
  ([ProPakistani](https://propakistani.pk/2021/08/09/fbr-now-requires-name-of-the-buyer-from-retailers-if-invoice-is-over-rs-100000/amp/)).
- **Digital Invoicing for all registered persons (SRO 709(I)/2025):** corporate by 1 Jun 2025, non-corporate by
  1 Jul 2025 after extension ([KPMG](https://assets.kpmg.com/content/dam/kpmg/pk/pdf/2025/04/A-Brief-on-Integration-Deadlines.pdf),
  [Sovos](https://sovos.com/regulatory-updates/sut/pakistan-mandatory-e-invoicing-integration-deadlines-announced/)).
  FMCG distributors and wholesalers were covered from Feb 2024. Live posting needs the PRAL API (BL M19 has it).
- **Customers do check FBR receipts:** the Tax Asaan app (1M+ installs) verifies a POS invoice by number or QR,
  and "INV <number>" to 9966 enters the monthly prize draw
  ([Play](https://play.google.com/store/apps/details?id=com.pral.fbr_varification_system),
  [FBR](https://fbr.gov.pk/fbr-launches-much--awaited-prize-scheme-on-po/173269)).
- Scale: about 11,141 Tier-1 retailers integrated by Feb 2026 (Profit headline) **[unverified]**.

### 1.3 Rates
- **Standard sales tax 18%**, unchanged in Budget 2026-27 (IMF's 19% not adopted)
  ([Bol News](https://www.bolnews.com/business/imf-asks-pakistan-to-increase-gst-to-19-in-budget-2026-27),
  [Pakistan Observer](https://pakobserver.net/budget-2026-from-baby-formula-milk-to-electronics-over-3000-items-to-carry-18-sales-tax/)).
- **Reduced, exempt, zero:** Eighth Schedule reduced rates, Sixth Schedule exemptions, zero-rated items; 14% for
  local textile and leather sold by integrated retailers ([Odoo FBR module](https://apps.odoo.com/apps/modules/18.0/l10n_pk_fbr_pos_receipt)) **[verify]**.
  Keep rates per item and never hard-code.
- **Further tax (s.3(1A)):** 4% on taxable supplies to unregistered or inactive buyers (3% before Finance Act 2023).
  FBR proposed abolishing it in 2025 and the IMF refused ([Business Recorder](https://www.brecorder.com/news/40374481)).
  FY2026-27 status **[unverified]**: keep it a configurable percentage per buyer type.
- **Third Schedule (retail-price) goods:** tax is 18% of the printed retail price. STGO 8 of 2026 (7 Jul 2026)
  requires the retail price and the tax amount printed on packs in 56 categories (juices, soft drinks, tea,
  shampoo, detergents, cosmetics, biscuits, edible oil, chocolates, milk products, batteries, tyres,
  appliances…) ([ProPakistani](https://propakistani.pk/2026/07/07/fbr-orders-retail-price-sales-tax-printing-on-packaging-of-56-items/));
  Budget 2026 extends the regime to 3,000+ items. On the bill: the price is tax-inclusive and capped at MRP,
  tax shown = MRP × 18/118, and selling above MRP should warn.
- **Provincial sales tax on services** (repair shops, salons, restaurants):
  - Punjab (PRA) 16%; restaurants and several services 16% cash, **8% when paid by card, wallet or QR** from
    1 Jul 2026 (was 5%) ([ProPakistani](https://propakistani.pk/2026/07/03/punjab-increases-restaurant-card-payment-tax/)).
  - Sindh (SRB) 15%; restaurants 8% by card or QR ([pkrevenue](https://pkrevenue.com/sindh-imposes-15-sales-tax-on-restaurants-for-ty2025/)).
  - KP and Balochistan: **not checked**.
  - So the rate can depend on the payment mode: compute tax after the tender is chosen.
- **BL status:** M12 charges 18%, takes tax out of inclusive and Third Schedule prices, adds 4% further tax,
  warns on s.73 cash payments over Rs 50,000; provincial services tax is **not built**.

### 1.4 Pharmacy (Punjab Drug Sale Rules 2007, hosted by DRAP)
Source: [DRAP-hosted rules](https://www.dra.gov.pk/wp-content/uploads/2022/11/Punjab-Drug-Sale-Rules.pdf) (text extracted and checked).
- Purchase and sale records kept **3 years**, showing date; supplier or buyer name and address;
  **drug name, batch number, expiry date, quantity**; manufacturer. Bills, counterfoils and purchase invoices kept 3 years.
- A seller to a licence holder issues an **invoice and warranty** with the buyer's full name and address,
  signed and dated (pharma wholesalers).
- **Schedule B/D (narcotic, psychotropic, controlled)** sold only on a registered practitioner's prescription,
  original kept. Register fields: serial number, date of sale, **prescriber, patient**, drug, manufacturer,
  quantity sold, **batch number**, qualified person's signature, **quantity purchased and balance**.
- Storage conditions (refrigeration). "Medical store" licences cannot sell Schedule G drugs.
- **MRP is fixed by DRAP**: selling above is illegal, below is allowed, so "% off MRP" is common
  ([Arab News](https://www.arabnews.pk/node/1477186)).
- Other provinces assumed similar **[not individually verified]**.
- BL status: FEFO batches and the expiry list (M11); drug schedules and prescriptions **not built**.

### 1.5 Mobile phone shops (PTA DIRBS)
- Statuses: **PTA Approved**, **Valid but Not PTA Approved** (informal import), **Non-Compliant** (blocked within 60 days).
- Check: SMS the 15-digit IMEI to **8484** (about 10 paisa) or online
  ([ProPakistani](https://propakistani.pk/2018/05/11/pta-dirbs-explained-heres-how-you-can-avoid-getting-your-phone-and-imei-blocked-in-pakistan/),
  [Daily Capital](https://dailycapital.pk/check-phone-pta-approved/)).
- Shops record the IMEI on purchase (used phones: with the seller's CNIC) and on sale. Instalment (qist)
  selling is common ([Qist Bazaar](https://play.google.com/store/apps/details?id=com.tech.qistbazar), 100K+).
- BL status: IMEI tracking (M11). The 8484 check can be a pre-filled SMS intent (needs signal, no server).

---

## 2. How Pakistani shops actually work

- **Khata words:** جمع jama (received) / بنام banam (owed); "purana baqaya" = opening balance. Household khatas
  settle on salary day. Users want the khata top-to-bottom like paper, and a jama and banam total.
- **Payment modes:** cash dominates ([Nukta](https://nukta.com/cash-reigns-supreme-in-pakistan)) but QR grows fast:
  JazzCash went from about 0.9M to **1.7M merchants** in six months, about PKR 150bn a month in QR payments
  ([Digital Pakistan](https://digitalpakistan.pk/jazzcash-onboards-1-7-million-merchants-onto-raast/)); Raast passed
  1M QR merchants, with static/dynamic QR, alias, IBAN, request-to-pay and till codes
  ([Bank Alfalah](https://bankalfalah.com/business-banking/retail-payment-solution/raast-p2m-qr/),
  [Business Recorder](https://www.brecorder.com/news/amp/40384460)). Also Easypaisa, IBFT, card, and **cheques**,
  including post-dated cheques in wholesale; a bounced cheque can be criminal under **s.489-F PPC**
  ([KPJA paper](https://kpja.edu.pk/d11/sites/default/files/publications/Offence%20of%20dishonoring%20of%20cheque%20Muhammad%20Jamil%20Khan.pdf)).
- **Bill book / parchi:** carbon-copy bill books and handwritten parchis; users ask to photograph the parchi onto an entry.
- **Printers:** 58mm Bluetooth/USB printers cost about Rs 5,000–6,000 (e.g. Black Copper BC-58U,
  [PowerHouse](https://powerhouseexpress.com.pk/products/black-copper-bc-58u-thermal-receipt-printer)); 80mm at counters.
  Usable width 384 dots (58mm) and 576 dots (80mm) is standard ESC/POS knowledge, not sourced here.
  **Urdu cannot print as ESC/POS text**; it must go as a raster image (Posill sells on exactly this). BL already rasterises (M2).
- **Units:** kg with grams (users complain apps only take whole kg); **maund (mann) = 40 kg**, still used in grain
  markets; **seer ≈ 0.933 kg** ([maund](https://en.wikipedia.org/wiki/Maund_(unit)), [seer](https://en.wikipedia.org/wiki/Seer_(unit)),
  [PBS conversion factors](https://www.pbs.gov.pk/sites/default/files/agriculture/publications/agricultural_statistics_of_pakistan_2010_11/converstion_factors_2012.pdf));
  dozen, carton/box/packet/dabba; litres with decimals (petrol/diesel request); feet (printing trade request);
  pharmacy pack/strip/tablet.
- **Prices:** separate wholesale and retail prices; distributor schemes ("x+1 free") and short-expiry practices
  exist **[practice, no PK source found]**.
- **Overseas Pakistanis** keep khatas abroad and want SAR/AED/OMR/USD; DigiKhata supports them.
- **Roman Urdu** is how most reviews are written ("dobara login pr sara data clear"). Search must accept
  Roman spellings (atta/aata/آٹا, cheeni/chini).

---

## 3. Pakistani khata, billing and POS apps

Play figures scraped from the PK store with `google-play-scraper` on 2 Oct 2026.

### 3.1 The big four khata apps
- **DigiKhata** ([Play](https://play.google.com/store/apps/details?id=com.androidapp.digikhata), [site](https://digikhata.pk/)):
  5M+, 4.42★ from 211,517 ratings, v9.6.2. $2M seed 2021 from Telenor Velocity
  ([ProPakistani](https://propakistani.pk/2021/07/08/telenor-velocity-startup-digi-khata-raises-2-million-in-seed-funding/)).
  - Features: customer/supplier khata; Staff Book (attendance, salary, overtime, bonus); Cash Book, Bank Book,
    Expense Book; Stock Book with barcode and low-stock alerts; Bill Book (invoices and quotations on WhatsApp);
    multi-business; multi-user with view/edit/delete permissions; PIN or fingerprint lock; DigiCash wallet,
    DigiPOS (NFC), DigiQR, Smart Lending up to PKR 50,000; Windows/web (a 2025 review says desktop was switched off).
  - Pricing: free tier now online-only; **Pro Rs 790/month, Rs 1,850/quarter, Rs 5,500/year**
    ([App Store](https://apps.apple.com/pk/app/digikhata-money-manager/id1571599845)); offline and multi-device are Pro.
  - Complaints: forced online since May 2026 (146 of the newest 2,000 reviews mention offline, averaging 1.79★);
    paid but Pro not activated; repeated CNIC/KYC prompts ("apko cnic kyo chahiya? simple hisab kitab rakhna hai");
    stock book stuck loading; PDF/WhatsApp share hanging; archive removed; "no counter sale profit and loss option";
    "monthly sales record" missing after a Sep 2026 change.
  - Users want: Jameel Noori Nastaleeq font; Urdu or English reminder SMS; jama/banam wording; date-wise
    carry-forward in the cash book; a "Dual Unit System"; quantity-only khata lines (2020 request).
- **Easy Khata** (Bazaar Technologies) ([Play](https://play.google.com/store/apps/details?id=com.tech.bazaar.easykhata)):
  5M+, 4.44★ from 33,825, v7.0.1, no in-app purchases. 2.4M businesses in 2022 ([TechCrunch](https://techcrunch.com/?p=2284452));
  Bazaar has since moved to consumer grocery and bought Keenu ([Nukta](https://nukta.com/bazaar-technologies-eyes-profitability)).
  - Features: udhaar khata, cash in/out, WhatsApp/SMS reminders, PDF reports, fingerprint/PIN, internet backup,
    "Batwa" wallet, "live khata" share. **No stock or bill module** (Jul 2026 review).
  - Complaints: data lost after phone change or OTP failure (23% of its 1–2★ reviews); restores that change
    amounts; unreadable PDF fonts; rows hidden under the PDF footer; token-only WhatsApp support; no number change;
    "super slow at opening" (+763). Alleged Rs 20k bribe for a restore **[unverified]**.
  - Strength: still offline and free, so it is collecting DigiKhata and CreditBook refugees
    ("Digikhata app And Creditbook apps are useless in Pakistan because they can't be used without internet", May 2026).
  - Users want: stock and P&L; vendor-filtered PDFs; search in the cash book; fast loose-item entry
    ("Who will spend 3 minutes to enter an entry for 1 kg of onions").
- **Rupin, formerly Udhaar Book** (Toko Lab, YC; $6M seed 2021, [Dawn](https://www.dawn.com/news/1656795))
  ([Play](https://play.google.com/store/apps/details?id=com.oscarudhaarapp), [rupin.pk](https://rupin.pk), [udhaar.pk](https://udhaar.pk)):
  5M+, 4.31★ from 41,881, v32.9.2.
  - Features: khata and personal khata, cash book, purchasing, inventory with low-stock and top sellers, P&L,
    POS, an invoice maker sold as "GST and Sales Tax compliant" with payment QR and bank details, payroll and
    attendance, Rupin Wallet (SBP e-money pilot: QR, JazzCash, Easypaisa, Raast, IBFT), web version.
  - Paid monthly SMS packages (one buyer says messages still weren't sent).
  - Complaints: Aug–Sep 2026 redesign broke the cash book (in/out view gone, one year of history only); a zero
    discount line printed on bills (customers then ask for a discount); backups failing with "connectivity problem";
    unusable at about 180 customers (2021, +252); "200000 shows 2000" (2025, +103); embarrassing automatic SMS to
    relatives (+294); ad flood (May 2026); total-profit view removed (Jun 2025, Roman Urdu); font "bahut bareek" (too thin).
  - Users want: select-all customers for reminders; automatic daily/weekly reminders; automatic SMS on new udhaar;
    Urdu bill messages; a bill-number box; a roznamcha (daybook) view.
  - Package name contains "oscar"; any link to Oscar POS **[unverified]**.
- **CreditBook** (Karachi; $11M Tiger Global round 2021, [TechCrunch](https://techcrunch.com/2021/12/16/tiger-global-backs-fintech-creditbook-in-first-pakistan-investment/))
  ([Play](https://play.google.com/store/apps/details?id=com.creditbookpk.creditbook), [site](https://www.creditbook.pk/)):
  5M+, 4.09★ from 25,425, v9.1.6. Website is now a lender (FinanceNow, SECP licence SECP/LRD/86/CBFSPL/2022-103).
  - Features: khata with an **udhaar date and a "wasooli" (collection) date**; labels "Aapne Diye / Aapne Liye";
    free SMS/WhatsApp reminders; CashBook, StockBook, BillBook; mobile load; multi-device and multi-business;
    English, Urdu, Sindhi, Pashto, Punjabi. Early versions sent reminder SMS **from the shopkeeper's own SIM**.
  - Developer reply: "The app is now online-only due to recent updates and data security requirements, so
    offline access is no longer available." Offline was removed in Dec 2025 (+74, +90 reviews).
  - Complaints: mass outage about 2–3 Mar 2026; balances changing by themselves (blamed on sync); debit/credit
    columns reversed in PDFs; the money direction reversed in an SMS (2021); one-tap reminder removed; contacts no
    longer readable (Play policy); automatic update lost data.
  - Users want: time on bills; daily total of items sold; Windows version; Excel export; change-number option;
    Balochi language.

### 3.2 Smaller Pakistani and Urdu apps
| App | Stats | What it is | Worth taking |
|---|---|---|---|
| [Business Khata](https://play.google.com/store/apps/details?id=com.sajidhadi.businesskhata) ([site](https://businesskhata.com/)) | 1K+, 4.75★, IAP Rs 200–3,600 | Feature-rich 2026 app, offline with sync | Item-wise **and amount-wise** sale; kg/g/pcs/dozen/custom with weight pricing; fixed or % fees/taxes, inclusive or exclusive; payments split across unpaid bills oldest first; photo and voice notes on entries; **30-day trash**; ESC/POS 58/80mm Bluetooth/Wi-Fi with auto-cut; repeating reminders |
| [Easy Karyana](https://play.google.com/store/apps/details?id=com.amirsolutions.easykaryana) | 1K+, 4.73★ | Kiryana POS in Roman Urdu, offline | **Carton calculator** (per-piece cost); **end-of-day net-cash calculator**; cash / udhaar / online sale with a breakdown report; daily/weekly/monthly profit; dark theme |
| [Daily Khata](https://play.google.com/store/apps/details?id=com.mdxon.dailykhata) | 10K+, 4.64★ | Offline with cloud sync, multi-company | A recently-deleted bin |
| [Urdu Khata Book](https://play.google.com/store/apps/details?id=com.wssolutions.khatta_book) | 100K+, 4.2★, ads | Simple Urdu ledger with trade categories (doodh dahi, ata chaki, installment shop, mandi) | Hated for ads and for keeping only 30 days; users want a jama and banam total |
| [Hysab Kytab](https://play.google.com/store/apps/details?id=com.jbs.hk.c) | 500K+, 3.92★, last update Oct 2023 | Personal finance | Abandoned; backup/restore failures; "i want offline but its only required account" |
| [Hisaab Kitaab: Expense Manager](https://play.google.com/store/apps/details?id=hisaab_kitaab.shahkar.com) | 10K+, 4.0★ | Personal | Minor |
| [Asan Billing](https://play.google.com/store/apps/details?id=com.asanbilling.app), [Pak Billing Restaurant POS](https://play.google.com/store/apps/details?id=com.pakbilling.restaurantpos) | small | Restaurant POS | Minor |

### 3.3 POS apps and software used in Pakistan
- **Xona POS Billing** ([Play](https://play.google.com/store/apps/details?id=com.xonasolutions.easyinvoicemaker)): 10K+, 4.53★,
  IAP Rs 250–8,000. Camera barcode; 58/80mm Bluetooth printing (sale and return slips, custom header); returns
  restore stock; daily/monthly/yearly and best-seller reports. Complaints: an 8-hour trial; price.
- **Quickro POS** ([Play](https://play.google.com/store/apps/details?id=com.app.quickropos), quickro.pk): 1K+, 4.27★,
  Rs 550–13,300. Offline-first; built-in double entry; multi-store with own stock and prices; supplier balances;
  Cash/Card/QR; Google Drive backup ("your data stays on your device unless you back it up").
- **Offline Shop** ([Play](https://play.google.com/store/apps/details?id=com.binaryscript.offlineshop)): 10K+, 3.77★,
  Rs 1,100–14,400. Fully offline; CSV import/export; margins; stock adjustments with a reason; A4 or thermal.
  1★ reviews for forcing a subscription first; then added a free plan of 50 orders a month.
- **Posill / Custom Bill Print** (Indian, popular in PK) ([Play](https://play.google.com/store/apps/details?id=com.billing.system)):
  100K+, 4.39★. Prints **Urdu as an image** "without thermal printer compatibility issues"; XPrinter, Rongta,
  Hoin, Goojprt, Epson; offline billing with later sync. Complaint: no multiple prices.
- **Zapbill** ([Play](https://play.google.com/store/apps/details?id=com.takinex.zapbill)): 10K+, 4.21★. Offline; USB/Bluetooth/Wi-Fi printers.
- **EKhata** ([ekhata.ai](https://ekhata.ai), [Play](https://play.google.com/store/apps/details?id=ai.ekhata.mobile), Jul 2026):
  cloud AI "SIFR" in Urdu, Roman Urdu and English; voice entries ("chai ka kharcha 500 cash likh do") with a
  confirmation card and one-tap Undo; receivables ageing; claims FBR DI ready and "PRA/SRB aware". Needs a server.
- **Oscar POS** ([oscar.pk](https://oscar.pk/)): cloud POS for retail, restaurants, pharmacy; price not published.
- **Mint POS:** "FBR-integrated, offline-first", LAN counters, from US$25 ([Capterra](https://www.capterra.com/p/10045019/MintPos/)).
- **HysabOne** (cloud SaaS, PKR 3,499/month, 14-day trial; markets "Urdu + FBR", [blog](https://blog.hysabone.com/?p=12)):
  [pharmacy](https://hysabone.com/industries/pharmacy/) — salt/formula search, batch tracking, near-expiry alerts,
  Urdu UI; [mobile shop](https://hysabone.com/industries/mobile-shop/) — IMEI per phone, IMEI search and history,
  repair job cards, **instalment plans with down payment and reminders**, warranty claims, trade-ins, used phones.
- **MediStock** (Indian; PK use **[unverified]**, [Play](https://play.google.com/store/apps/details?id=com.asharinfotech.medistock)):
  low-stock and expiry alerts; a **daily wishlist / order list sent to distributors**.
- **Pharmacy POS** (Toposfy, 100K+): reviewers want a desktop version.
- **CashBook** (Obopay, India, listing in Roman Urdu) ([Play](https://play.google.com/store/apps/details?id=com.cashbooknew)):
  5M+, 4.48★. Free for 5 years, then put entries behind a paywall (IAP up to Rs 158,400); most new 1★ reviews are about it.

### 3.4 B2B ordering apps (all need a server; shown for context)
| App | Stats | Status and complaints |
|---|---|---|
| [Tajir](https://play.google.com/store/apps/details?id=com.tajir.tajir) (YC W20, $17M Series A) | 500K+, 4.24★ | Running. "Lays k har carton peechy 60 se 80 rupay mehnga"; short-dated stock ("1/4 life wholesaler ki, 3/4 retailer ki"); short delivery; **invoice price differs from app price** |
| [Retailo](https://play.google.com/store/apps/details?id=com.app.retailerapp) | 100K+, 3.77★ | 2023–24: out of stock, not in my city, Rs 5,000 minimum. Distribution reportedly shut **[unverified]** |
| [Dastgyr](https://play.google.com/store/apps/details?id=com.dstgyr.dastgyr) | 100K+, 4.10★ | Late-2024 reviews: service stopped; delivery charges Rs 100–300 |
| Bazaar ([app](https://play.google.com/store/apps/details?id=bazaar.tech.com), [site](https://www.bazaartech.com/)) | 1M+ | Moved to consumer grocery plus Bazaar Pro |
| [Unilever Kiryana](https://play.google.com/store/apps/details?id=com.unilever.dtt.pk) | 50K+, 4.06★ | "barely works on weaker cellular networks"; distributors cancel app orders |
| [Dukan.pk](https://play.google.com/store/apps/details?id=pk.dukan) | 500K+, 4.31★ | CNIC verification, payout delays, "Rs.5000/Mon is so expensive", "no POS feature" |

Offline lesson: a reorder list sent to the distributor on WhatsApp, and a record of the quoted rate checked against
the invoice rate on receipt, need no server.

### 3.5 Indian apps seen from Pakistan
- **Vyapar** still runs [vyapar.pk](https://vyapar.pk/) and a Facebook page "Vyapar App - Partners for Pakistan"
  ([link](https://www.facebook.com/p/Vyapar-App-Partners-for-Pakistan-61551838270355/)), but Play reviews since
  May 2025 say licences can't be renewed and the app stopped working in Pakistan ("pakistan ma phla chlti thi india
  pak war ka bd bnd kr dii", 2025-09-22; "is there any way to renew the license in pakistan", 2025-07-26, +65;
  a 3-year licensee told "Due to the current situation of…", 2026-05-07) [R, not officially confirmed].
  Urdu was asked for twice (2022-11-24, 2025-05-15). A Punjab user asked for a stock-overdraw warning after
  selling 700 kg against 600 kg (2021-11-19).
- **Khatabook** demanded an Indian OTP from early 2024 ("only verify Indian Number… all my ledgers… lost",
  2024-08-23); "not working in Pakistan" (2026-06-19). A CreditBook review says "after Khatabook was banned in
  Pakistan" (2024) **[unverified]**.
- The scraper returns PK-store pages for both, but it does so even for apps not sold in a country, so real
  availability is **[unverified]**.
- ProPakistani's "top 10 billing software in Pakistan" lists Vyapar and mentions no Urdu, FBR or PKR features
  ([link](https://propakistani.pk/how-to/top-10-free-billing-software-in-pakistan/)). **No review in any app asked for FBR integration.**

---

## 4. Mistakes the competition made (do not repeat)

- Taking offline away, or adding a forced login, OTP or KYC after users have years of data (DigiKhata, CreditBook, Hysab Kytab).
- Free-to-paid switches that block entering or **viewing** existing data (CashBook, RecordBook, DigiKhata, myBillBook); trials too short to judge (Xona 8 hours, Vyapar 7 days).
- Redesigns that move or drop familiar views (Rupin cash in/out, DigiKhata archive, Vyapar standard view) or change PDF formats without warning.
- Ads inside a ledger (Urdu Khata Book); history-limited free tiers (30 days; one year of cash book).
- Restores that silently change balances (EasyKhata "31000 hogaye 30500"); always show a before/after reconciliation.
- Automatic SMS with no per-customer off switch (OkCredit +3,292, Khatabook +993, Rupin +294).
- Letting customers write into the shop's ledger (OkCredit +787).
- Three different balances on three screens (OkCredit +258); debit/credit columns swapped in a PDF (CreditBook).
- A zero discount line on the bill; no time or bill number on the bill; text too small; mixed-language screens.
- Sending bills from the vendor's own number, with branding or a watermark (Vyapar).
- Support that only issues tokens or auto-replies; asking users to install remote-access software (Vyapar).

---

## 5. Review-mining numbers

Google Play reviews pulled with `google-play-scraper` on 2 Oct 2026 (newest and most-relevant sorts, 1–3★).
Percentages are keyword matches over 1–2★ reviews, so they are lower bounds.

**1–2★ reviews analysed:** Vyapar 2,246 · Khatabook 1,240 · myBillBook 1,134 · OkCredit 1,242 · EasyKhata 898 ·
DigiKhata 1,101 · CreditBook 696 · Rupin 999. Plus the 6,000 newest Vyapar reviews of every rating for Pakistan and Urdu mentions.

**Vyapar themes (share of 1–2★):** price/subscription/paywall 17% (14% to 2024 → **24%** in 2025–26) · support 13%
(→ 17%) · slow/hanging 8% · desktop 5% · licence per device 5% · reports 5% · sales calls and nags 4% · edit/delete 4% ·
printing 3% · stock 3% · data loss/backup 3% · sync 2%.

**Vyapar theme counts (1–3★):** Excel import/bulk edit 86 · desktop vs mobile parity 64 · roles/permissions 52 ·
backup/restore 52 · no iOS 42 · features moved up a plan 39 · barcode 38 · no journal entry 35 · per-device licence 27 ·
"5 invoices a week" 23 · branding/watermark 23 · thermal printer 23 · sales calls 19 · duplicate party/item 18 · negative stock 12.

**Most-upvoted reviews worth remembering:** Vyapar sync (3★, +1,447); Vyapar split payments wrong in exports and units
as "0.4756" (2026-09-04, +403); Vyapar thermal printer + no support (2019, +375); Khatabook PDF attachments request (+4,383);
Khatabook delete password + fingerprint lock (+2,250); Khatabook list jumps to top after edit (+1,976); OkCredit
auto-messages can't be switched off (+3,292); OkCredit bulk payment requests (+2,928); myBillBook payment mode not recorded
on credit receipts (+1,519); myBillBook old bill's address changes when the party is edited (+550); DigiKhata "offline only
in premium" (2026-05-16, +228); DigiKhata 249 one-to-two-star reviews in May 2026 alone.

Third-party review sites used: [Capterra Vyapar](https://www.capterra.com/p/180579/Vyapar/reviews/),
[Capterra.in Vyapar](https://www.capterra.in/reviews/180579/vyapar), [Trustpilot Vyapar](https://www.trustpilot.com/review/vyaparapp.in),
[Software Advice](https://www.softwareadvice.com/accounting/vyapar-profile/reviews), [Techjockey Vyapar](https://www.techjockey.com/reviews/vyapar),
[Capterra myBillBook](https://www.capterra.com/p/202732/FloBooks/reviews/), [Trustpilot myBillBook](https://www.trustpilot.com/review/mybillbook.in),
[Trustpilot Khatabook](https://www.trustpilot.com/review/khatabook.com), [Techjockey OkCredit](https://www.techjockey.com/reviews/okcredit),
[itforsme alternatives](https://www.itforsme.in/best/vyapar-alternatives-india).

---

## 6. Detail notes on other apps

### 6.1 Zoho Books / Invoice (official help; "(u)" = uncertain)
- **Reports catalogue (70+)** ([help](https://www.zoho.com/books/help/reports/)): Business Overview (P&L, horizontal P&L,
  Cash Flow, Balance Sheet, 8 performance ratios, cash-flow forecasting, movement of equity); Sales (by customer, item,
  salesperson; Sales Summary; order fulfilment); Inventory (summary, aging, adjustments); valuation (FIFO cost lot tracking,
  **ABC classification**); Receivables (customer balance, AR aging summary/details, invoice details, bad debts…);
  Payments received (time to get paid, credit notes, refunds); Payables; Purchases and expenses; Accountant (GL, journal,
  trial balance, DayBook (India)); Activity (audit trail).
- **Columns worth copying:**
  - AR Aging: buckets Current, 1-15, 16-30, 31-45, >45 (configurable count and length); aging by invoice or **due date**;
    group by salesperson; show by amount or invoice **count**; drill to details (Date, Transaction#, Status, Customer,
    Age, Amount, Balance Due).
  - Customer Balance Summary: Customer, Invoiced, Received, Closing Balance; "exclude zero balances".
  - Invoice Details: Status, Invoice Date, Due Date, Invoice#, Customer, Total, Balance; advanced filters (field + comparator + value).
  - Sales by Salesperson: invoices and credit notes in separate sections, an "Others" bucket.
  - Time to Get Paid: 0-15, 16-30, 31-45, >45 days.
  - Inventory Summary: Item, SKU, Reorder Level, Qty Ordered, Qty In, Qty Out, Stock on Hand, Committed, Available.
  - Stock Summary: Opening, In, Out, Closing. Stock Movement: Date, Txn#, Item, Type, Qty, In/Out, Source, Destination.
  - Inventory Aging: 1-3, 4-6, 7-9, 10-12, 13-15, >15 days (configurable), All/Moving/Not Moving.
  - ABC: by usage value (qty sold × cost) or quantity, user thresholds.
  - Audit trail: Time, Activity, Description; filters by date, module, customer, user, action; **View Versions → Compare**
    (yellow modified, red removed, green added). In India it **cannot be disabled** (MCA mandate from 1 Apr 2023)
    ([link](https://www.zoho.com/in/books/audit-trail/)).
  - Every report: filters, group by, show/hide/reorder columns, save as custom report; layout density, A4/Letter,
    portrait/landscape, a **dynamic font for right-to-left scripts**, header with "generated by / at", page numbers;
    PDF/XLS/XLSX/CSV export with optional password; favourites (star) and report search ([manage reports](https://www.zoho.com/books/help/reports/manage-reports.html)).
- **Invoice lifecycle:** Draft, Sent, Viewed, Partially Paid, Paid, Overdue, Void. Drafts appear in no report.
  Editing a Sent invoice needs a preference; total can't drop below what's paid (u). Record lock (with reason) and
  transaction (period) lock per module with a mandatory reason; items dated *on* the lock date stay editable (gotcha);
  negative stock blocks locking ([period lock](https://www.zoho.com/books/help/accountant/transaction-lock.html),
  [record lock](https://www.zoho.com/books/help/settings/customization/record-locking.html)).
  **Void** needs a reason, keeps the record out of reports, unlinks payments to customer credit, can be restored to draft;
  **Delete** is permanent and blocked while payments exist ([other actions](https://www.zoho.com/books/help/invoice/other-actions.html)).
  Clone, Make Recurring, Create Credit Note, attachments (5 × 5 MB), bulk actions, adjustment (round-off) line, discount per
  line/bill before or after tax. **Write Off** with date and reason → Bad Debts report; Cancel Write Off.
- **Payments:** split payment at invoice creation; one payment across many invoices with the **excess** kept as credit;
  advances applied later; "Dissociate & Add as Credit"; early-payment discount in the term; Sales Receipt (sale + payment in one).
- **Reminders:** manual (Overdue and Sent templates) and 3 automatic rules (N days before/after due); **Expected Payment
  Date** that holds reminders; stop reminders per invoice or customer.
- **Credit limit:** global mode "Restrict" or "Warn and allow"; the pop-up offers **Update Credit Limit and Save** or Proceed
  ([help](https://www.zoho.com/books/help/contacts/credit-limit.html)).
- **Opening balance write-off** with a reason; **late fees** as % or fixed after N days, a separate LF- invoice, per-customer opt-out.
- **Inline creation:** "+ New Customer", "+ Add New Item", "+ New Tax", "+ New Payment Term", "Manage Salespersons"
  inside the invoice ([new invoice](https://www.zoho.com/invoice/help/invoice/new-invoice.md)); customer **Remarks** shown
  while billing; payment terms Net 15/30/45/60, end of month, on receipt, custom.
- Tip: any Zoho help page can be fetched as clean markdown by replacing `.html` with `.md`.

### 6.2 Marg ERP (care.margcompusoft.com)
- Fast/Medium/Slow/Non-moving by **number of sale entries in N days** with user thresholds; filters rack, company, rate
  ([link](https://care.margcompusoft.com/margerp/inventory-reports/1930/1/how-to-view-fast-and-slow-moving-item-report-in-marg-software)); Dump Stock (unsold N days).
- Re-order Management: 12 methods (sales × days − stock, min/max, zero/negative stock, shortage list, average, last
  year's same month, "MARG formula"); subtract pending POs; round to minimum order; respect schemes; F6 best supplier;
  POs split by supplier; expiry and near-expiry returns from the same screen
  ([link](https://care.margcompusoft.com/margerp/re-order-management/2343/1/what-is-the-process-of-re-order-in-marg-software)).
- Hourly sales with "Issue Time management" ([link](https://care.margcompusoft.com/margerp/inventory/149679/1/how-to-view-time-wise-report-in-marg-software)).
- Bill GP on Ctrl+F7, "Today's Gross Profit", item GP loss-only filter, party- and doctor-wise GP; hide Today's GP per user
  ([link](https://care.margcompusoft.com/margerp/management-reports/1729/)).
- Cashier management: salesmen bill, a cashier collects, paid bills lock ([link](https://care.margcompusoft.com/margerp/transaction-data-entry/3543/)).
- Locks: freeze a voucher type to a date; auto-freeze older than N days; per-user "modification allowed up to N hours";
  edit-allowed days per voucher type; no edits to cashier-paid bills ([link](https://care.margcompusoft.com/margerp/password-and-powers/1828/)).
- Audit: "Bill Value Changes" (edited/deleted/cancelled above a minimum difference), user audit trail, operator logbook,
  **random stock checking** of N items ([link](https://care.margcompusoft.com/margerp/audit-trail/172889/)).
- Cancel needs a remark; returns "Select from Sold" offers only batches sold to that customer, with a reason.
- Credit control: warning and hard limits by **amount, number of bills and days**; temporary limit with expiry; limits
  suggested from history; **billing stops after a bounced cheque**
  ([link](https://care.margcompusoft.com/margerp/rate-and-discount-master/38672/)).
- **Bill tagging**: a party's open bills given to a salesman as a numbered collection sheet, marked paid or "shop closed"
  on return ([link](https://care.margcompusoft.com/margerp/bill-taging-for-collection/1995/)).
- Party master (F2): balancing method bill-by-bill / FIFO / on account; credit days, interest %, credit limit; area,
  route, salesman; drug licence and expiry; party category; "freeze up to" date; narcotic/Schedule-H permission.
- Salt master with substitutes ([link](https://care.margcompusoft.com/margerp/inventory-master/38694/)); bonus schemes
  (Full / Half / All, custom tables); bill-value discount slabs; Hold/Ban a batch; expiry ticker.

### 6.3 TallyPrime (help.tallysolutions.com)
- Bills Receivable: Date, Ref, Party, Pending, Due On, Overdue days; age by bill or due date with editable slabs;
  Alt+B settles bills ([link](https://help.tallysolutions.com/manage-receivables-outstanding-tally/)).
- Stock Ageing 0-45 / 45-90 / 90-180 / 180+ by purchase, expiry or manufacturing date ([link](https://help.tallysolutions.com/stock-ageing-analysis-report-tally/));
  Movement Analysis; Reorder Status (Closing, PO pending, SO due, Net available, Reorder level, Shortfall, Min order,
  Order to be placed) ([link](https://help.tallysolutions.com/reorder-stock-items-reorder-status-and-reorder-quantity/)).
- Ratio Analysis (GP%, NP%, current, quick, inventory turnover, receivable days) → **Ledger Payment Performance**
  (delay per bill, average delay per customer) ([link](https://help.tallysolutions.com/ratio-analysis-tally/)); cash-flow projection.
- F7 Show Profit on Day Book / Sales Register per invoice; Ctrl+J exception reports (negative stock, negative cash,
  overdue, cancelled, post-dated); saved views; new column to compare periods; drill-down everywhere; Stock Query card.
- Vouchers: Cancel (Alt+X) keeps the number; Delete (Alt+D) either renumbers or keeps the gap and later offers unused
  numbers (Ctrl+Alt+U); Duplicate (Alt+2); Insert (Alt+I); optional and post-dated vouchers
  ([numbering](https://help.tallysolutions.com/use-voucher-numbering-methods/)).
- **Edit Log** (Release 2.1+): every version with activity, user, time; differences in red; cannot be printed or exported
  ([link](https://help.tallysolutions.com/tracking-modifications/)). Period lock per role ("days allowed for back-dated vouchers").
- Interest: rate slabs after due date + grace, posted by debit note ([link](https://help.tallysolutions.com/interest-calculation-tally/)).
- Inline creation: Alt+C on any field opens the full master (nested).

### 6.4 myBillBook (knowledge.mybillbook.in)
- **Cancel** (sales invoices): mandatory reason (Order Cancelled, Duplicate Entry, Wrong Entry, Other); irreversible; number
  kept; PDF watermarked CANCELLED; stock back; out of returns and P&L but counted as "documents issued"; Day Book shows it as
  Cancelled with zero values; if paid at creation, choose auto credit note or move payment to the party balance; blocked
  while a linked payment exists; a cancelled invoice can still be duplicated
  ([link](https://knowledge.mybillbook.in/articles/5125143-how-to-cancel-an-invoice-in-mybillbook)).
- **Delete** leaves a numbering gap; recoverable for a limited time ([link](https://knowledge.mybillbook.in/articles/5679263-how-to-recover-deleted-invoices-in-mybillbook));
  parties can only be made inactive. **Edit** blocked if a payment is linked or an e-invoice exists.
- Reports: Bill Wise Profit (Date, Invoice, Party, Invoice amt, Sales amt, Purchase amt, Profit); Sales Summary staff-wise
  (Created By; tabs Cash/Credit/All and Paid/Unpaid/Cancelled); Receivable Ageing with **"Not yet due"** and overdue buckets,
  WhatsApp reminder per row ([link](https://knowledge.mybillbook.in/articles/9535668-how-to-monitor-and-manage-receivables-and-payables-efficiently));
  Rate List; Item Report by Party; Party Report by Item; Serial items sold/unsold; stock value 4 ways (cost or sale price,
  with or without tax); Daily/Weekly Summary (sales, collections, expenses, profit)
  ([link](https://mybillbook.featurebase.app/en/help/articles/9707273-comprehensive-financial-reporting-daily-summary-balance-sheet-and-pandl-statement)).
- **Last 5 prices** for a repeat customer over 365 days ([link](https://knowledge.mybillbook.in/articles/3253036-how-to-view-last-5-item-prices-for-repeat-customers)).
- **Payment-In Discount** posted as discount allowed ([link](https://knowledge.mybillbook.in/articles/9372066-how-to-record-a-payment-in-discount-in-mybillbook)).
- Party form: Name*, type, category, mobile, PAN/tax ID, email, **opening balance with "I Receive / I Pay"**, billing
  and several shipping addresses, **credit period (number + unit) and credit limit**, contact person, date of birth,
  custom fields, bank/UPI; warns **"One or More Party exists with same number. Ignore to create anyway."**; Save / Save & New.
- Item form: name, category, sale and purchase price each with/without tax, tax, unit + alternate unit with conversion,
  opening stock, low-stock level, item code with auto barcode, MRP, **wholesale price with minimum quantity**, default
  discount, custom fields, batch OR serial.
- Transporter copy without prices; Original/Duplicate/Triplicate labels.

### 6.5 Swipe (community.getswipe.in)
- Cancel moves the invoice to a Cancelled tab, deletes its payments, returns stock, and can be **restored**; delete only
  from the Cancelled tab ([1474](https://community.getswipe.in/t/1474), [304](https://community.getswipe.in/t/304)).
- Deleted payment numbers never reused; edit blocked if the new total is below what's paid; Duplicate makes an editable
  copy ([1177](https://community.getswipe.in/t/1177)); per-invoice Activity tab, admin only ([1234](https://community.getswipe.in/t/1234)).
- Profit reports per bill, item, category, customer, with a choice of "purchase price at sale" or "current purchase
  price"; FIFO costing ([2512](https://community.getswipe.in/t/2512)). "Created By" column and filter; column chooser;
  report links with a PIN (server).

### 6.6 Khatabook and OkCredit
- Khatabook: entries editable (amount, date, bill photo) or deletable; deleted entries and customers restorable;
  **Data Lock** PIN for edit/delete separate from App Lock ([help](https://khatabook.com/help/en)); per-customer SMS
  language; bulk reminders with preview; collection date with automatic reminders the day before and on the day (server);
  IVR "Secret Call" (server). Inline party: name + optional phone or contact pick.
- OkCredit: per-entry SMS receipt; **free plan sends from the phone's own SIM** ([pricing](https://okcredit.in/pricing));
  per-customer off switch; monthly auto-reminder; defaulter list; monthly collection report; edit entries but not the date.

### 6.7 BUSY (partial)
- Critical level per item and warehouse; at sale time No Action / Warning / Don't Allow; "Live and Dead Stock, Slow
  Moving Items" ([link](https://busy.in/accounting-software/inventory-management/)); salt search; shelf-life alert.
  Voucher edit/cancel rules and display-menu names not researched.

---

## 7. What Bazaar Ledger already has (checked in the code, 2 Oct 2026)

- **Reports screen** (`lib/features/reports/reports_screen.dart`): 15 report kinds — Profit and Loss, Sales tax,
  Tajir Dost, Sales by day, Receivables (Udhaar by age), Payables (Owed to suppliers), Trial Balance, Balance Sheet,
  Expiry, Purchase register, Sales by item, Expenses, Cash Book, Day Book, Stock value — plus the party statement
  (`packages/pk_reports/lib/src/builders.dart`). **Only four periods** (`enum _Span { today, thisMonth, lastMonth, thisYear }`;
  Cash Book and Day Book default to today). No custom range, no filters, no sorting, no charts. Export: CSV (Excel-safe,
  BOM for Urdu) and A4 PDF with the Urdu font fallback.
- **Quick-add from the bill (M32, commit 3e1f50a):** an item a search or scan can't find opens `quick_item_sheet.dart`
  with the name or code filled in — name, barcode, code, sale price, unit, cost (for whoever may see costs), opening
  stock — and **checks for look-alike items ("twins") before saving**, with "add anyway". A customer name nobody matches
  is offered as a new customer from the party picker on the tender sheet, without leaving the bill.
- **Bills:** posted bills are immutable and undone by reversal (M5-VOID-01); void and partial return from the receipt
  screen; gap-free numbers per firm and fiscal year; reprint is "a deliberate act through a different door"; receipt
  shared as PDF; sales list shows voided bills struck through. Not seen: duplicate/clone, cancel reason codes,
  CANCELLED watermark, per-bill history view, bill search by party/amount.
- **Hidden, not deleted:** Settings → Hidden brings archived items and parties back (M5-RECYCLE-01); nothing is ever
  destroyed (six-year retention).

---

## 8. Evidence log: Vyapar

### 8.1 How the Vyapar help pages were found
`vyaparapp.in/guides` is rendered by JavaScript, so its guide list is invisible to fetchers. The full list comes from the
Yoast sitemap: `https://vyaparapp.in/sitemap_index.xml` → `page-sitemap.xml` (819 URLs; 127 under `/guides/`, `/videos/`,
`/use-cases/`). Each guide page carries numbered steps with screenshots at
`https://vyaparapp.in/v/z/wp-content/uploads/2026/03/Step-NN_*-scaled.webp` (desktop app, March 2026 build).

### 8.2 Pages read, and what each verified
| Page | Verified |
|---|---|
| [Transaction reports guide](https://vyaparapp.in/guides/how-to-check-transaction-reports-in-vyapar-app) | The transaction report list; Sale, Day Book, All Transactions, P&L, Bill Wise Profit, Sale Aging, Cash Flow, Balance Sheet screens (13 screenshots); FAQ: deleted transactions only in Recycle Bin; **no column customisation** |
| [P&L guide](https://vyaparapp.in/guides/how-to-check-profit-and-loss-report-in-vyapar) | Vyapar vs Accounting view; gross then net profit; other income included; item-wise P&L is a separate report |
| [Balance sheet guide](https://vyaparapp.in/guides/how-to-check-your-balance-sheet-in-vyapar) | Custom period, horizontal/vertical toggle, PDF/XLS |
| [Stock guide](https://vyaparapp.in/guides/how-to-manage-stock-inventory-in-vyapar) | Stock Summary screenshot (filters and columns); the Item/Stock report list as on desktop; item screen with Adjust Item; adjustment with reason |
| [Low stock guide](https://vyaparapp.in/guides/how-to-set-a-low-stock-alert-in-vyapar) | "Min Stock to Maintain" per item; pop-up during sale; red flag in the item list; Low Stock Report exportable |
| [Batches/serials guide](https://vyaparapp.in/guides/how-to-add-item-batches-serial-numbers-in-vyapar) | Batch (MRP, batch no, mfg, exp, size, qty) OR serial per item, never both; premium; selection at sale; printed on the invoice |
| [Expenses guide](https://vyaparapp.in/guides/how-to-add-and-manage-expenses-in-vyapar-app) | Expense report screenshot (columns, filters, Graph/Excel/Print); the Taxes, Expense, Order and Other Income report lists |
| [GST guide](https://vyaparapp.in/guides/how-to-manage-gst-compliance-and-taxation-in-vyapar-app) | GST report list (GSTR 1, 2, 3B, 9, Sale Summary by HSN, SAC Report); GSTR-1 screen (JSON/XLS/Print, Sale and Sale Return tabs) |
| [Tax invoice guide](https://vyaparapp.in/guides/how-to-create-tax-gst-invoices-in-vyapar-app) | Sale form (Customer*, Phone No., BAL under the name, billing address, invoice number/date, payment terms, due date, state of supply, line columns); **Preview screen with share targets, theme list, Download PDF, thermal and normal print** |
| [Reminders guide](https://vyaparapp.in/guides/how-to-send-payment-reminders-in-vyapar) | Template with [Party Name], [Amount], [Business Name], Reset Default; per-party WhatsApp/SMS; **bulk reminder screen** (tick list, sortable, "Send Reminders in Bulk"); free SMS; overdue status needs due dates |
| [Due dates guide](https://vyaparapp.in/guides/how-to-add-due-dates-on-invoices-in-vyapar) | Party detail screen with the Status column (Overdue N Days, Partial, Used, Unused) |
| [Recurring invoice guide](https://vyaparapp.in/guides/how-to-create-a-recurring-invoice-in-vyapar-app) | Repeat every N weeks/months on a day, start/end, pause; "Sale (Repeating)" tag with next due date; delete "this invoice only / this and all future" or Pause instead; **needs sync login** |
| [Transaction messages guide](https://vyaparapp.in/guides/how-to-enable-and-send-transaction-messages-in-vyapar) | Automatic messages for Sale, Purchase, Payment-In, Sale Return; current balance and web link options; WhatsApp first, SMS fallback; own-WhatsApp option; free |
| [Multiple devices guide](https://vyaparapp.in/guides/how-to-use-vyapar-app-on-multiple-devices) | Sync is premium; a licence per device; internet needed; roles limit access to profit reports |
| [Offline billing guide](https://vyaparapp.in/guides/how-to-make-bills-offline-in-vyapar) | Turning sync off to bill offline |
| [POS guide](https://vyaparapp.in/guides/how-to-do-pos-billing-with-vyapar) | Desktop-only POS (Alt+D); barcode and direct scan; thermal 2/3/4 inch; EDC machines; USB/Bluetooth scale (contradicts the FAQ) |
| [FAQ](https://vyaparapp.in/faq) | Creditor/debtor list = All Parties filtered; outstanding bills = All Transactions filtered unpaid; bad debt = discount during payment; waste = Adjust Item; estimates don't move stock; closing stock excludes tax; year close: change prefix or start fresh; licence asked again after device change |
| [Complete feature list blog](https://vyaparapp.in/blog/vyapar-app-complete-feature-list-all-about-your-favorite-billing-software/) | One-line description of every report; every setting (transaction, item, party, print, SMS, reminder, backup, utilities) |
| [Free vs paid blog](https://vyaparapp.in/blog/vyapar-free-vs-paid-mobile-app/) | Paid = multi-device sync, no Vyapar branding, more reports (GST, profit), multi-firm, TCS/TDS, marketing |
| [AR/AP video page](https://vyaparapp.in/videos/how-to-manage-accounts-receivable-and-payable), [overdue video page](https://vyaparapp.in/videos/how-to-track-overdue-payments), [mobile bill video page](https://vyaparapp.in/videos/how-to-make-bill-on-mobile-vyapar) | All Parties search/filter/export; Sale Ageing buckets, per-row and bulk reminders, graph; "type the name to create" a new customer on the bill |
| [Share invoices use case](https://vyaparapp.in/use-cases/share-invoices-instantly) | WhatsApp PDF in one tap; SMS link; resend from the saved list |
| [llms.txt](https://vyaparapp.in/llms.txt) | Claims 50+ reports, Android/iOS/Windows/Mac, UAE edition (VAT 5%) |
| Play listing (scraped) | 10M+ installs, 4.82★, 195,485 ratings, v29.4.0; screenshots say "37+ business reports"; mobile GST report has PDF and XLS buttons |

### 8.3 Pricing-page code bundle (feature keys)
`https://vyaparapp.in/pricing/assets/index-CIVtjkf2.js` (React app, 1.9 MB). Category "Premium Reports" and plan feature
lists include: `BILLWISE_PROFIT_LOSS_REPORTS`, `PARTYWISE_PROFIT_LOSS_REPORT`, `BALANCE_SHEET`, `TRIAL_BALANCE_REPORT`,
`ITEM_BATCH_REPORT`, `ITEM_SERIAL_REPORT`, `STOCK_TRANSFER_REPORT`, `GSTR_REPORTS`, `MANUFACTURING_REPORT`,
`CONSUMPTION_REPORT`; other paid features: `RECYCLE_BIN` ("Restore deleted transactions"), `AUDIT_TRAIL` ("Audit Trail &
Activity Log"), `CHECK_PROFIT_ON_INVOICES`, `SET_CREDIT_LIMIT_FOR_PARTIES`, `PARTY_WISE_ITEM_RATES`,
`SET_MULTIPLE_PRICING_FOR_ITEMS` ("different prices for retail and wholesale… based on quantity"),
`SYNC_ACROSS_DEVICES`, `AUTOMATE_PAYMENT_REMINDERS`, `REMOVE_VYAPAR_BRANDING_ON_INVOICES`, `BARCODE_GENERATION_PRINT`,
`MANAGE_GODOWNS_TRANSFER_STOCK`, `ITEM_BATCHES_AND_SERIALS`, `UPDATE_ITEMS_IN_BULK`, `CREATE_MULTIPLE_FIRMS`,
`LOYALTY_POINTS`, `SERVICE_REMINDER`, `BULK_WHATSAPP_MESSAGING`, `EXPORT_DATA_TO_TALLY`, `IMPORT_DATA_FROM_TALLY`,
`IN_BUILT_ITEM_LIBRARY` (100M+ barcodes), `TRACK_FIELD_SALESMAN`, `WEIGHING_SCALE_INTEGRATION`, `JOB_WORK_CHALLAN`,
`ADD_FIXED_ASSETS`, `CHART_OF_ACCOUNTS`, `MULTI_CURRENCY`, `PAID_INVOICE_THEMES`. Which tier holds each varies by plan
(Silver/Gold/Platinum, Retail Pro, Distributor Pro, Manufacturing Pro); the obfuscated code did not give a clean per-tier table.
Pricing from aggregators: Silver from about ₹3,399/yr desktop, ₹4,010/yr desktop+mobile ([itforsme](https://www.itforsme.in/pricing/vyapar-india)); Gold/Platinum figures inconsistent.

### 8.4 Vyapar YouTube (official channel unless marked)
| Video | Used for |
|---|---|
| [TVPBKaVSsTo](https://www.youtube.com/watch?v=TVPBKaVSsTo) Audit Trail | Turn on in General Settings; ⋮ → View History; edit and see changes; cancel or delete keeps history |
| [Bn3NAiPHPdU](https://www.youtube.com/watch?v=Bn3NAiPHPdU) Recycle Bin | Deleted transactions restorable |
| [XtiIBvDvV9Q](https://www.youtube.com/watch?v=XtiIBvDvV9Q) P&L reports | Bill-, party- and item-wise profit; Excel/PDF |
| [AEfyBoEad9c](https://www.youtube.com/watch?v=AEfyBoEad9c) Receivables/payables | "You will receive / pay" dashboard; All Parties outstanding report |
| [e7WJm4L49pw](https://www.youtube.com/watch?v=e7WJm4L49pw) Outstanding (mobile) | Thumbnail shows the mobile Party Report: Date Filter, Show All/Receivable/Payable, Group, "Show 0 balance party", Party Name / Balance, Total Receivable / Total Payable, PDF/XLS |
| [sMM_uZwXS64](https://www.youtube.com/watch?v=sMM_uZwXS64), [a1Gn5mrT_ak](https://www.youtube.com/watch?v=a1Gn5mrT_ak) | Original/Duplicate copies (desktop, mobile) |
| [KHJitxTtQ5s](https://www.youtube.com/watch?v=KHJitxTtQ5s) | Previous balance printed on the invoice |
| [ECWYl11OTP4](https://www.youtube.com/watch?v=ECWYl11OTP4) | Party-wise item rate |
| [9dunaQNz-6E](https://www.youtube.com/watch?v=9dunaQNz-6E) (AKS Tutorial Point) | Cancel invoice exists |
| [VlQ03r9NuOI](https://www.youtube.com/watch?v=VlQ03r9NuOI) (AKS) | Delete invoice |
| [nJxmsJmsDl8](https://www.youtube.com/watch?v=nJxmsJmsDl8), [CpX8TgZ62R0](https://www.youtube.com/watch?v=CpX8TgZ62R0), [x9qT3HzYvMM](https://www.youtube.com/watch?v=x9qT3HzYvMM) (AKS) | Party Statement, All Party, Party Report by Items tutorials (titles only) |
| [g3XReu9ZfOs](https://www.youtube.com/watch?v=g3XReu9ZfOs) (AKS) | Send account statement to a party |
| [QvdsYl58-vE](https://www.youtube.com/watch?v=QvdsYl58-vE), [MFeqQnPMgYQ](https://www.youtube.com/watch?v=MFeqQnPMgYQ) (AKS) | Sales and purchase report tutorials |
| [pIxzmao9Wqs](https://www.youtube.com/watch?v=pIxzmao9Wqs) | Near-expiry and expired stock tracking |
| [biEWmd-p2-w](https://www.youtube.com/watch?v=biEWmd-p2-w) | Multiple devices and billing counters |
| [YeTScOcmzFI](https://www.youtube.com/watch?v=YeTScOcmzFI) (myBillBook) | Party ledger and statement |

---

## 9. Searches that found nothing, and blocked sources

- **Vyapar mobile Reports screen:** crown icons on premium reports, report search, star/favourite and "recently used"
  — no screenshot, document or video description shows any of them. Treat as absent or unverified.
- **Vyapar bill ⋮ menu items:** only "View History", cancel and delete were confirmed (audit-trail video). Duplicate,
  Open PDF, Preview, Print, Preview as Delivery Challan, Convert to Return and Receive Payment are recalled [K].
  Converting a sale to a delivery challan via ⋮ → Convert is described for Swipe, not confirmed for Vyapar.
- **Vyapar Recycle Bin retention:** not found (a search answer claiming 90 days came from Enerpize's docs, not Vyapar).
- **Vyapar release notes:** the public changelog `vyapar-desktop-updates.feedbear.com` is deactivated; no Wayback copy.
- **Exact columns** of Party Statement, Party-wise P&L, Item/Party cross reports, Item-wise P&L, Item-wise Discount,
  Bank Statement, Tax reports, Order reports and Loan Statement: not seen on screen.
- **Blocked or unreachable:** Reddit (search refused, JSON 403, PullPush rate-limited), G2, TrustRadius and thecfoclub (403),
  MouthShut and alternativeto (DNS errors). No usable Quora, YouTube-comment or r/pakistan material.
- **Not researched:** Moneyview/Bahi Khata; Hisab Kitab (only `com.zylux.hisabkitab` found); Swipe's inline creation, POS
  and roles; BUSY's voucher rules; KP and Balochistan service-tax rates; FY2026-27 further-tax rate; the gazetted Finance
  Act 2026 Tier-1 test; whether Urdu speech recognition works offline on-device; on-device OCR quality for purchase bills.

---

## 10. Raw data and how to regenerate it

The raw files sit in the session scratchpad
(`C:\Users\safiu\AppData\Local\Temp\claude\D--Project-Working-DIrectory-Finance-Managment\6f87ecb5-061d-4203-8731-6f4f8e83fe36\scratchpad\`),
which is temporary:
- `gp_reviews2.json` (all scraped Play reviews, 5 MB), `neg/gp_cat.json` (tagged), `neg/vy_all.json` (6,000 newest Vyapar reviews);
- `posbooklet.pdf/.txt` (FBR POS Booklet 2025), `pdsr.pdf/.txt` (Punjab Drug Sale Rules);
- `mainr/img/` (Vyapar guide screenshots converted to PNG), `page.xml` (Vyapar page sitemap).

To regenerate:
- Play reviews: `pip install google-play-scraper`, then `reviews(app_id, lang='en', country='pk', sort=Sort.NEWEST, count=2000)`
  for each package listed in §3 and in the main document; filter `score <= 2`.
- Vyapar guide list: read `https://vyaparapp.in/page-sitemap.xml` and keep `/guides/`, `/videos/`, `/use-cases/`.
- Vyapar screenshots: the `<img src>` under each `<h3>` step on a guide page; they are WebP, convert with Pillow.
- YouTube: video titles and descriptions come from `ytInitialPlayerResponse.videoDetails` in the watch page HTML.
