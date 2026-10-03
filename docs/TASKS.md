# Bazaar Ledger — the build list

The working list for the push to match and beat Vyapar. Every item here is
either done (with the milestone that proved it), in progress, or queued. Nothing
is "done" here until its milestone is sealed in `docs/feature_ledger.yaml` with
passing proof tests — this file tracks the plan; the ledger is what proves it.

Last updated: 3 Oct 2026.

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
- No database schema change without coordinating the version number (v12 now — M50).
- Agents building this work alone: a subagent may not launch its own
  subagents. Every subagent brief says so.

## Wave 1 — tester complaints and the reports hub (all done)

### M30 · A bill is found again and sent again — DONE (7475907, merged)
Tester: "we can share an invoice when we make it, but not later."
- [x] Sales list: search by bill no, customer name, phone (any format), amount (5525 / 5,525 / Rs 5525)
- [x] Sales list: filters — all / today / this week / this month / last month / date range; all / paid / udhaar / cancelled (in SQL, paging kept)
- [x] Send button and long-press on every bill row (list and home): WhatsApp, PDF, picture, print
- [x] WhatsApp opens the customer's own chat with shop, bill no, date, total, paid, still owed typed out; no number → share sheet
- [x] Share a bill as a picture (PNG) — no new dependency
- [x] Purchase bills (now openable — a tap used to go straight to send-back), quotations and challans can be opened later and shared
- [x] CANCELLED / MANSOOKH mark on a cancelled bill's PDF, picture and message; DUPLICATE / DOBARA COPY on a bill already printed
- [x] Tests + ledger rows (22 proofs); gates green
- Not built: a file straight into a named WhatsApp chat (WhatsApp links carry text only; files go through the share sheet with the message as caption); marks on thermal reprints; opening returns (no list yet).

### M31 · Every khata entry can be opened and put right — DONE (cb3f157, merged)
Tester: "customer account entries aren't editable once added."
- [x] Khata open bills show the bill number and date (not an internal ID) and open the bill
- [x] Every khata line opens: bill → bill; payment → payment page (amount, mode, account, cheque, bills settled, who/when, edit history); charge; bounced cheque; opening balance
- [x] Payment receipt PDF to share (marked CANCELLED with the reason if cancelled)
- [x] Cancel a payment received / paid: mirror entry, bills owed again, allocations released, audit row
- [x] Cheque at the bank / cleared / bounced: refused in words (it moves through the Cheques screen)
- [x] Edit a payment / charge / expense = cancel + re-record in one transaction (a failed edit leaves the original)
- [x] Expenses open from the list with Edit and Cancel
- [x] A party's opening balance can be corrected (from the khata or the party's details)
- [x] Reason presets: Wrong entry / Duplicate / Wrong amount / Customer dispute / Other
- [x] New permission "correct entries": owner, manager, accountant — not a cashier
- [x] A posted sale bill still offers no edit
- [x] Tests (14 database tests + 8 widget tests) + ledger row; gates green
- Not built: moving a payment to another party (cancel + re-enter); back-dated corrections; showing cancelled entries struck through; returns to a supplier opening.

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

### M33 · The reports hub, and every transaction and party report — DONE (e35302a, merged)
From the owner's Vyapar screenshots.
- [x] Hub grouped like Vyapar: Transaction, Party, Item/Stock, Business status, Taxes, Expense, Orders, Loans (empty groups hidden until filled)
- [x] Search reports by name; star → Favourites card; last 4 opened as Recent; each report remembers its period
- [x] Plan lock on paid reports; cost reports hidden for roles that may not see costs
- [x] Periods: today, yesterday, this week, this month, last month, this quarter, this FY (Jul–Jun), last FY, custom range
- [x] Filters as chips: party, party group, item, category, payment status, payment mode, user, type — all in SQL
- [x] Summary tiles with "% vs the period before"; sort any column both ways; 200 rows at a time; tap a bill → the bill, a party → its statement
- [x] Export: PDF, Excel (.xlsx, own small writer), CSV, print on the receipt printer
- [x] Transaction: Sale Report, Purchase Report, Day Book (extended), All Transactions, Bill Wise Profit, Profit & Loss (cost of sales laid out), Cash Flow, Balance Sheet, Trial Balance, Cash Book
- [x] Party: Party Statement, Party Wise P&L, All Parties, Party Report by Items, Sale/Purchase by Party, Sale/Purchase by Party Group
- [x] Tests tie totals to the books (sale report = sales by day; bill-wise profit = party-wise profit; cash flow closing = cash book; party statement = khata); 20,000-bill year in ~0.5 s
- Not built: direct A4 printing (no print plugin; PDF → any viewer prints it); charts and a column chooser (→ M46).
- Found: the khata history left out sale returns (sent to the udhaar-pack agent to fix); `party_group` was never written (→ M40).

