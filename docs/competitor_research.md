# Vyapar and other billing apps: competitor research for Bazaar Ledger (2 Oct 2026)

**Confidence tags used below:**
- **[V]** I checked it this session: an official vyaparapp.in page, a screenshot on that page (desktop app, March 2026 build), Vyapar's own pricing-page JavaScript, or Vyapar's own YouTube channel.
- **[R]** It comes from user reviews: Google Play reviews scraped on 2 Oct 2026 (1–2★ counts: Vyapar 2,246, Khatabook 1,240, myBillBook 1,134, OkCredit 1,242, EasyKhata 898, DigiKhata 1,101, CreditBook 696, Rupin 999), plus Capterra and Trustpilot.
- **[K]** It is product-walkthrough knowledge or a third-party account that I could **not** confirm this session. Check it in the live app before copying exact labels.

**What "BL" means:** Bazaar Ledger's status according to `D:\Project Working DIrectory\Finance Managment\docs\feature_ledger.yaml` (M0–M29).

**How this was produced:** three research subagents ran early on. They were told to stop when the no-subagent rule arrived. Their findings (Play-review mining, Pakistani apps, myBillBook/Swipe/Zoho/Marg/Tally/Khatabook) are folded in and attributed. Everything else, including all of the Vyapar screen and report verification, I did myself.

---

## 0. Headline findings

