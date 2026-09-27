import 'dart:convert';
import 'dart:math';

import 'package:pk_domain/pk_domain.dart';

import '../write/chart_top_up.dart';
import '../write/tx_runner.dart';

/// The settings key the shop's sync key is kept under.
const syncKeySetting = 'sync.key';

/// The shop's sync key, made the first time the master turns sync on.
///
/// Kept in settings, so it travels to every counter with the rest of the
/// books and a counter that has joined can go on syncing after a restart.
Future<String> ensureSyncKey(Tx tx, {Random? random}) async {
  final held = await tx.selectOne(
    'SELECT setting_value FROM settings WHERE firm_id = ? '
    'AND setting_key = ? AND deleted_at_utc IS NULL',
    [tx.actor.firmId, syncKeySetting],
  );
  if (held != null) return held.read<String>('setting_value');
  final r = random ?? Random.secure();
  final key = base64Url.encode([for (var i = 0; i < 24; i++) r.nextInt(256)]);
  await tx.insert('settings', {
    'setting_key': syncKeySetting,
    'setting_value': key,
  });
  tx.audit(
    action: 'SYNC_TURNED_ON',
    entityTable: 'firms',
    entityId: tx.actor.firmId,
    summary: 'Counters can sync with this phone',
  );
  return key;
}

/// Makes a joining counter's device row, with its own letter for the bill
/// numbers it will print, and returns its id.
///
/// The whole shipped chart is put in the books first. An account added to
/// the chart after the shop was set up is otherwise added the first time a
/// posting needs it — on whichever device that happens — and two tills
/// adding the same account apart would each have their own.
Future<String> admitCounter(
  Tx tx, {
  required String label,
  required String platform,
}) async {
  await accountsBySystemKey(tx, {
    for (final a in defaultChartOfAccounts) ?a.systemKey,
  });
  final used = {
    for (final r in await tx.select(
      'SELECT doc_prefix FROM devices WHERE firm_id = ?',
      [tx.actor.firmId],
    ))
      r.read<String>('doc_prefix'),
  };
  var letter = 'B'.codeUnitAt(0);
  while (used.contains(String.fromCharCode(letter))) {
    letter++;
  }
  final prefix = letter <= 'Z'.codeUnitAt(0)
      ? String.fromCharCode(letter)
      : 'C${used.length}';
  final id = await tx.insert('devices', {
    'label': label,
    'platform': platform,
    'device_role': 'counter',
    'doc_prefix': prefix,
    'is_this_device': 0,
  });
  tx.audit(
    action: 'COUNTER_JOINED',
    entityTable: 'devices',
    entityId: id,
    summary: '$label joined; its bills are numbered $prefix',
  );
  return id;
}