## Wave 2 — the rest of Vyapar's reports (in progress on M33's framework)

### M34 · Item and stock reports — DONE (7db836b)
- [x] Stock Summary (as-of date, category, godown, "in stock only", sale/purchase price, value)
- [x] Item Report by Party / Party Report by Item (both directions)
- [x] Item Wise Profit & Loss, Item Category Wise Profit & Loss
- [x] Low Stock Summary (with reorder suggestion)
- [x] Item Detail (one item, date-wise sale/purchase/adjustment/closing)
- [x] Stock Detail (every item: opening, in, out, closing — qty and value — for any period)
- [x] Sale/Purchase by Item Category; Stock Summary by Item Category
- [x] Item Batch Report (batch, expiry, qty); Item Serial/IMEI Report (sold/unsold/returned, search)
- [x] Item Wise Discount
- [x] Stock Transfer Report (godowns, vans)
- [x] Production run register (manufacturing / consumption)
- [x] Beyond Vyapar: dead / slow / fast stock (sales in last N days), stock ageing 0-45/45-90/90-180/180+

  - Found: batch costs were the item average on arrival; batches now valued off their own ledger rows. Khula maal shows as one "Khula maal (no item)" row.
  - Not built: per-item trading account, ageing by expiry date, ABC classification, place filter on ageing/fast-slow.

### M35 · Business status, tax, expense, staff and order reports — DONE (7d10df0)
- [x] Bank Statement (per bank account: date, description, withdrawal, deposit, balance)
- [x] Discount Report (per party given/received) and discount by cashier
- [x] Tax Report (output vs input sales tax, per party); Tax Rate Report (18%, reduced, exempt, zero, further tax, Third Schedule)
- [x] Sales by HS code; Annex-C (sales) and Annex-A (purchases) export files for the sales tax return (offline files, nothing sent)
- [x] Expense Transaction Report, Expense Category Report, Expense Item Report
- [x] Order registers: open quotations, challans not yet billed (and purchase/sale orders once M41 exists)
- [x] Beyond Vyapar: sales by cashier/counter, payment-mode summary, hourly sales
- [x] Beyond Vyapar: daily summary / Z report screen + 58/80mm print (sales, returns, collections by mode, udhaar given/recovered, expenses, profit, cash expected vs counted)
- [x] Beyond Vyapar: customer payment performance (average days late), defaulter list, expected collections this week
- [x] Beyond Vyapar: changed / cancelled bills report ("bill value changes")

## Wave 3 — features from other apps and from Vyapar's bad reviews (queued)

From `docs/competitor_research.md` (sections 6–8). Offline-doable only. Each is
its own milestone; any that changes the database schema runs alone, one at a
time, on the latest master (schema is v8 today).

