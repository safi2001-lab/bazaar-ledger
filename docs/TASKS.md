# Bazaar Ledger — the build list

The working list for the push to match and beat Vyapar. Every item here is
either done (with the milestone that proved it), in progress, or queued. Nothing
is "done" here until its milestone is sealed in `docs/feature_ledger.yaml` with
passing proof tests — this file tracks the plan; the ledger is what proves it.

Last updated: 2 Oct 2026.

## Ground rules (from the owner)

- **Offline only.** No external API, no server, no cloud account. Anything that
  needs a server goes under "Later (needs a server)" and is not built now.
- **A sale bill a customer received is never editable.** Return and cancel
  already exist for it. Everything else a shopkeeper enters (payments, charges,
  expenses, parties, items, opening balances) must be correctable — by reversal
  underneath, never by rewriting the books.
- **Match every Vyapar feature, then beat it** — and take good features from
  other apps (Khatabook, OkCredit, myBillBook, Swipe, Zoho, Marg, Busy, Tally,
  Pakistani khata apps) and from Vyapar's bad reviews, where they work offline.
- Every milestone passes the full gate list before it lands: l10n check,
  `dart analyze --fatal-infos`, `tool/arch_check.dart`, ledger shape, every
  package test, the app tests, and ledger proofs.
- Every string in both English and Roman Urdu.
- No database schema change without coordinating the version number (v8 now).
- Agents building this work alone: a subagent may not launch its own
  subagents. Every subagent brief says so.

## Wave 1 — tester complaints and the reports hub (in progress)

### M30 · A bill is found again and sent again
Tester: "we can share an invoice when we make it, but not later."
- [ ] Sales list: search by bill no, customer name, phone, amount
- [ ] Sales list: filters — today / week / month / last month / custom; paid / udhaar / cancelled
- [ ] Row actions on every bill: Share PDF, Send on WhatsApp, Print
- [ ] Send on WhatsApp to the customer's own number with a typed summary
- [ ] Share a bill as an image (PNG), not only PDF
- [ ] Purchase bills, quotations, challans can be opened later and shared
- [ ] Tests + ledger rows; all gates green

### M31 · Every khata entry can be opened and put right
Tester: "customer account entries aren't editable once added."
- [ ] Khata open bills show the bill number (not an internal ID) and open the bill
- [ ] Every khata history entry is tappable (bill → bill; payment → payment detail)
- [ ] Payment detail: share a payment receipt PDF
- [ ] Cancel a payment received / paid (reversal, allocations released, balances right)
- [ ] Cheque payments respect the cheque lifecycle
- [ ] Edit a payment / charge / expense = cancel + re-record in one transaction
- [ ] Expenses openable with Edit and Cancel
- [ ] A party's opening balance can be corrected
- [ ] Permission: a cashier cannot cancel or edit money entries
- [ ] A posted sale bill still offers no edit
- [ ] Tests + ledger rows; all gates green

### M32 · A new customer or item is added from the bill — DONE (3e1f50a, merged)
Tester: "in Vyapar a new product or person is added while billing."
- [x] Customer picker offers "+ Add '<name>' as a new customer" (name, phone, price tier, credit limit)
- [x] Item search offers "+ Add '<text>' as a new item" (name, sale price, unit, cost, opening stock)
- [x] An unknown scanned barcode (wedge, camera, scale label) offers the same quick item sheet
- [x] Same on the purchase screen (new supplier, new item at the buying price)
- [x] Duplicates are warned about (same name or same mobile); roles respected (no cost/stock/tier for a role that cannot see costs)
- [x] Quick-added items survive the app being killed mid-bill
- [x] Tests + ledger rows; gates green (17 tests in test/new_from_the_bill_test.dart)
- Found on the way and fixed: a purchase line's prefilled cost was read as the line total, so average cost came out at a tenth of the price.
- Owner to decide: a separate "may add items/customers" permission (today no role is barred, as in the full forms).
- Not built: give a scanned barcode to an existing item; landline on the short form.

### M33 · The reports hub, and every transaction and party report
From the owner's Vyapar screenshots.
- [ ] Hub grouped like Vyapar: Transaction, Party, Item/Stock, Business status, Taxes, Expense, Orders, Loan
- [ ] Search reports by name
- [ ] Star a report → Favourites at the top (kept on the phone)
- [ ] Plan lock shown on paid reports
- [ ] Date presets incl. custom range and Pakistani fiscal year
- [ ] Per-report filters: party, item, category, party group, type, payment mode, user
- [ ] Summary tiles; tap a row through to its bill
- [ ] Export: PDF, CSV, Excel (.xlsx), print, share
- [ ] Transaction: Sale Report, Purchase Report, Day Book, All Transactions, Bill Wise Profit, Profit & Loss, Cashflow, Balance Sheet
- [ ] Party: Party Statement, Party Wise P&L, All Parties, Party Report by Items, Sale/Purchase by Party, Sale/Purchase by Party Group
- [ ] A registry so later report groups plug in cleanly
- [ ] Tests that tie each report's totals to the books; all gates green

