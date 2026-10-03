/// Bills a shop reporting to FBR made while FBR could not be reached (M59).
///
/// Rule 150XC of the Sales Tax Rules: invoices issued during an internet or
/// power failure "shall be clearly identified as invoices issued in the
/// offline mode and uploaded within 24 hours of restoration" (FBR's POS
/// booklet, 2025; EY's summary of the amendment). A Pakistani counter loses
/// its signal every day — load-shedding takes the router, a basement shop
/// has none — and the bill cannot wait for it.
///
/// So, for a shop that reports (M19):
///
///  * a bill FBR has not yet answered for is marked on its paper and PDF as
///    issued in offline mode, with its FBR number to follow — the mark comes
///    off a reprint once FBR has numbered it. That is every bill printed
///    before FBR answered, which is exactly the bill a customer walks out
///    with when the signal is down;
///  * the moment the connection came back is the first time FBR answered
///    anything after the bill was made — a bill numbered, or a bill refused,
///    which is still FBR answering;
///  * a bill still unanswered 24 hours after that is overdue, and said so on
///    the FBR screen and on Home.
///
/// Nothing new is sent anywhere: this only labels and watches what M19
/// already sends.
library;

/// How long after the connection comes back an offline bill may wait.
const offlineUploadWindow = Duration(hours: 24);

/// What the paper says, line by line, on a bill FBR has not answered for.
const offlineInvoiceMark = [
  'OFFLINE INVOICE',
  'Issued in offline mode',
  'FBR invoice no. to follow',
];

/// When the connection came back for a bill made at [madeAtUtc]: the
/// earliest moment FBR is known to have answered at or after it, from
/// [answeredAtUtc]. Null while FBR has not been heard from since.
DateTime? connectionBackFor({
  required DateTime madeAtUtc,
  required Iterable<DateTime?> answeredAtUtc,
}) {
  DateTime? earliest;
  for (final at in answeredAtUtc) {
    if (at == null || at.isBefore(madeAtUtc)) continue;
    if (earliest == null || at.isBefore(earliest)) earliest = at;
  }
  return earliest;
}

/// Whether a bill is past Rule 150XC's 24 hours: FBR has not answered for it
/// ([status] still `pending`), and the connection came back more than a day
/// ago.
bool offlineOverdue({
  required String status,
  required DateTime? connectionBackAtUtc,
  required DateTime nowUtc,
}) =>
    status == 'pending' &&
    connectionBackAtUtc != null &&
    nowUtc.difference(connectionBackAtUtc) > offlineUploadWindow;
