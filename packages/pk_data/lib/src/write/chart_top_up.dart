import 'package:pk_domain/pk_domain.dart';

import 'tx_runner.dart';

/// The firm's accounts by system key, with any of [needed] that the shipped
/// chart has and this firm does not added first.
///
/// A chart is seeded once, on first run, so an account added to the shipped
/// chart later — Cheques Issued, in M6 — is missing from every shop set up
/// before it. Rather than a migration that writes accounts for firms and
/// users it cannot see from inside a schema step, the account is added the
/// first time a posting needs it, in the posting's own transaction, through
/// the one write path, and said in the audit trail.
///
/// Only an account the firm never had is added. One it had and archived
/// was archived by somebody, and is left archived: the key stays missing and
/// the writer refuses in words, as it does for a key the shipped chart does
/// not have at all.
Future<Map<String, String>> accountsBySystemKey(
  Tx tx,
  Set<String> needed,
) async {
  final byKey = await _read(tx);
  final absent = needed.where((k) => !byKey.containsKey(k)).toList();
  if (absent.isEmpty) return byKey;

  final everHad = {
    for (final r in await tx.select(
      'SELECT system_key FROM accounts WHERE firm_id = ? '
      '  AND system_key IN (${List.filled(absent.length, '?').join(', ')})',
      [tx.actor.firmId, ...absent],
    ))
      r.read<String>('system_key'),
  };
  for (final key in absent) {
    if (everHad.contains(key)) continue;
    for (final spec in defaultChartOfAccounts.where(
      (a) => a.systemKey == key,
    )) {
      byKey[key] = await _add(tx, spec);
    }
  }
  return byKey;
}

Future<Map<String, String>> _read(Tx tx) async {
  final rows = await tx.select(
    'SELECT id, system_key FROM accounts '
    'WHERE firm_id = ? AND system_key IS NOT NULL '
    '  AND deleted_at_utc IS NULL',
    [tx.actor.firmId],
  );
  return {
    for (final r in rows) r.read<String>('system_key'): r.read<String>('id'),
  };
}

/// Adds [spec], and its parent first if the firm lacks that too.
Future<String> _add(Tx tx, AccountSpec spec) async {
  String? parentId;
  if (spec.parentCode case final parentCode?) {
    final parent = await tx.selectOne(
      'SELECT id FROM accounts WHERE firm_id = ? AND code = ? '
      '  AND deleted_at_utc IS NULL',
      [tx.actor.firmId, parentCode],
    );
    parentId =
        parent?.read<String>('id') ??
        await _add(
          tx,
          defaultChartOfAccounts.firstWhere((a) => a.code == parentCode),
        );
  }
  final id = await tx.insert('accounts', {
    'code': await _freeCode(tx, spec.code),
    'name': spec.nameEn,
    'account_type': spec.type.name,
    'normal_side': spec.normalSide.name,
    'system_key': spec.systemKey,
    'parent_id': parentId,
    'is_direct': spec.isDirect ? 1 : 0,
  });
  tx.audit(
    action: 'ACCOUNT_ADDED',
    entityTable: 'accounts',
    entityId: id,
    summary:
        'Account ${spec.code} ${spec.nameEn} added to the chart, first '
        'needed by this posting',
  );
  return id;
}

/// [code], or the next one up that the firm has not used. Codes are unique
/// per firm, and a shop may have numbered an account of its own 2150.
Future<String> _freeCode(Tx tx, String code) async {
  var candidate = int.parse(code);
  while (await tx.selectOne(
        'SELECT 1 FROM accounts WHERE firm_id = ? AND code = ?',
        [tx.actor.firmId, '$candidate'],
      ) !=
      null) {
    candidate++;
  }
  return '$candidate';
}