## Wave 2 — the rest of Vyapar's reports (queued, starts on M33's framework)

### M34 · Item and stock reports
- [ ] Stock Summary (as-of date, category, godown, "in stock only", sale/purchase price, value)
- [ ] Item Report by Party / Party Report by Item (both directions)
- [ ] Item Wise Profit & Loss, Item Category Wise Profit & Loss
- [ ] Low Stock Summary (with reorder suggestion)
- [ ] Item Detail (one item, date-wise sale/purchase/adjustment/closing)
- [ ] Stock Detail (every item: opening, in, out, closing — qty and value — for any period)
- [ ] Sale/Purchase by Item Category; Stock Summary by Item Category
- [ ] Item Batch Report (batch, expiry, qty); Item Serial/IMEI Report (sold/unsold/returned, search)
- [ ] Item Wise Discount
- [ ] Stock Transfer Report (godowns, vans)
- [ ] Production run register (manufacturing / consumption)
- [ ] Beyond Vyapar: dead / slow / fast stock (sales in last N days), stock ageing 0-45/45-90/90-180/180+

### M35 · Business status, tax, expense, staff and order reports
- [ ] Bank Statement (per bank account: date, description, withdrawal, deposit, balance)
- [ ] Discount Report (per party given/received) and discount by cashier
- [ ] Tax Report (output vs input sales tax, per party); Tax Rate Report (18%, reduced, exempt, zero, further tax, Third Schedule)
- [ ] Sales by HS code; Annex-C (sales) and Annex-A (purchases) export files for the sales tax return (offline files, nothing sent)
- [ ] Expense Transaction Report, Expense Category Report, Expense Item Report
- [ ] Order registers: open quotations, challans not yet billed (and purchase/sale orders once M41 exists)
- [ ] Beyond Vyapar: sales by cashier/counter, payment-mode summary, hourly sales
- [ ] Beyond Vyapar: daily summary / Z report screen + 58/80mm print (sales, returns, collections by mode, udhaar given/recovered, expenses, profit, cash expected vs counted)
- [ ] Beyond Vyapar: customer payment performance (average days late), defaulter list, expected collections this week
- [ ] Beyond Vyapar: changed / cancelled bills report ("bill value changes")

## Wave 3 — features from other apps and from Vyapar's bad reviews (queued)

From `docs/competitor_research.md` (sections 6–8). Offline-doable only. Each is
its own milestone; any that changes the database schema runs alone, one at a
time, on the latest master (schema is v8 today).

### Billing and bills
- [ ] M36 · Duplicate a bill / repeat last order for a party / "correct and reissue" (cancel + prefilled copy, linked both ways); cancel reason codes; Original/Duplicate copy labels; previous balance printed on the bill
- [ ] M37 · (in progress) Last 5 rates for this party and item, shown when the item goes on the bill, one tap to reuse; a loose-item line (amount only, never saved as an item)
- [ ] M43 · Schemes: buy X get Y (10+1 bonus), quantity-slab prices, bill-value discount slabs; scheme received on purchases flows into cost
- [ ] M45 · Two-unit quantities everywhere ("2 ctn + 5 pcs", "1 kg 500 g") on bills, stock and reports, and entered that way
- [ ] M51 · Transporter copy without prices (bilty/delivery); Original/Duplicate/Triplicate labels; invoice themes for A4/A5 (logo, colours, layouts)
- [ ] M53 · Negative stock policy per item (allow / warn / block); app font-size setting
- [ ] Recurring bills (weekly/monthly for fixed customers), made on the phone when due
- [ ] Shop's static payment QR (Raast/JazzCash/Easypaisa image), IBAN and wallet on bills and reminders

