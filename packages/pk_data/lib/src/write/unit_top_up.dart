import 'package:pk_domain/pk_domain.dart';

import 'tx_runner.dart';

/// The units the shipped list has and this firm never had, added (M56).
/// Returns the codes it added, in the shipped order.
///
/// Units are seeded once, on first run, so a unit added to the shipped list
/// later — the carton, the dabba, the packet, the strip and the tablet, in
/// M56 — is missing from every shop set up before it, exactly as Cheques
/// Issued was missing from every chart before M6. The chart is topped up
/// the first time a posting needs an account; a unit is needed before
/// anything is posted — the moment somebody opens the item editor and looks
/// for it — so this runs when the books are opened instead, through the one
/// write path, and says so in the audit trail.
///
/// Only a unit the firm never had is added. One it had and hid was hidden by
/// somebody, and stays hidden. Any conversion that ships with a new unit
/// comes with it; the packs ship with none.
///
/// Run on the phone that keeps the books, never on a counter that joined
/// it: the counter receives the master's units like every other row, and
/// two phones adding a carton apart would each have their own, one of them
/// kept as a clash.
Future<List<String>> addMissingUnits(Tx tx) async {
  final firmId = tx.actor.firmId;
  final everHad = {
    for (final r in await tx.select(
      'SELECT code FROM units WHERE firm_id = ?',
      [firmId],
    ))
      r.read<String>('code'),
  };
  final missing = [
    for (final u in defaultUnits)
      if (!everHad.contains(u.code)) u,
  ];
  if (missing.isEmpty) return const [];

  final idsByCode = {
    for (final r in await tx.select(
      'SELECT id, code FROM units WHERE firm_id = ? AND deleted_at_utc IS NULL',
      [firmId],
    ))
      r.read<String>('code'): r.read<String>('id'),
  };
  String? firstId;
  for (final unit in missing) {
    final id = await tx.insert('units', {
      'code': unit.code,
      'name_en': unit.nameEn,
      'name_ur': unit.nameUr,
      'kind': unit.kind.name,
      // Never a base: the base of every kind shipped from the start, and a
      // second one would redenominate nothing and confuse everything.
      'is_base': 0,
      'decimals': unit.decimals,
    });
    idsByCode[unit.code] = id;
    firstId ??= id;
  }

  final added = {for (final u in missing) u.code};
  for (final c in defaultUnitConversions) {
    if (!added.contains(c.fromCode) && !added.contains(c.toCode)) continue;
    final from = idsByCode[c.fromCode];
    final to = idsByCode[c.toCode];
    if (from == null || to == null) continue;
    await tx.insert('unit_conversions', {
      'from_unit_id': from,
      'to_unit_id': to,
      'factor_thousandths': c.factorThousandths,
    });
  }

  final codes = [for (final u in missing) u.code];
  tx.audit(
    action: 'UNITS_ADDED',
    entityTable: 'units',
    entityId: firstId!,
    summary: 'Units added to the shop: ${codes.join(', ')}',
  );
  return codes;
}