1. **Vyapar has about 50 reports, plus GST reports.** The Play listing says "37+" and the site says "50+".
   - On desktop, every list-type report shares one pattern:
     - a filter bar: period preset + from/to + firm + user + godown, plus a transaction-type filter on All Transactions;
     - summary cards;
     - a table with a funnel filter on each column and a search box;
     - row actions: print, share and a ⋮ menu;
     - Graph, XLS and Print buttons.
   - Columns cannot be chosen; the FAQ admits it [V] ([guide](https://vyaparapp.in/guides/how-to-check-transaction-reports-in-vyapar-app)).
   - **BL's report pack has 4 period presets (today, this month, last month, this fiscal year) and no party, user, category or payment filters. This is the single biggest reporting gap.**
2. **These Vyapar reports are premium** (from the "Premium Reports" category in its pricing bundle [V]):
   - Balance Sheet, Bill-wise P&L, Party-wise P&L, Trial Balance;
   - Item Batch Report, Item Serial Report, Stock Transfer Report;
   - GSTR reports, Manufacturing Report, Consumption Report.
3. **These Vyapar features are also premium** [V]:
   - Recycle Bin ("Restore deleted transactions"), Audit Trail & Activity Log, Check Profit on Invoices;
   - credit limit, party-wise item rates, multiple pricing (wholesale by quantity), sync across devices;
   - automated payment reminders, removing Vyapar branding, barcode generation, godowns, batches/serials;
   - bulk item update, multiple firms.
4. **Vyapar's biggest pain points are commercial:**
   - Paywall complaints went from 14% of 1–2★ reviews (2024 and earlier) to 24% (2025–26) [R].
   - Mid-2025 reviews report the free plan cut to 5 invoices a week (user-reported, not officially confirmed) [R].
   - A licence is tied to one device; "sync" needs internet, and billing offline means turning sync off ([Vyapar's own guide](https://vyaparapp.in/guides/how-to-make-bills-offline-in-vyapar)) [V].
   - Support ranks second at 13–17% of 1–2★ reviews [R].
5. **Vyapar's service in Pakistan appears disrupted since May 2025.** Users write "pakistan ma phla chlti thi, india pak war ka bd bnd kr dii" (it worked in Pakistan before; they shut it after the war) and that licences can't be renewed [R, not officially confirmed]. Khatabook demands an Indian OTP [R].
   - **There are stranded paying users.** An importer for Vyapar's Excel exports is an acquisition hook.
6. **In Pakistan, DigiKhata (May 2026) and CreditBook (Dec 2025) made their apps online-only.** DigiKhata put offline use behind a paid "Pro" plan (Rs 790/month); CreditBook removed offline entry outright. Reviews are furious; DigiKhata had 249 1–2★ reviews in May 2026 alone [R]. **Free, offline, no-login is the clearest opening in the market. BL already has it; say it loudly.**
7. **Invoice handling: Vyapar edits posted bills in place.** Edit/delete can be gated by a passcode, an audit trail ("View History") is optional and premium, cancel exists, and deletes go to a premium Recycle Bin.
   - BL's "reverse, never edit" model is stricter and more trustworthy.
   - BL still lacks the convenience layer around it: find any old bill and reprint or reshare it, duplicate it, see its history, keep a cancel reason, and correct-and-reissue in one step.
8. **Inline creation: Vyapar silently auto-creates a party or item from whatever is typed on the bill.** Users blame this for duplicate parties and items and for negative stock [R]. Copy the speed, not the silence: quick-add with a "did you mean…?" check.

---

## 1. Vyapar's report list, report by report

### 1.0 Reports screen UX, shared mechanics, premium tags

- **Desktop** [V, screenshots in the guides]:
  - Left: the app menu. Middle: the report catalogue, grouped by section headers. Right: the open report.
  - A global "Search Transactions" box and "Open Anything (Ctrl+F)" sit at the top.
  - Sections as seen on desktop:
    - Transaction report
    - Party report
    - GST reports
    - Item/Stock report
    - Business Status
    - Taxes (GST Report, GST Rate Report, Form No. 27EQ, TCS Receivable, TDS Payable, TDS Receivable)
    - Expense report
    - Sale/Purchase Order report
    - Other Income report
    - Loan
- **Mobile:**
  - A list with section headers and **PDF and XLS icons** on each report's top bar [V: GST report screenshot on the Play listing; official thumbnail of the mobile "Party Report"].
  - **Crown icons on premium reports:** you report seeing them; I could not verify them from public material.
  - **Search, favourite/star, recently used:** I found **no evidence** of these in any screenshot or document. Treat them as absent or unverified. Zoho Books *does* have report search and favourite stars ([Zoho](https://www.zoho.com/books/help/reports/manage-reports.html)).
- **Common controls** [V]:
  - Period dropdown: "This Month" and similar. The guide names Monthly, Quarterly, Yearly and Custom.
  - A "Between" from/to range.
  - ALL FIRMS, ALL USERS, All Godown.
  - A funnel filter on every column header; an in-table search box.
  - Graph view on Sale and Expense; XLS (Excel) and Print (which also produces a PDF).
  - Per-row Print, Share and ⋮ menu.
  - Deleted transactions do not appear in reports; they sit in the Recycle Bin.
  - **No column chooser** (FAQ in the [transaction reports guide](https://vyaparapp.in/guides/how-to-check-transaction-reports-in-vyapar-app)).

### 1.1 Transaction reports

**Sale Report** [V]
- **Filters:** period preset, from/to, All Firms, All Users, All Godown; a funnel on every column.
- **Summary cards:**
  - Total Sales Amount, with a "% vs last month" chip, plus Received and Balance.
  - Total Loyalty Points Rewarded and Total Discount Redeemed.
- **Columns:** Date | Invoice no | Party Name | Transaction | Payment Type | Amount | Balance | Actions (print, share, ⋮).
- **Exports:** search, Graph, XLS, Print.

**Purchase Report** [V text]
- Mirrors the Sale Report (Godown, Monthly/Quarterly/Yearly/Custom).
- XLS and PDF/print.
- Columns [K]: same as Sale, with "Paid" in place of "Received".

**Day Book** [V screenshot]
- **Filters:** a **single date**, ALL FIRMS, All Godown; a search box; funnels.
- **Columns:** Name | Ref No | Type (Sale, Purchase, Expense, Other Income…) | Payment Type | Total | Money In | Money Out | Print/Share | ⋮.
- **Exports:** Excel Report, Print.
- No running cash balance is shown.

**All Transactions** [V screenshot]
- **Filters:** period preset + Between, ALL FIRMS, ALL USERS, **All Transaction (type)**, All Godown; search; funnels.
- **Columns:** # | Date | Ref No. | Party Name | Category Name | Type | Total | Received/Paid | Balance | Print/Share | ⋮.
- **Exports:** Excel, Print.
- The FAQ says this is how you get an "outstanding bills" PDF: filter to unpaid ([FAQ](https://vyaparapp.in/faq)).

**Bill Wise Profit** [V screenshot] (premium)
- **Filters:** From/To, Party filter.
- **Title:** "PROFIT ON SALE INVOICES".
- **Columns:** Date | Invoice No | Party | Total Sale Amount | Profit(+)/Loss(−) | Details "Show >" (expands to item-level cost and profit).
- A **Summary** block at the bottom.
- **Exports:** XLS, Print.

**Profit & Loss** [V screenshots]
- **Filters:** From/To; **View: Vyapar or Accounting** (accounting view is T-format or vertical).
- **Lines, in order:**
  - Sale (+), Credit Note (−), Sale FA (+), Purchase (−), Debit Note (+), Purchase FA (−)
  - Direct Expenses (−): Other Direct Expenses, Payment-in Discount
  - Tax Payable (−): GST, TCS, TDS
  - Tax Receivable (+): GST, TCS, TDS
  - Opening Stock (−), Closing Stock (+), Opening Stock FA (−), Closing Stock FA (+)
  - **Gross Profit**
  - Other Income (+)
  - Indirect Expenses (−): Other Expense, Loan Interest, Loan Processing Fee, Loan Charges
  - **Net Profit**
- **Exports:** XLS, Print.
- Source: [P&L guide](https://vyaparapp.in/guides/how-to-check-profit-and-loss-report-in-vyapar).

**Sale Aging** (desktop list) [V screenshot]
- **Filters:** Firm, "Report by" (Today…), Date.
- **Pie chart** of buckets: Current, 1-30, 31-45, 46-60, Over 60.
- **Columns:** Party | Current | 1-30 Days | 31-45 Days | 46-60 Days | Over 60 Days | Total | ">" drill-down.
- Shows "Unused Payments & Open Cr Notes" and "Total Payable".
- Group/duration filters; a reminder arrow per party and a bulk reminder icon.
- **Exports:** Excel/PDF.
- Ageing is by **due date** when due dates are on ([overdue video](https://vyaparapp.in/videos/how-to-track-overdue-payments)).

**Cashflow** [V screenshot]
- **Filters:** period + Between, ALL FIRMS; **Opening Cash-in-Hand** shown; a "Show zero amount transaction" tick box.
- **Columns:** Date | Ref No. | Name | Category | Type | Cash In | Cash Out | Running Cash-in-Hand | Print/Share | ⋮.
- **Exports:** Excel, Print.

**Trial Balance** [V text] (premium)
- Custom period; "Show working trial balance"; "Show 0 balances account".

**Balance Sheet** [V screenshot] (premium)
- **Filters:** Period (Custom range); a **Horizontal/Vertical** toggle.
- **Assets:** Fixed, Non-current, Current (Sundry Debtors, Input Duties & Taxes, Bank Accounts, Cash Accounts, Other Current Assets, Stock-in-hand).
- **Equities & Liabilities:** Capital (Owner's Equity; Reserves & Surplus: Net Income, Revaluation Reserve, Retained Earnings), Long-term liabilities, Current liabilities (Sundry Creditors…).
- Grand totals; collapsible groups.
- **Exports:** PDF, XLS ([guide](https://vyaparapp.in/guides/how-to-check-your-balance-sheet-in-vyapar)).

### 1.2 Party reports

Descriptions are from Vyapar's [feature list](https://vyaparapp.in/blog/vyapar-app-complete-feature-list-all-about-your-favorite-billing-software/) [V]. Columns not seen on screen are marked [K].

**Party Statement**
- "All transactions made with a particular party." Filters: party picker and period.
- **Columns [K]:**
  - Vyapar view: Date | Txn Type | Ref No | Payment Type | Total | Received/Paid | Txn Balance | Receivable/Payable running balance.
  - An Accounting (debit/credit/running) view.
- **Footer totals [K]:** sale, purchase, money in, money out, closing balance.
- Print and Excel. Can be sent to the party as an account statement ([tutorial](https://www.youtube.com/watch?v=g3XReu9ZfOs) [V title]).

**Party wise Profit & Loss** (premium)
- "Total profit against the party for total sale."
- **Columns [K]:** Party | Phone | Total Sale | Profit/Loss. Filters [K]: date, party group.

**All Parties**
- "Each party's dues (payable/receivable) on any given date." Mobile [V, official thumbnail]:
  - **Filters:** a **Date Filter** tick box + date (as-of); **Show:** All Parties / Receivable / Payable; **Group:** All…; a **"Show 0 balance party"** tick box.
  - **Columns:** Party Name | Balance; header totals **Total Receivable / Total Payable**; PDF and XLS.
- Desktop: a search box and Excel/Print ([AR/AP video](https://vyaparapp.in/videos/how-to-manage-accounts-receivable-and-payable)).
- Extra desktop columns [K]: Email, Phone, Receivable, Payable, Credit Limit.

**Party Report by Item**
- "Quantity of a particular item sold to/purchased from each party."
- **Columns [K]:** Party | Sale Qty | Sale Amt | Purchase Qty | Purchase Amt. Filters [K]: item, category, date.

**Sale/Purchase by Party**
- Totals per party.
- **Columns [K]:** Party | Sale Amount | Purchase Amount; date and firm filters.
- (Vyapar's own blog wrongly describes this report as orders.)

**Sale/Purchase by Party Group**
- "Total sale & purchase against a group of parties." Party grouping is a Party setting [V].

### 1.3 Item and stock reports

**Stock Summary** [V screenshot]
- **Filters:** All Categories, **Date filter** tick box + date (stock as of a date), **"Show items in stock"**, All Godown.
- **Columns:** # | Item Name | Sale Price | Purchase Price | Stock Qty (negative shown in red) | Stock Value.
- **Total row:** quantity and value.
- **Exports:** XLS, Print.

**Item Report by Party** [V desc]
- Items sold to or bought from a chosen party, with quantities.
- Columns [K]: Item | Sale Qty | Sale Amt | Purchase Qty | Purchase Amt.

**Item Wise Profit & Loss** [V name]
- Profit/loss per item.
- Columns [K]: Item | Sale | Sale return | Purchase | Purchase return | Opening stock | Closing stock | Tax receivable/payable | Net P/L.

**Item Category Wise Profit & Loss** [V, in the desktop list]

**Low Stock Summary** [V desc]
- Items below "Min Stock to Maintain", with quantity and value. Filter by category; Excel/PDF ([guide](https://vyaparapp.in/guides/how-to-set-a-low-stock-alert-in-vyapar)).
- Columns [K]: Item | Min Qty | Stock Qty | Stock Value.

**Item Detail** [V desc]
- For one item: date-wise **sale qty, purchase qty, adjustment qty, closing qty**.
- [K] has a "hide inactive dates" option.

**Stock Detail** [V desc]
- Each item's beginning qty → closing qty.
- [K] adds Qty In, Purchase Amt, Qty Out, Sale Amt.

**Sale/Purchase by Item Category** [V desc]
- Category-wise sale and purchase quantity.

**Stock Summary by Item Category** [V desc]
- Category-wise stock quantity and value.

**Item Batch Report** (premium) [V]
- Current quantity per batch (batch, MRP, mfg/expiry, size).

**Item Serial Report** (premium) [V]
- Current quantity per serial or IMEI.

**Item Wise Discount** [V desc]
- Discount given on sold items.
- Columns [K]: Item | Qty sold | Sale amt | Discount amt | Avg %.

**Stock Transfer Report** (premium) [V]
- Transfers between godowns.

**Manufacturing / Consumption Report** (premium) [V, pricing bundle]

### 1.4 Business status

**Bank Statement** [V desc]
- "On what day you withdrew or deposited."
- Columns [K]: Date | Description | Withdrawal | Deposit | Balance, per bank account.

**Discount Report** [V desc]
- Per party: discount you gave on sales, and discount you received on purchases.

### 1.5 Taxes and GST (with Pakistan mapping)

**Tax Report** [V]
- Purchase tax paid and sales tax collected.
- [K] per party.
- **PK mapping:** an input vs output sales-tax register.

**Tax Rate Report** [V]
- Tax collected and paid per rate.
- **PK mapping:** split by 18%, reduced rates, exempt, zero, 4% further tax and Third-Schedule items.

**GSTR-1** [V screenshot]
- **Filters:** From/To Month; "Consider non-tax as exempted".
- **Tabs:** Sale / Sale Return.
- **Columns:** GSTIN/UIN | Party | Invoice No | Date | Value | Tax Rate | Cess Rate…
- **Exports:** **JSON**, XLS, Print.
- **PK mapping:** sales tax return **Annex-C** (sales register). BL M12 notes it is not built.

**GSTR-2 / GSTR-3B / GSTR-9** [V names]
- **PK mapping:**
  - GSTR-2 → Annex-A (purchases/input); BL has a purchase register (M24).
  - GSTR-3B → the monthly return summary (BL "sales tax summary").
  - GSTR-9 → an annual summary.

**Sale Summary by HSN / SAC Report** [V]
- **PK mapping:** sales summary by PCT/HS code (BL items already carry an HS code for FBR DI).

**GST Report / GST Rate Report** [V, desktop list]

**Form 27EQ, TCS Receivable, TDS Payable/Receivable** [V]
- **PK mapping:** withholding registers (s.236G/236H advance tax; Tajir Dost already in BL).

### 1.6 Expense and other income

**Expense** [V screenshot]
- **Filters:** period + Between, ALL FIRMS, ALL USERS; Graph, Excel, Print; an "+ Add Expense" button on the report.
- **Columns:** Date | Exp No. | Party | Category Name | Payment Type | Amount | Balance Due.

**Expense Category Report** [V]
- Totals per category; categories are Direct or Indirect.

**Expense Item Report** [V]
- "What you spent on and how much": expense items with HSN/SAC, quantity and amount.

**Other Income / Other Income Category / Other Income Item** [V]
- The same three levels for income such as rent received or interest.

### 1.7 Sale and purchase orders

**Sale/Purchase Orders (transaction report)** [V]
- All orders in the period.
- [K]: Status filter (Open/Closed/Overdue), due date, advance and balance columns.

**Sale/Purchase Order Item** [V]
- Items ordered, with quantities, in the period.

### 1.8 Loan

**Loan Statement** [V desc]
- "Record of repayments for a loan" (EMI, interest, processing fee, charges, which feed into P&L).

### 1.9 Report-like screens outside the Reports menu

- **Party detail** [V screenshot]
  - Header: name, phone, SMS/WhatsApp/reminder icons.
  - **Columns:** Type | Number | Date | Total | Balance | Due Date | **Status** (Overdue *N* Days, Partial, Used/Unused for Payment-In) | ⋮.
  - Search, print, XLS.
  - The party list shows each balance coloured green (receivable) or red (payable).
- **Item detail** [V screenshot]
  - Header: sale and purchase price (excl. tax), stock quantity, stock value; **ADJUST ITEM**.
  - **Columns:** Type (with godown) | Invoice/Ref | Name | Date | Quantity | Price/Unit | Status (Paid/Unpaid).
  - Search, XLS.
  - A godown selector on the item list.
- **Cash & Bank:** Cash in hand (date-wise cash list), Bank accounts, **Cheques** (open/closed), Loan accounts [V].
- **Dashboard:** cash in hand, stock value, bank balance, "You'll Receive / You'll Pay" lists [V].
- **Bulk Payment Reminder** [V screenshot]
  - Every receivable party with a tick box, sortable by Party/Amount, a WhatsApp icon per row.
  - A **"Send Reminders in Bulk"** button.

### 1.10 Reports other apps have and Vyapar lacks

Findings from the other-apps research; sources inline.

**Fast / medium / slow / non-moving items** (Marg)
- Banded by the **number of sale entries in the last N days**, with user thresholds; filter by rack, company or rate.
- Source: [Marg](https://care.margcompusoft.com/margerp/inventory-reports/1930/1/how-to-view-fast-and-slow-moving-item-report-in-marg-software)

**Dump stock** (Marg)
- Items not sold for N days.

**Stock ageing 0-45 / 45-90 / 90-180 / 180+** (Tally)
- By purchase date or by expiry date.
- Source: [Tally](https://help.tallysolutions.com/stock-ageing-analysis-report-tally/)

**Inventory Aging + ABC classification** (Zoho)

**Reorder Status** (Tally)
- **Columns:** Closing | PO pending | SO due | Net available | Reorder level | Shortfall | Min order qty | Order to be placed.
- Source: [Tally](https://help.tallysolutions.com/reorder-stock-items-reorder-status-and-reorder-quantity/)

**Re-order Management** (Marg)
- 12 ways to calculate the quantity, including sales × days − stock − pending PO.
- A best supplier for each item; POs are generated split by supplier.
- Source: [Marg](https://care.margcompusoft.com/margerp/re-order-management/2343/1/what-is-the-process-of-re-order-in-marg-software)

**Sales by staff / "Created By"** (myBillBook, Swipe), **Sales by Salesperson** (Zoho), **MR-wise / route-wise / operator-wise / payment-mode-by-operator** (Marg)

**Hourly / time-range sales** (Marg)
- With "Issue Time management" switched on.

**"Today's Gross Profit" and bill GP on a hotkey** (Marg, Ctrl+F7)
- Item GP with a "loss-making only" filter.

**Ratio analysis** (Tally)
- GP%, NP%, inventory turnover, receivable days.
- Drill-down to **Ledger Payment Performance**: average days late per customer.

**Cash-flow projection** (Tally)
- Receivables minus payables by due date.

**Daily Summary** (myBillBook)
- Sales, collections, expenses, profit; Today / This Week / custom.

**Receivable ageing with "Not yet due" vs overdue buckets** (myBillBook, Zoho)
- Zoho buckets are configurable, by amount or by count.

**Exception reports** (Tally Ctrl+J)
- Negative stock, negative cash, overdue, cancelled, post-dated.

### 1.11 Vyapar report → BL status → what to build

BL status is per `feature_ledger.yaml`.

**Sale Report (invoice register)**
- BL has: Sales by day, plus a paged sales list.
- Build: an **invoice register** with Received/Balance columns, user/party/payment-mode filters and "vs last period".

**Purchase Report**
- BL has: purchase register (M24).
- Build: add filters and paid/balance columns.

**Day Book**
- BL has it (M8).
- Build: add type and user filters, Money In/Out columns, and a single-date picker.

**All Transactions**
- BL: none.
- Build: a master list with a transaction-type filter and unpaid-only.

**Bill Wise Profit**
- BL: none.
- Build: new. Margin %, a loss flag, and drill-down to lines at average cost.

**Profit & Loss**
- BL has it.
- Build: add custom ranges, a comparison period, and a "Vyapar-style" simple view.

**Sale Aging**
- BL has Udhaar by age (bill date only).
- Build: ageing by **due date**, a "not yet due" bucket, a chart, and per-row and bulk reminders.

**Cashflow**
- BL has the Cash Book.
- Build: add a "show zero" toggle, category and a running balance (verify it is shown).

**Trial Balance / Balance Sheet**
- BL has both (M10).
- Build: a horizontal/vertical toggle.

**Party Statement**
- BL has the PDF (M24).
- Build: an on-screen table with type filters and an Accounting/simple toggle; hide/show entries ([R] request).

**Party-wise P&L**
- BL: none.
- Build: new.

**All Parties**
- BL has Udhaar by age plus Owed to suppliers.
- Build: one screen with Receivable/Payable/All, group, show-zero, as-of date, credit limit.

**Party report by item / Item report by party**
- BL: none.
- Build: new (both directions).

**Sale/Purchase by party / by party group**
- BL: none. Needs **party groups** (area, route, type).

**Stock Summary**
- BL has a stock summary and stock value.
- Build: as-of date, category, godown, "in stock only".

**Item wise P&L / Category P&L**
- BL: none.
- Build: new.

**Low stock**
- BL has it.
- Build: add reorder suggestion → PO.

**Item detail / Stock detail**
- BL has the stock movement for one item.
- Build: a period stock detail (opening, in, out, closing for every item).

**Category sale/purchase and stock**
- BL: none.
- Build: new.

**Batch report / Serial (IMEI) report**
- BL has the expiry list and IMEI tracking.
- Build: a batch-wise stock report; an IMEI sold/unsold report with search.

**Item-wise discount / Discount report**
- BL: none (only the role ceiling).
- Build: new, including **discount by cashier**.

**Stock Transfer report**
- BL has godowns and vans.
- Build: new.

**Bank statement**
- BL has account drill-down (M10).
- Build: present it as a bank statement.

**Tax / Tax rate / GSTR → PK**
- BL has the sales tax summary, Tajir Dost and the purchase register.
- Build: Annex-C sales and Annex-A purchase exports; a rate-wise report.

**Expense / category / item; Other income**
- BL has Expenses by head.
- Build: add a transaction list, a "shop vs ghar" split, and other-income reports.

**Order reports**
- BL has quotation and challan documents.
- Build: open-quotation and challan registers.

**Loan statement**
- BL has user-added accounts (M26).
- Build: optional.

**Manufacturing / consumption**
- BL has BOMs (M17).
- Build: a production-run register.

### 1.12 Report framework spec to beat Vyapar

Build this once and use it for every report.

**Period presets**
- Today, Yesterday, This week, This month, Last month, This quarter, **This FY (Jul–Jun)**, Last FY, Custom range, "As of" date.
- Remember the last choice per report.

**Filters**
- Firm, User/cashier, Counter/device, Godown/van, Party, Party group/area/route, Item, Category, Payment mode (Cash/JazzCash/Easypaisa/Bank/Cheque/Udhaar), Transaction type, Status (paid/partial/unpaid/cancelled).
- Show **chips** for active filters.

**Summary cards**
- Totals plus **"vs previous period %"** (Vyapar shows "516% vs last month").

**Table**
- Sort any column, **ascending or descending**; oldest-first is a recurring complaint against both Vyapar and Khatabook [R].
- A filter per column, search, and a pinned **total row**.
- **Column chooser** (Vyapar can't do this, per its FAQ).
- **Drill-down** to the document. Tap-and-hold → Reprint / Share / Duplicate / Return.

**Views**
- Table, chart (Vyapar has Graph on Sale and Expense), and a mobile "card" layout.

**Export**
- PDF (A4/A5, Urdu-safe; BL already has this), **XLSX** as well as CSV, and print to thermal for the short reports (Day Book, daily summary).
- Share to WhatsApp; the page header shows "generated by and generated at" (Zoho).

**Navigation**
- **Report search box, favourites/pins, recently used** (absent in Vyapar as far as I could verify; present in Zoho).
- Saved views ("my Monday udhaar list").

**Permissions**
- Cost and profit columns hidden by role (Marg can hide "Today's GP" from a user).

---

## 2. Invoice handling in Vyapar (and what others do)

**Right after saving** [V screenshot, ["share instantly"](https://vyaparapp.in/use-cases/share-invoices-instantly)]
- A **Preview** screen (setting "Enable Invoice Preview").
- **Theme list:** Tally Theme, GST Theme 1/3, Double Divine, French Elite, Landscape 1/2, Vintage themes, plus a colour palette.
- **Share Invoice:** WhatsApp, Gmail, Message (SMS), Vyapar (its network).
- **Download PDF, Print Invoice (Thermal), Print Invoice (Normal).**
- A "Do not show invoice preview again" tick box; **Save & Close**.

**Reopening later** [V]
- Every list (Sale list, Sale report, Day Book, All Transactions, party detail) has per-row **Print** and **Share** icons and a **⋮** menu.
- **⋮ items [K, verify]:** View/Edit, Cancel Invoice, Delete, Duplicate, Open PDF, Preview, Print, Preview as Delivery Challan, Convert to Return, Receive Payment, View History (when audit trail is on).
- Android: Sales → select invoice → ⋮ → "Convert" options [K].

**Sharing later** [V]
- A PDF on WhatsApp in one tap.
- An SMS with a **web invoice link** (opens in any browser; needs a server).
- "Share invoice as Image" setting.
- Automatic transaction messages for Sale, Purchase, Payment-In and Sale Return:
  - can include the party's **current balance** and the web link;
  - "Send via Vyapar" (WhatsApp first, SMS fallback, free) or the user's own WhatsApp login.
- Source: [transaction messages guide](https://vyaparapp.in/guides/how-to-enable-and-send-transaction-messages-in-vyapar).
- **Complaints** [R]: bills arrive from Vyapar's number and look like spam; Vyapar branding or watermark on free bills.

**Copies and printing** [V titles]
- **Original/Duplicate copies** ([mobile](https://www.youtube.com/watch?v=a1Gn5mrT_ak)).
- **Previous balance printed on the invoice** ([video](https://www.youtube.com/watch?v=KHJitxTtQ5s)).
- **Bulk print invoices** ([video page](https://vyaparapp.in/videos/how-to-print-invoices-in-bulk)).

**Duplicate**
- Duplicate in the ⋮ menu [K].
- Elsewhere: Tally Alt+2; myBillBook and Swipe duplicate (including a cancelled invoice); Zoho Clone [other-apps research].

**Editing**
- Posted bills **are editable in place** [V].
- Optional **"Passcode for edit/delete"** setting ([feature list](https://vyaparapp.in/blog/vyapar-app-complete-feature-list-all-about-your-favorite-billing-software/)).
- The salesman role cannot edit or delete [V].
- Edit rules elsewhere:
  - myBillBook blocks edits once a payment is linked or an e-invoice exists.
  - Swipe blocks edits that drop the total below what's been paid.
  - Marg has an edit window per user and type, auto-freeze after N days, and no edits to bills paid at the cashier.
  - Zoho needs "Allow editing of Sent invoice", and offers record locking and period locking.

**Audit of edits**
- "Audit Trail" is switched on in General Settings. Each transaction then gets **⋮ → View History** showing every change; cancelling or deleting "keeps full history" ([video](https://www.youtube.com/watch?v=TVPBKaVSsTo)) [V].
- It is a premium feature ("Audit Trail & Activity Log") [V].
- Older reviews: "Doesn't have audit log… can't tell if any invoice updated" (2021) [R].
- Elsewhere: Tally Edit Log (red diff between versions; cannot be exported); Zoho "View Versions → Compare" (yellow modified, red removed, green added; cannot be disabled in India).

**Cancel**
- Exists ([tutorial](https://www.youtube.com/watch?v=9dunaQNz-6E)) [V].
- Behaviour [K]: status "Cancelled", amounts out of reports, stock returned, number kept.
- Complaint from before it existed: "no option for cancelling… void" (2023) [R].
- **myBillBook's cancel is the best model** ([source](https://knowledge.mybillbook.in/articles/5125143-how-to-cancel-an-invoice-in-mybillbook)):
  - a **mandatory reason** (Order cancelled / Duplicate / Wrong entry / Other);
  - "CANCELLED" watermark on the PDF; the number is kept; stock comes back;
  - if it was paid at creation, choose an auto credit note or moving the payment to the party's balance;
  - blocked while a separate linked payment exists.

**Delete**
- Deleted bills go to the **Recycle Bin** (Utilities), restorable ([video](https://www.youtube.com/watch?v=Bn3NAiPHPdU)). Restore is **premium** [V]. Retention period: **unknown**.
- Elsewhere: Swipe only lets you delete from the Cancelled tab; Tally either renumbers or keeps the gap and later offers unused numbers; myBillBook deletes leave a gap and can be recovered for a limited time.

**Payment-in against a bill** [V]
- "Link Payment to invoices" setting; status per bill (Paid/Partial/Unpaid/Overdue).
- Party detail shows Payment-In as Used/Unused.
- "Discount during payment" is used to write off bad debt (FAQ).
- [K]: "Receive Payment" in the bill's ⋮ menu.
- Elsewhere: Zoho's "Dissociate & add as credit"; myBillBook's Payment-In Discount; Zoho's excess becomes advance.

**Due dates and reminders** [V]
- Payment Terms (e.g. Net 15) set the due date automatically; overdue status.
- Sale Aging has per-row and bulk reminders.
- Template placeholders [Party Name], [Amount], [Business Name], with Reset Default.
- Bulk sending from Home ⋮ → Payment Reminder (tick list → "Send Reminders in Bulk").
- "Remind for payment due more than N days" plus self-notifications.
- Free SMS from Vyapar.
- Sources: [reminders guide](https://vyaparapp.in/guides/how-to-send-payment-reminders-in-vyapar), [due dates guide](https://vyaparapp.in/guides/how-to-add-due-dates-on-invoices-in-vyapar).

**Recurring invoices** [V]
- Repeat Invoice: frequency, start/end, pause, edit future ones.
- **Requires sync login** ([guide](https://vyaparapp.in/guides/how-to-create-a-recurring-invoice-in-vyapar-app)).

**BL today**
- Void/return by reversal, gap-free numbers, reprint "through a different door", receipt shared as PDF, payments settle oldest-first, reminders by WhatsApp intent.
- **Missing:** duplicate/clone, cancel reason codes and watermark (verify), per-bill history view, a "correct & reissue" flow (cancel + clone pre-filled), a bulk reminder queue, due dates/terms, and recurring bills.

---

## 3. Creating a party or item while billing

**Vyapar party** [V transcript and screenshot]
- In the sale form's **Customer\*** field: "If it's a new customer, type the name to create one, and enter details like phone and address."
- A **Phone No.** field sits beside it, with a Billing Address box (Remove/Change).
- For an existing party, **"BAL: 6122"** shows under the name.
- The party is created on Save.
- **Complaints** [R]: typos create duplicate parties "with new balance"; two customers can't share a name.

**Vyapar item** [V screenshot, R]
- **Line columns:** Item | Item code | HSN | Description | Batch | Model | Exp | Mfg | Size | Qty | Unit | Price/Unit (with/without tax) | Discount %/amt | Tax %/amt | Amount.
- An item name not in the master is **created on save**. Mis-taps "create a new item, so stock is always minus" (2024) [R].
- The new item gets no cost price, so profit reports are wrong (inference).
- Settings: "Update Sale Price from TXN", party-wise item rate (premium), free-quantity column, "Show profit while making sale invoice" (premium).

**Zoho**
- Inline **"+ New Customer"**, **"+ Add New Item"**, **"+ New Tax"**, **"+ New Payment Term"** inside the invoice form.
- The customer's **Remarks** show under the customer field while billing ([source](https://www.zoho.com/invoice/help/invoice/new-invoice.md)).

**myBillBook** (form fields from its web app)
- **Party:**
  - Name\*, type, category, mobile, **opening balance with "I Receive/I Pay"**, address, **credit period + credit limit**.
  - Warns **"One or more party exists with same number. Ignore to create anyway."**
  - Save / Save & New.
- **Item:**
  - Name, category, sale and purchase price (each with/without tax), tax, unit + alternate unit with conversion.
  - **Opening stock**, low-stock level, code/barcode, MRP, **wholesale price + minimum quantity**.

**Khatabook / OkCredit**
- Name + optional phone (or from contacts), then straight to entry.

**Tally / Marg**
- Tally: Alt+C on any field opens the full master form (nested).
- Marg: F2 opens the full ledger, including credit days, interest %, area/route/salesman, drug licence.

**Recommended BL quick-add**
- **Party:**
  - Name (Urdu or Roman), phone.
  - **Duplicate check** by phone and fuzzy name ("Did you mean Aslam Kiryana?").
  - Optional: opening balance with jama/banam direction, credit days, price tier (retail/wholesale/VIP).
  - Default: customer, retail, no limit.
- **Item:**
  - Name, sale price, unit.
  - Optional: cost price (default: ask once, or "unknown" so profit is flagged), opening stock (default 0, **warn**, never go silently negative), tax class (default from the shop's tax profile), category.
- **Open-price / misc line:** a "loose item" entry ("just type the amount") that is **not** saved as a master, so typos never pollute the catalogue (complaint by Easy Khata users about "3 minutes for 1 kg onions" [R]).

---

## 4. Editing after saving

**Vyapar** [V unless marked]
- **Parties:** every field is editable (party grouping, additional fields, shipping address).
- **Items:** every field; **Adjust Item** (add/reduce with a reason) for stock corrections; bulk item update (premium).
- **Transactions:** sale, purchase, payment in/out, expense, other income, orders, challans are editable and deletable.
  - Gated only by the edit/delete passcode, user roles, and the optional premium audit trail.
  - An update took away expense editing; users complained (2024-08-27, +135) [R].
- **"Verify my data"** utility checks for mismatches.

**Others**
- Khatabook "Data Lock" (a PIN to edit or delete, separate from the app lock).
- OkCredit lets you edit entries but **not the date**.
- Tally: cancel keeps the number; period lock per role ("days allowed for back-dated vouchers").
- Zoho: a period lock date with a reason; record lock.
- Marg: freeze up to a date, a modification window in hours, a "Bill Value Changes" audit report, and a **random stock check** of N items.

**BL**
- Posted documents are immutable and reversed (stronger than Vyapar).
- A party edit keeps what the form doesn't show.
- Items can be edited and archived; an activity log by person.
- **Add:**
  - a per-record history/diff view;
  - a **period lock date** (e.g. the last day close or month end) with an owner override plus a reason;
  - a "Data Lock" PIN for edits to masters;
  - a "bill value changes" report.

---

## 5. User complaints and gaps

### Vyapar (1–2★ n=2,246) [R]

**Paywall creep** (17% overall; 24% in 2025–26)
- Features moved to higher tiers: manufacturing, bulk add, label printing, barcode.
- Renewal "₹8,000 → ₹25,000".
- Editing restricted after expiry. A 7-day trial.

**Support** (13–17%)
- Responsive before purchase, silent after.
- Asked users to install remote-access software; "executives can see our passwords and OTPs".

**Speed, hangs, errors** (about 8%)
- "Loading… Loading…", "Unable to retrieve data. Contact Vyapar Team", desktop lag, forced Gmail sign-in (2026).

**Licence per device; sync unreliable; offline weak**
- "Offline billing not possible" (+115); "it always require internet" (+61).
- The top-voted review (+1,447) is about sync.

**Data loss and backup**
- Restore "please select the correct file"; lost on phone change; a daily backup requested.

**Wrong numbers**
- Split payments (cash + online) wrong in exported reports, and secondary units shown as decimals like "0.4756" (**top recent review, +403**, 2026-09-04).
- GST applied twice. Discount-on-MRP calculated wrong.
- Batch quantities wrong after the year close.
- Negative stock from auto-created items.
- No oldest-first sort.

**Printing**
- Thermal printer failures, a 2-inch layout that wastes paper, uneven page breaks, blank WhatsApp PDFs.

**Missing**
- Journal entry on mobile, roles and audit (older), barcode scan-to-bill without a tap each time.
- Multi-unit "1 box + 2 pcs", multiple price lists, a 10+1 scheme, void, batch editing.
- Van stock per salesman, Excel import of invoices, AI scan of purchase bills.

**UX**
- Too complex ("BillGuru more simple", +186), redesigns break habits, one bill window at a time, no keyboard shortcuts, search breaks on spaces and dots.

**Language**
- English and Hindi only. Urdu was requested (2022-11-24, 2025-05-15).

**Pakistan**
- Licences can't be renewed, the app "not working in Pakistan", "not on Play Store" (2025–26), unverified officially.
- Vyapar still runs [vyapar.pk](https://vyapar.pk/).

### Khatabook [R]
- **Mandatory SMS and location permissions** (2023, +727/+681).
- Automatic SMS to customers with no opt-out (+993).
- **Locked out after a phone change or OTP failure**; India-only OTP shut out Pakistani users (2024).
- SMS capped at 200 a month, then paid coins.
- The list jumps to the top after an edit (+1,976).
- Requests: PDF attachments (+4,383), a delete password and fingerprint lock (+2,250), cash register, expenses.

### myBillBook [R]
- Price ₹1,600 → ₹9,000+ by 2026.
- **Data held or deleted when you don't renew.**
- No real offline mode.
- A salesman can mark bills paid with no trace (+143).
- Payment mode not recorded on credit receipts (+1,519).
- **An old bill's address changes when the party's address is edited** (+550).
- Quantity entered by tapping "+" 500 times.

### OkCredit [R]
- Auto-SMS can't be switched off (+3,292).
- "Syncing failed / no internet" after updates.
- **Customers can add entries to your ledger** (+787).
- Three different balances on three screens (+258).

### Pakistani apps [R]
- **DigiKhata:** offline made Pro-only (May 2026); CNIC/KYC pop-ups; different balances across devices.
- **CreditBook:** online-only; a March 2026 outage; debit/credit columns swapped in PDFs.
- **EasyKhata:** OTP or re-login wipes data (23% of 1–2★); unreadable PDF fonts.
- **Rupin/Udhaar:** unusable at about 180 customers; 200000 shown as 2000; a zero discount line printed on bills.

---

## 6. Top 25 feature ideas to clearly beat Vyapar

All are offline-doable and ranked by impact for kiryana, pharmacy, mobile shop and wholesaler. "BL" gives the current status. Details and sources are in §7 under the same number.

1. **Report framework with filters, custom range, sort and drill-down** (§1.12). Owners ask "what did Aslam buy in Ramzan, cash or udhaar?" and BL can't answer it today.
2. **Find any old bill → reprint, reshare as PDF or image on WhatsApp, Original/Duplicate copy.** "Bill dobara bhej do" (send the bill again) is a daily request. BL: partial.
3. **Bill-wise, item-wise and party-wise profit, plus a "Today's munafa" card.** This is Vyapar's premium hook; give it free. BL: P&L only.
4. **Duplicate a bill / repeat last order, and "correct & reissue"** (cancel + pre-filled copy). Wholesalers rebill the same list weekly; BL's reversal model needs this to feel easy.
5. **Last 5 rates for this party and item at billing.** Bargaining culture; consistent wholesale quoting.
6. **Credit days, due date per bill, and a promise-to-pay (wasooli) date with a local reminder.** Udhaar is the core job; ageing should split not-yet-due from overdue.
7. **Bulk reminder queue in Urdu, Roman Urdu or English via the shop's own WhatsApp/SMS**, with per-customer language and opt-out. Vyapar sends from its own number, which customers think is spam.
8. **All-parties and party-by-item / item-by-party reports, plus party groups** (area, route, type). The wholesaler's daily "who buys what" view.
9. **Stock detail (opening, in, out, closing per item for any period) and category summaries.** Stock reconciliation and theft detection.
10. **Dead, slow and fast stock plus stock ageing.** Cash stuck on shelves is the kiryana's hidden loss. Vyapar doesn't have it.
11. **Shortage list ("*" at the counter) + reorder suggestion → purchase order per supplier on WhatsApp.** Replaces waiting for the order-booker.
12. **Sales by cashier/counter, payment-mode summary, hourly sales.** Owner–staff trust and staffing the rush hours.
13. **Per-bill history with diff, a "bill value changes" report, and a period lock date.** Vyapar charges for the audit trail; BL can lead here.
14. **Cancel with reason codes + CANCELLED watermark + Cancelled tab; recycle bin for masters.** A clean trail when a customer disputes a bill.
15. **Safe inline quick-add of party and item, with a duplicate check, plus a loose-item line.** Speed without Vyapar's duplicate and negative-stock mess.
16. **Daily summary card and Z-style day report**: sales, collections by mode, expenses, profit, items sold. Owner reads it each night; myBillBook and Easy Karyana have it.
17. **Bonus schemes (10+1), quantity-slab and bill-value discount slabs.** Pharma and FMCG trade runs on bonus.
18. **Discount reports (party, item, cashier).** Detects discount leakage at the counter.
19. **Expense category and item reports, "shop vs ghar ka kharcha", other-income reports.** Owners mix home and shop spending.
20. **Settlement discount and bad-debt write-off with a reason, plus a bad-debts report.** Udhaar is often settled "Rs 500 chhor do" (let the Rs 500 go).
21. **Two-unit display everywhere ("2 ctn + 5 pcs", "1 kg 500 g") in bills and reports.** Vyapar's +403 review is exactly this.
22. **Report search, favourites/pins, recently used, saved views.** Faster than Vyapar's long list; Zoho-grade navigation.
23. **Pharmacy pack:** near-expiry by supplier, expiry return-to-supplier, salt/generic search, Schedule B/D register. DRAP record-keeping and expiry losses.
24. **Mobile-shop pack:** IMEI sold/unsold report, IMEI search, warranty, PTA status, qist (instalment) plans. Proves where a phone came from; qist selling is common.
25. **Charts and "vs last period" on reports** (sales trend, top items/customers, receivable pie). Owners read pictures faster than tables.

**Already in BL; market these against Vyapar** (do not rebuild):
- no login, OTP or internet for anything core;
- Urdu rasterised on receipts and in PDFs;
- reverse-never-edit and gap-free numbers;
- credit limit with a named override;
- post-dated cheques and the 489-F notice;
- FEFO batches, IMEI, GS1, scale labels;
- vans; LAN multi-counter sync; Excel import;
- encrypted books; sealed backups;
- FBR DI; "losing a plan locks nothing already made".

---

## 7. Offline-doable features from other apps and from Vyapar complaints (ranked)

Every item below works fully offline on the phone. Numbers 1–25 match §6. The "BL" line says what Bazaar Ledger has today and what to add.

### 1. Report framework
- **From:** Vyapar (filter bar, column funnels, Graph/XLS/Print); Zoho (save view, column chooser, favourites, RTL font, page header); Tally (drill-down to any figure); complaint about no oldest-first sort [R].
- **What exactly:** presets including FY Jul–Jun and Custom; filters for firm, user, counter, godown, party, group, item, category, payment mode, type and status; sorting; a column chooser; drill-down; XLSX, CSV, PDF and thermal output; saved views.
- **Why a PK shop wants it:** accountants want XLSX; owners want "this customer, this month".
- **BL:** 4 presets and no filters → build.

### 2. Bill finder with reprint and reshare
- **From:** Vyapar (per-row print/share, Original/Duplicate copies, previous balance on the bill, bulk print).
- **What exactly:** search by number, party, amount or date; reprint on thermal or A4; share the PDF or image through the WhatsApp intent; print "DUPLICATE"; print the previous balance.
- **Why a PK shop wants it:** customers lose parchis; wholesalers resend bills.
- **BL:** reprint path and PDF share exist → add the finder and the copy label.

### 3. Profit set
- **From:** Vyapar Bill-wise / Party-wise / Item-wise P&L (premium); Marg Ctrl+F7 and "Today's GP"; Swipe (choose the cost basis).
- **What exactly:** per-bill and per-line margin at average cost; a loss-on-bill flag; item, party and category profit; profit hidden by role.
- **Why a PK shop wants it:** *"cost price… to know profit details easily and secretly"* (Easy Khata review).
- **BL:** P&L only → build.

### 4. Duplicate / repeat / correct-and-reissue
- **From:** Vyapar (Duplicate [K]), Tally Alt+2, Zoho Clone, myBillBook, Swipe.
- **What exactly:** clone any bill (including a cancelled one) to a new draft; "repeat last order" for a party; "Correct" = reverse + pre-filled new bill, linked both ways.
- **Why a PK shop wants it:** weekly repeat orders; fixing a typo without re-entering 30 lines.
- **BL:** build.

### 5. Last-deal pop-up
- **From:** myBillBook (last 5 prices over 365 days), Marg Alt+L, Vyapar party-wise rate (premium).
- **What exactly:** when an item is added for a party, show the last 5 rates, discounts and dates; one tap to reuse.
- **Why a PK shop wants it:** bargaining and quoting consistency.
- **BL:** build.

### 6. Credit terms, due dates, promise-to-pay
- **From:** Vyapar payment terms and overdue status; myBillBook credit period; CreditBook udhaar date plus "wasooli" date; Zoho expected payment date ("don't remind until").
- **What exactly:** party default credit days → due date on each bill; record a promise date; a local notification the day before and on the day; ageing by due date with a "not yet due" bucket.
- **Why a PK shop wants it:** salary-day settlements; "Friday ko de dunga" (I'll pay on Friday).
- **BL:** ageing by bill date only → build.

### 7. Bulk reminder queue
- **From:** Vyapar bulk reminders; OkCredit (free plan sends from the phone's own SIM); Khatabook (language set per customer); CreditBook (own-SIM SMS).
- **What exactly:**
  - pick the overdue list → send one by one through WhatsApp or SMS intents (Play restricts the `SEND_SMS` permission, so the user taps Send);
  - Urdu-script, Roman Urdu or English templates with {name} {amount} {due} {shop} {JazzCash/IBAN};
  - per-customer opt-out; a log of who was reminded.
- **Why a PK shop wants it:** chasing 40 names an evening; Urdu messages are requested.
- **BL:** single-party intent → add the queue and templates.

### 8. Party report pack
- **From:** Vyapar (All Parties with receivable/payable/group/show-zero/as-of; Party report by item; Item report by party; Sale/Purchase by party and by group).
- **What exactly:** as listed, plus party groups (area, route, mohalla, type).
- **Why a PK shop wants it:** wholesalers' route and customer analysis.
- **BL:** partial → build.

### 9. Stock detail and category reports
- **From:** Vyapar Stock Detail, Item Detail, category summary; Zoho Stock Summary (opening/in/out/closing).
- **What exactly:** a period table per item of opening, purchases, sales, returns, adjustments, transfers and closing (quantity and value); category roll-ups; as-of-date stock.
- **Why a PK shop wants it:** monthly stock-taking and spotting theft or wastage.
- **BL:** per-item movement only → build.

### 10. Dead / slow / fast stock and stock ageing
- **From:** Marg (bands by number of sales in N days; dump stock), Tally (stock ageing by purchase or expiry date), Zoho (Inventory Aging, ABC), BUSY (Live/Dead stock).
- **What exactly:** user thresholds; a "not sold since" date; value tied up per band.
- **Why a PK shop wants it:** frees cash and drives discount clearance.
- **BL:** build.

### 11. Shortage list and reorder → PO
- **From:** Marg ("*" shortage at the counter; 12 reorder methods; best supplier; POs split by supplier); Tally Reorder Status; MediStock "daily wishlist" shared with distributors; Vyapar has only the low-stock list.
- **What exactly:** suggested quantity = average daily sales × cover days − stock − open PO; group by last supplier; send as a WhatsApp text or PDF; record the quoted rate and compare it at receipt.
- **Why a PK shop wants it:** order-bookers visit on fixed days; catches "invoice and app rate is different" (complaint against Tajir).
- **BL:** low-stock list → build.

### 12. Staff and time analytics
- **From:** myBillBook staff-wise sales; Swipe "Created By"; Marg operator, terminal, MR and payment-mode-by-operator; Marg time-range sales.
- **What exactly:** sales, discounts, voids and cash short/over per cashier and counter; an hourly heat-map.
- **Why a PK shop wants it:** trust in hired staff; staffing evening peaks.
- **BL:** every row carries its user → build the reports.

### 13. Audit diff and period lock
- **From:** Vyapar View History (premium); Tally Edit Log (red diff); Zoho version compare and lock date; Marg "Bill Value Changes", edit window, auto-freeze.
- **What exactly:** a per-record timeline (who, when, what changed); a report of changed or voided bills above Rs X; a lock date after day close with an owner override and reason.
- **Why a PK shop wants it:** salesman fraud is a top fear (myBillBook +143 review).
- **BL:** activity log → add the diff, the report and the lock.

### 14. Cancel UX
- **From:** myBillBook (reason codes, CANCELLED watermark, credit-note choice); Swipe (Cancelled tab with restore, delete only from there); Tally (cancel keeps the number).
- **What exactly:** reason codes are mandatory; the watermark goes on the PDF and the reprint; a Cancelled filter; masters go to a 30-day trash (Business Khata).
- **Why a PK shop wants it:** customer disputes; FBR Rule 150R requires logging cancellations.
- **BL:** reversal exists → add reasons, watermark, tab.

### 15. Safe inline quick-add
- **From:** Vyapar type-to-create (fast but silent → duplicates [R]); myBillBook duplicate-phone warning; Zoho "+ New" inside dropdowns; Business Khata amount-only line.
- **What exactly:** see §3.
- **Why a PK shop wants it:** speed without polluting the catalogue.
- **BL:** verify current flow.

### 16. Daily summary and Z report
- **From:** myBillBook Daily Summary; Easy Karyana "net cash calculator"; Marg Day Wise Summary.
- **What exactly:** one screen and one 58mm print: bills, sales, returns, collections by mode (cash, JazzCash, Easypaisa, bank, cheque), udhaar given and recovered, expenses, profit, items sold, cash expected vs counted.
- **Why a PK shop wants it:** the nightly galla (cash drawer) check.
- **BL:** has day close → add the summary print.

### 17. Schemes and slabs
- **From:** Marg bonus (Full/Half/All modes), bill-value discount slabs, quantity-slab rates; Vyapar's free-quantity column and "10+1" requests [R].
- **What exactly:** item-level "buy X get Y" with stock deducted; slab pricing; scheme received on purchases flows into cost.
- **Why a PK shop wants it:** distributor and pharma practice.
- **BL:** build.

### 18. Discount reports
- **From:** Vyapar Discount Report and Item-wise Discount.
- **What exactly:** discount given per party, item and cashier; discount received from suppliers.
- **Why a PK shop wants it:** leakage control.
- **BL:** role ceiling exists → build the reports.

### 19. Expense and other-income depth
- **From:** Vyapar expense category/item and other-income reports; DigiKhata Expense Book; the "ghar ka kharcha" request.
- **What exactly:** transaction list; category and item totals; a personal-drawings tag; recurring rent and bijli (electricity) reminders.
- **Why a PK shop wants it:** owners mix shop and home money.
- **BL:** Expenses by head → extend.

### 20. Write-off and settlement discount
- **From:** Vyapar "discount during payment" (its bad-debt method); myBillBook Payment-In Discount; Zoho write-off with reason and cancel write-off.
- **What exactly:** settle a balance with a discount or a write-off with a reason; a Bad Debts report.
- **Why a PK shop wants it:** "baqi chhor do" (forget the rest) settlements.
- **BL:** build.

### 21. Two-unit display
- **From:** Vyapar complaints (decimals like "0.4756", +403; "1 box + 2 pcs"); Easy Karyana carton calculator.
- **What exactly:** show quantity as major + minor unit in bills, stock and reports; enter "2 ctn 5 pcs".
- **Why a PK shop wants it:** carton/loose selling.
- **BL:** unit conversion exists → verify the display.

### 22. Report navigation
- **From:** Zoho (search, favourites); Tally (Go To, saved views).
- **What exactly:** a search box on the Reports home; star to pin; a "Recent" row; a "Today" dashboard tile.
- **Why a PK shop wants it:** 40+ reports on a phone.
- **BL:** build.

### 23. Pharmacy pack (rest)
- **From:** Marg (near-expiry by supplier, expiry return note, Hold/Ban a batch, salt search); HysabOne (salt/formula search); Punjab Drug Sale Rules (Schedule B/D register fields).
- **What exactly:** an expired-before-MM/YY list → bulk return to the original supplier with a return letter; generic/salt search with substitutes; a Schedule register (patient, prescriber, batch, balance).
- **Why a PK shop wants it:** expiry losses and legal records.
- **BL:** FEFO + expiry list → build the rest.

### 24. Mobile-shop pack
- **From:** HysabOne (IMEI history, repair job cards, qist plans); PTA DIRBS (SMS the IMEI to 8484); Vyapar Item Serial Report.
- **What exactly:**
  - IMEI sold/unsold/returned report and IMEI search;
  - warranty end date;
  - used-phone purchase with the seller's CNIC and photo;
  - PTA status field plus an SMS intent to 8484;
  - qist (instalment) schedule, overdue list, guarantor.
- **Why a PK shop wants it:** stolen or blocked phone disputes; instalment selling.
- **BL:** IMEI tracking → build the rest.

### 25. Charts and comparisons
- **From:** Vyapar Graph view and "% vs last month"; Sale Aging pie.
- **What exactly:** a trend line, top-10 bars and an ageing pie, rendered locally.
- **Why a PK shop wants it:** low-literacy-friendly.
- **BL:** build.

### 26. Data Lock PIN for edits and deletes
- **From:** Khatabook (separate from the app lock; +2,250 request); Vyapar edit/delete passcode.
- **What exactly:** a PIN to edit masters or delete anything.
- **Why a PK shop wants it:** family or staff use one phone.
- **BL:** roles exist → add the lock.

### 27. Customer payment performance
- **From:** Tally Ledger Payment Performance; OkCredit defaulter list.
- **What exactly:** average days late per customer; a defaulter list; "expected collections this week".
- **Why a PK shop wants it:** decide who gets more udhaar.
- **BL:** build.

### 28. Collection sheet for the recovery man
- **From:** Marg Bill Tagging.
- **What exactly:** assign a party's open bills to a recovery man as a numbered sheet; on return mark Paid / Partial / "shop closed".
- **Why a PK shop wants it:** wholesalers send a recovery man on routes.
- **BL:** vans exist → build.

### 29. Transporter copy and copy labels
- **From:** myBillBook (transporter copy hides prices; Original/Duplicate/Triplicate).
- **What exactly:** a price-less copy for the goods-transport receipt (bilty) or delivery.
- **Why a PK shop wants it:** wholesale dispatch through transport adda (depot).
- **BL:** build.

### 30. Bill keeps its own snapshot
- **From:** myBillBook complaint (+550: an old bill's address changed when the party was edited).
- **What exactly:** the party name, address, NTN and prices are frozen on each bill.
- **Why a PK shop wants it:** legal correctness.
- **BL:** likely already true (immutable docs) → test it.

### 31. Split-payment correctness in exports
- **From:** Vyapar's top 2026 complaint (+403).
- **What exactly:** each tender is its own row and column in every report and export.
- **Why a PK shop wants it:** cash + JazzCash split bills are common.
- **BL:** split tender is posted separately (M0) → test the reports.

### 32. Never-silent negative stock
- **From:** Vyapar complaints (700 kg sold against 600 kg in stock with no warning, from a Pakistani reviewer).
- **What exactly:** warn or block per item (BUSY: No action / Warn / Don't allow).
- **Why a PK shop wants it:** stock truth.
- **BL:** verify.

### 33. Performance at scale
- **From:** Rupin unusable at about 180 customers; Vyapar "Loading…".
- **What exactly:** indexed lists; ship a 50k-bill test dataset.
- **Why a PK shop wants it:** wholesalers with years of data.
- **BL:** paging exists → benchmark.

### 34. Readable Urdu
- **From:** Rupin "font too small"; DigiKhata Nastaliq request; EasyKhata unreadable PDF fonts.
- **What exactly:** a font-size setting, Nastaliq in PDFs, an Urdu/English toggle per document.
- **Why a PK shop wants it:** older owners.
- **BL:** Urdu PDF exists → add the size setting.

### 35. Quantity-only khata lines
- **From:** a DigiKhata request.
- **What exactly:** "10 kg ghee given, rate later", priced at settlement.
- **Why a PK shop wants it:** mandi and grocery practice.
- **BL:** build.

### 36. Payment details on bills and reminders
- **From:** Rupin (payment QR and bank details on invoices); Vyapar bank details or QR on invoice.
- **What exactly:** print the shop's own static Raast/JazzCash QR (scanned once), IBAN and wallet number.
- **Why a PK shop wants it:** pushes digital payment with no API.
- **BL:** "merchant's own alias" exists → extend to reminders.

### 37. Importer from Vyapar and Khatabook exports
- **From:** the stranded Pakistani Vyapar users [R]; Vyapar can export items and reports to Excel [V].
- **What exactly:** map Vyapar Excel item, party and report exports into BL masters and opening balances.
- **Why a PK shop wants it:** acquisition.
- **BL:** Excel import exists → add Vyapar column presets. Importing Vyapar's `.vyb` backup format is uncertain.

---

## 8. Per app: what to copy

- **Vyapar**
  - Report shell: filter bar, column funnels, summary cards with % change, Graph/XLS/Print.
  - Sale Aging pie with reminders; bulk reminder tick list.
  - Preview screen with share targets and theme picker.
  - Party detail Status column (Overdue N days, Used/Unused).
  - Item detail with Adjust Item; Original/Duplicate copies; previous balance on the invoice.
  - Recurring bills; loyalty points.
- **Khatabook:** Data Lock PIN; per-customer SMS language; delete password; restore deleted entries; attachments on entries.
- **OkCredit:** a per-entry SMS receipt from the phone's own SIM (can be switched off per customer); defaulter list; monthly collection report. **Avoid:** auto-messages with no off switch; letting customers add entries.
- **myBillBook**
  - Cancel model (reasons, watermark, credit-note choice); duplicate-phone warning.
  - Last 5 prices; staff-wise sales; Payment-In Discount.
  - Transporter copy; Daily Summary; wholesale price with minimum quantity.
  - Four ways to value stock (cost or sale price, with or without tax).
- **Swipe:** Cancelled tab with restore, delete only from there; cost basis choice for profit; "Created By" filter; per-invoice activity tab.
- **Zoho Invoice/Books**
  - Void vs delete; record lock and period lock with reasons; version diff.
  - Credit limit warn-or-restrict with "raise limit & save"; promise-to-pay date.
  - Dissociate a payment and keep it as credit; write-off with a reason.
  - Configurable ageing; inventory ageing; ABC; report favourites and RTL font; customer Remarks at billing.
- **Marg ERP**
  - Ctrl+F7 bill GP and Today's GP; fast/slow/dump stock; shortage "*" and reorder engine.
  - Expiry returns by supplier; salt search; Schedule register.
  - Bonus schemes; credit control (warning and hard limits by amount, bill count or days; temporary limit; stop billing after a bounced cheque).
  - Bill tagging for collection; edit windows and auto-freeze; random stock check; cashier mode (salesman bills, cashier collects).
- **BUSY:** negative/critical stock action per item (No action / Warn / Don't allow); live/dead stock (partly researched).
- **TallyPrime:** cancel-keeps-number; Edit Log diff; Reorder Status; Stock Ageing; Ratio Analysis with payment performance; exception reports; Stock Query card; drill-down everywhere.
- **EasyKhata:** stays free and offline (it is winning refugees from DigiKhata and CreditBook); dead simple.
- **DigiKhata:** Staff Book (attendance, salary, advance); Bank Book and Cash Book; staff permission levels. **Avoid:** forced online, CNIC prompts.
- **Rupin / Udhaar Book:** tax-ready invoice maker with payment QR; payroll. **Avoid:** zero discount line printed; redesigns that drop the cash in/out view.
- **CreditBook:** udhaar date plus wasooli date; regional languages (Sindhi, Pashto, Punjabi). **Avoid:** going online-only.
- **Business Khata (PK, 2026):** amount-only sale; weight-based pricing; payments auto-split oldest-first; photo and voice notes; 30-day trash; ESC/POS 58/80mm with auto-cut.
- **Easy Karyana (PK):** carton calculator for per-piece cost; end-of-day net-cash calculator; cash / udhaar / online breakdown.
- **Xona / Quickro / Posill (PK-used POS):** 58/80mm return slips; Urdu printed as an image (Posill's selling point; BL already does it); "data stays on device unless you back it up".
- **HysabOne:** pharmacy salt search and near-expiry alerts; mobile-shop IMEI history, repair job cards, qist plans.
- **MediStock:** daily wishlist sent to distributors.
- **Hisab Kitab, Bahi/Moneyview Khata:** not researched (only package names found).

---

## 9. Later (needs a server); keep out of the main list

- Real-time cloud multi-device sync and a web/PC dashboard. LAN sync is already offline in BL.
- Automatic cloud backup on our own servers. Drive backup is already built in BL (M20).
- Web invoice links; customer portal / "live khata" links; shared B2B ledgers.
- Server-sent SMS gateway with a masked sender ID, WhatsApp Business API auto-messages, IVR call reminders, scheduled report emails.
- Payment links, dynamic Raast QR with reconciliation, wallets, card or NFC acceptance, lending.
- FBR/PRAL live posting is already built in BL as M19 and needs internet. Online PTA DIRBS API; NTN/STRN lookup.
- Online medicine database and DRAP price updates; distributor price-list sync; B2B ordering (Tajir, Bazaar Pro type).
- AI or OCR scanning of purchase bills in the cloud. On-device ML Kit OCR could be offline: unverified.
- Voice entry through a cloud assistant (EKhata-style). Whether Urdu speech recognition works offline on-device is unverified.
- Report share links with a PIN (Swipe); "Viewed" tracking of sent invoices.

---

## 10. Not verified / gaps

- **Vyapar items not confirmed on screen [K]:**
  - the exact columns of Party Statement, Party-wise P&L, Party/Item-by-party, Item-wise P&L, Item-wise Discount, Bank Statement, Tax reports, Order reports, Loan Statement;
  - the bill ⋮ menu items;
  - cancel behaviour details;
  - Recycle Bin retention period;
  - crown icons, search and favourites on the mobile Reports screen.
- **Screenshots are desktop.** The mobile app shows fewer columns, with PDF/XLS icons in the top bar.
- **Vyapar FAQ vs POS guide disagree on weighing scales.** The FAQ says weighing-scale input is unavailable; the newer POS guide says desktop POS auto-reads a USB/Bluetooth scale.
- **Vyapar pricing:** Silver from about ₹3,399/yr desktop and ₹4,010/yr desktop+mobile ([itforsme](https://www.itforsme.in/pricing/vyapar-india)). Gold and Platinum figures from aggregators were inconsistent.
- **Play listing (scraped 2 Oct 2026):** 10M+ installs, 4.82★, 195,485 ratings, v29.4.0.
- **No Reddit, Quora or YouTube-comment data.** Reddit was blocked to both search and direct fetch. Reviews are from Play, Capterra and Trustpilot only.
- **Not checked:** KP and Balochistan service-tax rates; whether further tax remains 4% in FY2026-27; the Finance Act 2026 Tier-1 turnover test.
