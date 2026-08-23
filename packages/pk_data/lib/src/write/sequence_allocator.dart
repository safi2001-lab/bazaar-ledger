import 'tx_runner.dart';

/// A freshly allocated document number.
final class DocumentNumber {
  const DocumentNumber({
    required this.formatted,
    required this.series,
    required this.sequence,
    required this.fiscalYear,
  });

  /// `INV-2627-0001`.
  final String formatted;

  /// `INV` — the series, stored separately so reports can group on it.
  final String series;

  /// The raw counter value within the series.
  final int sequence;

  final int fiscalYear;

  @override
  String toString() => formatted;
}

/// Allocates the next document number for a document type, on this device, in
/// this fiscal year.
///
/// Called inside the same transaction as the document it numbers, so a rolled
/// back sale does not burn an invoice number and leave a gap. A gap in an
/// invoice series is not a cosmetic problem in Pakistan: it is the first thing
/// an auditor asks about, and the shopkeeper has to be able to answer.
///
/// Numbers are per DEVICE as well as per series. Two cashiers on the same shop
/// Wi-Fi must never mint the same invoice number, and renumbering after the
/// fact is not an option once the customer has walked out with the paper. Each
/// counter gets its own prefix letter, its own reserved block, or both.
final class SequenceAllocator {
  const SequenceAllocator();

  Future<DocumentNumber> allocate(
    Tx tx, {
    required String docType,
    required int fiscalYear,
  }) async {
    final row = await tx.selectOne(
      '''
      SELECT id, prefix, pad_width, next_value, block_start, block_end
      FROM numbering_sequences
      WHERE firm_id = ? AND doc_type = ? AND device_id = ? AND fiscal_year = ?
        AND deleted_at_utc IS NULL
      ''',
      [tx.actor.firmId, docType, tx.actor.deviceId, fiscalYear],
    );

    if (row == null) {
      throw SequenceNotConfigured(
        docType: docType,
        fiscalYear: fiscalYear,
        deviceId: tx.actor.deviceId,
      );
    }

    final next = row.read<int>('next_value');
    final blockEnd = row.read<int>('block_end');
    if (next > blockEnd) {
      throw SequenceBlockExhausted(
        docType: docType,
        fiscalYear: fiscalYear,
        blockEnd: blockEnd,
      );
    }

    final device = await tx.selectOne(
      'SELECT doc_prefix FROM devices WHERE id = ?',
      [tx.actor.deviceId],
    );
    final devicePrefix = device?.read<String>('doc_prefix') ?? '';

    final series = row.read<String>('prefix');
    final padded =
        next.toString().padLeft(row.read<int>('pad_width'), '0');
    final formatted = '$series-$fiscalYear-$devicePrefix$padded';

    await tx.update('numbering_sequences', row.read<String>('id'), {
      'next_value': next + 1,
    });

    return DocumentNumber(
      formatted: formatted,
      series: series,
      sequence: next,
      fiscalYear: fiscalYear,
    );
  }
}

/// Thrown when a device has no numbering row for a document type and year.
///
/// Reached at the July rollover if nothing created the new year's sequences,
/// which is why first run and the fiscal-year rollover both seed them
/// explicitly rather than creating them lazily at the counter.
class SequenceNotConfigured implements Exception {
  const SequenceNotConfigured({
    required this.docType,
    required this.fiscalYear,
    required this.deviceId,
  });

  final String docType;
  final int fiscalYear;
  final String deviceId;

  @override
  String toString() =>
      'No $docType numbering configured for device $deviceId in FY '
      '$fiscalYear. Set up numbering for the new financial year before '
      'billing.';
}

/// Thrown when a counter has used every number in its reserved block.
class SequenceBlockExhausted implements Exception {
  const SequenceBlockExhausted({
    required this.docType,
    required this.fiscalYear,
    required this.blockEnd,
  });

  final String docType;
  final int fiscalYear;
  final int blockEnd;

  @override
  String toString() =>
      'This counter has used its whole reserved $docType block for FY '
      '$fiscalYear (up to $blockEnd). Widen the block before billing again — '
      'issuing past it would collide with another counter.';
}