### Billing and bills
- [x] M36 · DONE (adfcfef) Duplicate a bill / repeat last order for a party / "correct and reissue" (cancel + prefilled copy, linked both ways); cancel reason codes; Original/Duplicate copy labels; previous balance printed on the bill
- [x] M37 · Last rates and khula maal — DONE (80b28aa): customer named first from the counter; "Pichhli dafa Rs X · date" beside every line; tap for the last 5 deals, one tap uses the price (exact unit conversion, never applied silently); supplier's last 5 prices on purchases; cost shown only to roles that may see it; khula maal line (no item, no stock, refused on FBR-reporting shops and on quotations/challans); fixed a standing-discount bug that made bills refuse
- [x] M57 · DONE (a6a2dea) Returns give back exactly what was charged: line discount and bill-discount share respected; quantity in the unit it was sold in (a maund line was over-refunding 40×) — found by M37
- [x] M43 · DONE (0adfc85) Schemes: buy X get Y (10+1 bonus), quantity-slab prices, bill-value discount slabs; scheme received on purchases flows into cost
- [x] M45 · DONE (c262b6d, a1adfa3) Two-unit quantities everywhere ("2 ctn + 5 pcs", "1 kg 500 g") on bills, stock and reports, and entered that way
- [x] M51 · DONE (baf5795) Transporter copy without prices (bilty/delivery); Original/Duplicate/Triplicate labels; invoice themes for A4/A5 (logo, colours, layouts)
- [x] M53 · DONE (3f12774, schema v10) Negative stock policy per item (allow / warn / block); app font-size setting
- [x] M63 · DONE (e04e01c) Recurring bills (weekly/monthly for fixed customers), made on the phone when due
- [x] (M51) Shop's static payment QR (Raast/JazzCash/Easypaisa image), IBAN and wallet on bills and reminders

### Udhaar and money
- [x] M38 · DONE (410f560) Credit days → due date on every bill; promise-to-pay ("wasooli") date per customer; a "due today / overdue" list on the home screen; ageing by due date with a "not yet due" bucket
- [x] M39 · DONE (038be4f) Bulk reminder queue: tick the overdue list, send one by one through WhatsApp/SMS from the shop's own phone; templates in Urdu script, Roman Urdu and English with {name} {amount} {due} {shop} {wallet}; per-customer language and opt-out; reminder log
- [x] M44 · DONE (d955b94) Settlement discount and bad-debt write-off with a reason ("baqi chhor do"); bad debts report
- [x] M48 · Loan accounts — DONE (895802e): Accounts → Loans; take a loan (fee kept back in one entry), repay with principal/interest/charges split and interest suggested, statement per loan as PDF/CSV, cancel by reversal; interest and fees in P&L, each loan a liability
  - [x] Loan Statement in the Reports hub (Loans group) — done in M58 — hook `buildLoanStatement` / `DriftLoanReads` into the registry (small follow-up after M35)