### Udhaar and money
- [ ] M38 · Credit days → due date on every bill; promise-to-pay ("wasooli") date per customer; a "due today / overdue" list on the home screen; ageing by due date with a "not yet due" bucket
- [ ] M39 · Bulk reminder queue: tick the overdue list, send one by one through WhatsApp/SMS from the shop's own phone; templates in Urdu script, Roman Urdu and English with {name} {amount} {due} {shop} {wallet}; per-customer language and opt-out; reminder log
- [ ] M44 · Settlement discount and bad-debt write-off with a reason ("baqi chhor do"); bad debts report
- [ ] M48 · (in progress) Loan accounts: loan taken, repayments split into principal and interest, loan statement
- [ ] M55 · Quantity-only khata lines ("10 kg ghee given, rate later"), priced at settlement
- [ ] Collection sheet for the recovery man: a numbered list of a route's open bills, marked Paid / Partial / Shop closed on return

### Stock and buying
- [ ] M40 · Party groups (area, route, mohalla, type) — set on parties, used by every report
- [ ] M41 · Purchase orders and sale orders as documents; shortage list ("*" at the counter); reorder suggestion (average sales × cover days − stock − open orders) grouped by last supplier → a purchase order sent on WhatsApp; quoted rate checked at delivery
- [ ] M49 · Pharmacy pack: near-expiry by supplier, expiry return to the supplier with a return note, salt/generic search with substitutes, Schedule B/D register
- [ ] M50 · Mobile-shop pack: IMEI search and history, warranty end date, PTA status field + SMS to 8484, used-phone purchase with seller's CNIC and photo, qist (instalment) plans with overdue list and guarantor

### Trust and control
- [ ] M42 · Per-record history (who changed what, when); period lock date after day close with owner override and reason; Data Lock PIN for edits and deletes
- [ ] Recycle bin for masters with 30-day restore (check what M5 already does)

### Expenses
- [ ] M47 · "Shop vs ghar" (owner's drawings) tag on expenses; other income entries and reports; recurring rent/bijli reminders

### Reports polish
- [ ] M46 · Charts: sales trend, top 10 items/customers, receivable ageing pie, "vs last period" — drawn on the phone
- [ ] Saved report views ("my Monday udhaar list")

### Getting shops to switch
- [ ] M52 · Importer presets for Vyapar and Khatabook Excel exports (items, parties, opening balances) — Vyapar's service in Pakistan is disrupted and its users are stranded

### Pakistan specifics (from the research appendix §1–2)
- [ ] Third Schedule goods: warn when a price goes above the printed retail price (MRP); show tax as MRP × 18/118
- [ ] Buyer's name required on a single bill over Rs 100,000 (FBR); warn at the counter
- [ ] FBR DI bills made while offline are marked "issued in offline mode" and sent within 24 hours of the connection coming back (Rule 150XC)
- [ ] Provincial sales tax on services (PRA 16% / 8% by card or QR; SRB 15% / 8%) for repair shops, salons, restaurants — rate after the tender is chosen
- [ ] Search that forgives Roman Urdu spellings (atta/aata, cheeni/chini) and Urdu script
- [ ] Units shops use: maund (40 kg), seer, dozen, carton/dabba, strip/tablet; kilos with grams
- [ ] Photo of a paper parchi attached to an entry (check what attachments already do)
- [ ] Pharmacy: selling above DRAP MRP blocked, "% off MRP" discount

### Checks on things we may already do (test, fix if wrong)
- [ ] An old bill keeps the party's name/address as they were (myBillBook bug +550)
- [ ] Split payments (cash + JazzCash) are separate rows in every report and export (Vyapar's top 2026 complaint)
- [ ] Never silently sell into negative stock (see M53)
- [ ] Big shop performance: 50,000 bills, lists and reports stay fast
- [ ] Urdu PDFs readable; bigger font option

## Finish line for each wave

- [ ] Merge every branch into master; resolve ARB and ledger conflicts; regenerate l10n
- [ ] Full gate list green on the merged tree (`melos run ci` equivalent)
- [ ] Build the phone APK and put it on the Desktop
- [ ] Ask the owner before pushing to GitHub

## Later (needs a server or an outside service — not now)

- Online invoice links a customer opens in a browser; customer portal / "live khata" links
- Payment gateway / payment links; dynamic Raast QR with reconciliation
- Cloud sync between shops across the internet; web/PC dashboard
- Server-sent SMS with a sender ID; WhatsApp Business API auto-messages; scheduled report emails
- Online medicine database / DRAP price updates; distributor price lists; B2B ordering
- Cloud OCR of purchase bills; cloud voice entry
- PTA DIRBS online lookup; NTN/STRN online lookup
- Live FBR/PRAL use with real credentials (built, never run against PRAL)
- Google Drive backup with a real OAuth client (built, never run against Google)

## Done

(Moves here with its milestone and commit when sealed.)
