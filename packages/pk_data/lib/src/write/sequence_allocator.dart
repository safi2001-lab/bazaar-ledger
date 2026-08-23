import 'package:drift/drift.dart';

import 'document_series.dart';
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
    var row = await tx.selectOne(
      '''
      SELECT id, prefix, pad_width, next_value, block_start, block_end
      FROM numbering_sequences
      WHERE firm_id = ? AND doc_type = ? AND device_id = ? AND fiscal_year = ?
        AND deleted_at_utc IS NULL
      ''',
      [tx.actor.firmId, docType, tx.actor.deviceId, fiscalYear],
    );

    // The financial year turned over.
    //
    // Pakistan's runs 1 July to 30 June and the series is scoped to it, so a
    // shop set up in August has rows for that year and no other. This used to
    // throw, and nothing anywhere caught it — so on 1 July every shop running
    // this stopped being able to bill, at the counter, on a date known years
    // in advance, for every user at once. The exception's own message told the
    // shopkeeper to set numbering up for the new year through a screen that
    // does not exist.
    //
    // A financial year turning over is not an exceptional condition. It is the
    // calendar, and the row for it is minted here, in the same transaction as
    // the document that needed it, so a rolled back sale does not leave a
    // series behind that nobody used.
    row ??= await _openYear(tx, docType: docType, fiscalYear: fiscalYear);

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
    final padded = next.toString().padLeft(row.read<int>('pad_width'), '0');
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

  /// Opens [docType] for [fiscalYear] on this device and returns its row.
  ///
  /// The reserved block carries forward from the most recent year this device
  /// already has. Two tills on one shop's wi-fi must never mint the same
  /// number, and a new year that reset Counter 2 to the default block would
  /// put it back onto Counter 1's numbers the moment the year turned — the
  /// exact failure the block exists to prevent, arriving annually.
  Future<QueryRow> _openYear(
    Tx tx, {
    required String docType,
    required int fiscalYear,
  }) async {
    final series = DocumentSeries.forType(docType);
    if (series == null) {
      // Still thrown, and it still means something. "The new year has not
      // been opened" is the calendar and is handled above; this is code
      // asking for a kind of document nobody has decided the numbering for,
      // which is a programming error and must not silently invent a prefix.
      throw SequenceNotConfigured(
        docType: docType,
        fiscalYear: fiscalYear,
        deviceId: tx.actor.deviceId,
      );
    }

    final previous = await tx.selectOne(
      '''
      SELECT block_start, block_end
      FROM numbering_sequences
      WHERE firm_id = ? AND doc_type = ? AND device_id = ?
        AND fiscal_year < ? AND deleted_at_utc IS NULL
      ORDER BY fiscal_year DESC
      LIMIT 1
      ''',
      [tx.actor.firmId, docType, tx.actor.deviceId, fiscalYear],
    );

    final blockStart = previous?.read<int>('block_start') ?? 1;
    final blockEnd = previous?.read<int>('block_end') ?? 999999;

    final id = await tx.insert('numbering_sequences', {
      'doc_type': docType,
      'device_id': tx.actor.deviceId,
      'fiscal_year': fiscalYear,
      'prefix': series.prefix,
      'pad_width': series.padWidth,
      // At the start of the block, not at one. A counter whose block begins
      // at 5000 must not mint 1.
      'next_value': blockStart,
      'block_start': blockStart,
      'block_end': blockEnd,
    });

    final opened = await tx.selectOne(
      '''
      SELECT id, prefix, pad_width, next_value, block_start, block_end
      FROM numbering_sequences WHERE id = ?
      ''',
      [id],
    );
    if (opened == null) {
      throw StateError('the numbering row just written cannot be read back');
    }
    return opened;
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