- [x] M55 · DONE Goods given rate later ("10 kg ghee given, rate later"): a challan with no rate from the khata or the counter, off the shelf at cost and owing nothing, shown apart on the khata, the chase list and the statement; "Rate lagayein" puts the rates on and bills it at the counter (M25's path, several challans on one bill)
- [x] M55 · DONE Collection sheet for the recovery man: customers by route, late or due today, numbered WS-…, printed 58/80mm, PDF or WhatsApp; on return each line Paid / Partial / Promise / Shop closed / Refused, receipts and promises on every khata in one go, expected vs collected and cash to hand over
  - Found: a receipt's note never reached the payment row (fixed); not built: cheques on the round, recording one sheet in two sittings

### Stock and buying
- [x] M40 · Party groups — DONE: groups on customers/suppliers (form + quick-add), filter/sort/bulk-assign on the Customers list with group totals, rename/merge groups, group chips at the counter, a "Counter ke liye note" shown on the payment sheet
- [x] M41 · DONE (ee1bf11) Purchase orders and sale orders as documents; shortage list ("*" at the counter); reorder suggestion (average sales × cover days − stock − open orders) grouped by last supplier → a purchase order sent on WhatsApp; quoted rate checked at delivery
- [x] M49 · DONE (83ab445, schema v11) Pharmacy pack: near-expiry by supplier, expiry return to the supplier with a return note, salt/generic search with substitutes, Schedule B/D register
- [x] M50 · DONE (51db127, schema v12) Mobile-shop pack: IMEI search and history, warranty end date, PTA status field + SMS to 8484, used-phone purchase with seller's CNIC and photo, qist (instalment) plans with overdue list and guarantor

### Trust and control
- [x] M42 · DONE (a1d31f4, d1676e6) Per-record history (who changed what, when); period lock date after day close with owner override and reason; Data Lock PIN for edits and deletes
- [x] M60 · DONE (d74fb03) Recycle bin for masters with 30-day restore (check what M5 already does)

### Expenses
- [x] M47 · DONE (a2592e7) "Shop vs ghar" (owner's drawings) tag on expenses; other income entries and reports; recurring rent/bijli reminders

### Reports polish
- [x] M46 · DONE with M58 (55fa8d2) Charts: sales trend, top 10 items/customers, receivable ageing pie, "vs last period" — drawn on the phone
- [x] M61 · DONE (53ce11f) Saved report views ("my Monday udhaar list")

### Getting shops to switch
- [x] M52 · Moving off Vyapar/Khatabook — DONE (ee47eba): "Where is this file from?" with auto-detection; balances on the right side; Indian GST/HSN never carried; units matched; duplicates skipped or updated by choice; old .xls read with no new dependency; preview in Urdu/English; large files off the main thread
  - Not verified: Vyapar's exact export headings (no public sample) — by-hand column mapping is the backstop; supplier opening balances still go in as purchase bills

### Pakistan specifics (from the research appendix §1–2)
- [x] M59 · DONE (96d3e8e) Third Schedule goods: warn when a price goes above the printed retail price (MRP); show tax as MRP × 18/118
- [x] M59 · DONE (96d3e8e) Buyer's name required on a single bill over Rs 100,000 (FBR); warn at the counter
- [x] M59 · DONE (96d3e8e) FBR DI bills made while offline are marked "issued in offline mode" and sent within 24 hours of the connection coming back (Rule 150XC)
- [x] M59 · DONE (96d3e8e) Provincial sales tax on services (PRA 16% / 8% by card or QR; SRB 15% / 8%) for repair shops, salons, restaurants — rate after the tender is chosen
- [x] M56 · DONE (88ead47) Search that forgives Roman Urdu spellings (atta/aata, cheeni/chini) and Urdu script
- [x] M56 · DONE Units shops use: maund (40 kg), seer, dozen, carton/dabba, strip/tablet; kilos with grams; app text-size setting
- [x] M60 · DONE Photo of a paper parchi attached to an entry (check what attachments already do)
- [x] M49 · Pharmacy: selling above DRAP MRP blocked, "% off MRP" discount

### Checks on things we may already do (test, fix if wrong)
- [x] M62 · DONE (0a5d135) An old bill keeps the party's name/address as they were (myBillBook bug +550)
- [x] M62 · DONE (0a5d135) Split payments (cash + JazzCash) are separate rows in every report and export (Vyapar's top 2026 complaint)
- [x] Never silently sell into negative stock — M53
- [x] M62 · DONE (0a5d135) Big shop performance: 50,000 bills, lists and reports stay fast
- [x] M62 · DONE (0a5d135) Urdu PDFs readable — bigger font option already done in M56


### Follow-ups found while merging — DONE by M58 (55fa8d2) and M36, except the owner decisions
- [x] Reports: Day Book / All Transactions call a party-less `other_income` document "Charge" — it is shop income (M47); expense reports must leave out or show apart the owner's drawings
- [x] Reports: M8 "Sales by item" inner-joins items, so khula maal lines are missing from it
- [x] Reports: Loan Statement in the hub's Loans group (M48 builder exists)
- [x] Reports: due-date ageing and bad-debts reports from the udhaar pack's queries
- [x] Receipt preview grows with the app text size — wrap it in `MediaQuery.withNoTextScaling` (lib/features/sales)
- [x] `recentExpenses` reads the head as required and would throw on a shop's own head (no caller now)
- [ ] Owner to confirm: seer = 1 kg (40 kg maund) rather than 933 g; separate permissions for quick-add and khula maal lines

### Found while merging this round
- [x] M60 found that any picture (item photo, logo, QR) broke LAN sync for that counter since M2/M51 — fixed: pictures stay on their phone and in its backups; everything else syncs
- [x] M43 × M45: a supplier's free carton on a delivery typed "10 ctn 5" was written as "1 pcs" — fixed in the merge (a1adfa3)
- [x] M59 found Third Schedule goods sold below MRP were under-taxed (Rs 15.25 instead of Rs 18 on a Rs 118 pack) — fixed
- [x] M61 · DONE: provincial service tax in the tax rate report, party tax, HS-code sales, Annex-C, the sales tax summary and returns
- [ ] Owner/accountant to confirm: free bonus lines carry no sales tax; service lines on an FBR-reporting shop go to FBR at 0%; whether PRAL accepts a Rs 0 line

### Polish round — small gaps the milestones reported — DONE by M54 (12/12)
- [x] M41: "Challan banayein" for a sale order loaded on the counter (one condition in the payment sheet) — M54
- [x] M41: the credit-limit check counts a sale order's advance against the bill it pays — M54 (the khata already netted the advance; a bill the advance covers is no longer asked)
- [x] M36 × M43: a copied bill no longer lists its old bonus as "left out" (the counter gives it again) — M54
- [x] M45: the stock warning in packs ("Stock sirf 2 ctn + 5 pcs hai"); a dozen line remembers its dozen when a piece is added — M54 (cart draft v6, older drafts read)
- [x] M43: a challan billed after its item's scheme changed is billed as sent, not refused — M54
- [x] M35: "Expected collections this week" (now that bills have due dates, M38) — M54, Party group, next 7 days with qist instalments and promises
- [x] M47: one line on Home for monthly bills due — M54
- [x] M42: sharing a bill (WhatsApp / PDF / picture) recorded in its history — M54 (DUPLICATE stays a paper mark, as M30 decided)
- [x] M49: Schedule items on a delivery challan asked for the prescription; batch MRP on the PO receive sheet; importer maps a "Generic" column — M54
- [x] M52: Vyapar's second unit and conversion imported as the item's pack (M53 made packs possible) — M54 (when the second unit is a pack and the conversion whole; a sheet whose first unit is the pack comes in as before)
- [x] M60: photos on loan entries, a cheque's own page and batches — M54
- [x] M55: cheques taken on a recovery round — M54

## Finish line for each wave

- [x] Merge every branch into master; resolve ARB and ledger conflicts; regenerate l10n — M30 to M63 all merged
- [x] Full gate list green on the merged tree — l10n check, analyze (root + 11 packages), arch, ledger shape, and the full verifier: 253 features, every completed feature has a passing proof (M0's 4 open rows are the handset demo, its recording, CI on a push, and goldens — all need things outside this machine)
- [x] Build the phone APK and put it on the Desktop
- [ ] Ask the owner before pushing to GitHub

## Round 4 — what the research offered that the first three rounds left (3 Oct 2026)

Found by re-reading `docs/competitor_research.md` §6–§8 and the appendix against the ledger. Offline-doable only.

### Batch 1 (in progress)
- [ ] M65 · (in progress, schema v13) Staff book: employees (not only app users), attendance, salary, advances, payroll posted to the books
- [ ] M66 · (in progress) Loyalty points; a fixed price list per customer; the margin on a bill shown while billing, owner only
- [ ] M67 · (in progress) Reports, deeper: ratio analysis (GP%, NP%, stock turnover, days to collect/pay), one exception report, ABC stock classes, ageing buckets the shop sets, stock valued at cost or sale price, per-column filters and a column chooser, "vs last period" on charts

### Batch 2 (queued)
- [ ] M68 · Control: credit control by bill count and days, a temporary limit, stop billing after a bounced cheque; days older than N lock themselves; random stock checks (cycle count); cashier mode (salesman bills, cashier collects)
- [ ] M69 · Repair job cards for mobile shops (device, IMEI, fault, estimate, parts from stock, labour, ready/delivered, billed) — schema v14
- [ ] M70 · More bill designs; after a bill or payment, offer to send the customer their receipt (per-customer on/off)

### Considered and left for now
- Urdu in its own script on screen (اردو, right to left) — the owner decided Roman Urdu and English are enough (3 Oct 2026); Urdu script stays on printed bills, PDFs and reminder templates
- Voice notes on entries (needs the microphone permission; photos already cover the paper)
- Overseas khatas in SAR/AED/USD (a second currency touches every amount in the books)
- A Windows PC build of the app (the Android printer, scanner and photo paths would each need a desktop twin)

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
