import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'tx_runner.dart';

/// Putting away what the shop no longer uses, and the recycle bin's own
/// reads (M60).
///
/// Items, customers, heads and staff were already hidden by their own
/// writers (M1, M3, M47, M9), and are brought back by them. What had no way
/// to be put away at all — a van, a recipe — is put away here, and here the
/// bin reads, for everything in it, when it went in and who put it there.
///
/// Every act leaves its audit row inside its own transaction, and every
/// hiding code is in `undoingActions`, so under Data Lock each asks for a
/// PIN at commit (M42) without this file knowing a lock exists.
final class DriftHiddenThings {
  DriftHiddenThings(this._db, this._runner);

  final AppDatabase _db;

  /// Asked for each time rather than held, as the attachment store does:
  /// the runner is rebuilt once first run registers the device.
  final TxRunner Function() _runner;

  // -------------------------------------------------------------------------
  // Vans (M18)
  // -------------------------------------------------------------------------

  /// Puts [vanId] away: off the vans list and off the choice of where a
  /// phone sells from. Its sales, loads and settlements stay where they are.
  ///
  /// Refused, in words, while goods are still on it — hidden, they would be
  /// stock nobody can see or sell — and while a phone still sells from it,
  /// which would leave that phone selling from a place that is not on any
  /// list. The same rule M3 keeps for a customer who still owes.
  Future<void> hideVan(ActorContext actor, String vanId) => _runner().run(
    actor,
    (tx) async {
      final van = await tx.selectOne(
        'SELECT name, location_code, is_active FROM vans '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [vanId, actor.firmId],
      );
      if (van == null) throw const VanRefused('That van is not in the books.');
      if (van.read<int>('is_active') == 0) return;
      final name = van.read<String>('name');
      final location = van.read<String>('location_code');

      final onBoard = await tx.selectOne(
        'SELECT COUNT(*) AS n FROM ('
        '  SELECT item_id FROM stock_ledger '
        '  WHERE firm_id = ? AND location_code = ? AND deleted_at_utc IS NULL '
        '  GROUP BY item_id HAVING SUM(qty_delta_thousandths) <> 0)',
        [actor.firmId, location],
      );
      final lines = onBoard?.read<int>('n') ?? 0;
      if (lines > 0) {
        throw VanRefused(
          '$name still has $lines '
          '${lines == 1 ? 'item' : 'items'} on board. Bring the goods back '
          'to the shop before putting the van away, or they are stock '
          'nobody can see.',
        );
      }
      final selling = await tx.selectOne(
        'SELECT COUNT(*) AS n FROM settings '
        "WHERE firm_id = ? AND setting_key LIKE 'device.location.%' "
        'AND setting_value = ? AND deleted_at_utc IS NULL',
        [actor.firmId, location],
      );
      if ((selling?.read<int>('n') ?? 0) > 0) {
        throw VanRefused(
          'A phone still sells from $name. Set that phone back to the shop '
          'floor first.',
        );
      }

      await tx.update('vans', vanId, {'is_active': 0});
      tx.audit(
        action: vanHiddenAction,
        entityTable: 'vans',
        entityId: vanId,
        summary: 'Van $name put away',
      );
    },
  );

  /// Brings [vanId] back onto the vans list, as it was.
  Future<void> restoreVan(ActorContext actor, String vanId) => _runner().run(
    actor,
    (tx) async {
      final van = await tx.selectOne(
        'SELECT name, is_active FROM vans '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [vanId, actor.firmId],
      );
      if (van == null) throw const VanRefused('That van is not in the books.');
      if (van.read<int>('is_active') == 1) return;
      await tx.update('vans', vanId, {'is_active': 1});
      tx.audit(
        action: vanRestoredAction,
        entityTable: 'vans',
        entityId: vanId,
        summary: 'Van ${van.read<String>('name')} back on the list',
      );
    },
  );

  /// The vans put away, the latest first.
  Future<List<HiddenVan>> hiddenVans(String firmId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, name, location_code FROM vans '
          'WHERE firm_id = ? AND deleted_at_utc IS NULL AND is_active = 0 '
          'ORDER BY updated_at_utc DESC, id DESC',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.vans},
        )
        .get();
    return [
      for (final r in rows)
        HiddenVan(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          locationCode: r.read<String>('location_code'),
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // Recipes (M17)
  // -------------------------------------------------------------------------

  /// Puts the recipe [bomId] away: off the recipes list, with every batch
  /// ever made from it untouched in the stock ledger.
  Future<void> hideRecipe(ActorContext actor, String bomId) =>
      _setRecipeHidden(actor, bomId, hidden: true);

  /// Brings the recipe [bomId] back onto the list.
  Future<void> restoreRecipe(ActorContext actor, String bomId) =>
      _setRecipeHidden(actor, bomId, hidden: false);

  Future<void> _setRecipeHidden(
    ActorContext actor,
    String bomId, {
    required bool hidden,
  }) => _runner().run(actor, (tx) async {
    final bom = await tx.selectOne(
      'SELECT name FROM boms WHERE id = ? AND firm_id = ? '
      'AND deleted_at_utc IS NULL',
      [bomId, actor.firmId],
    );
    if (bom == null) {
      throw const AssemblyRefused('That recipe is not in the books.');
    }
    final key = recipeSettingKey(bomId);
    final held = await tx.selectOne(
      'SELECT id, setting_value FROM settings '
      'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
      [actor.firmId, key],
    );
    final was = held != null && _hidden(held.read<String>('setting_value'));
    if (was == hidden) return;
    final value = jsonEncode({'hidden': hidden});
    if (held == null) {
      await tx.insert('settings', {
        'setting_key': key,
        'setting_value': value,
        'value_type': 'json',
      });
    } else {
      await tx.update('settings', held.read<String>('id'), {
        'setting_value': value,
      });
    }
    final name = bom.read<String>('name');
    tx.audit(
      action: hidden ? recipeHiddenAction : recipeRestoredAction,
      entityTable: 'boms',
      entityId: bomId,
      summary: hidden
          ? 'Recipe $name put away'
          : 'Recipe $name back on the list',
    );
  });

  /// The recipes put away, the latest first.
  Future<List<HiddenRecipe>> hiddenRecipes(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT b.id, b.name, i.name AS output_name
          FROM boms b
          JOIN items i ON i.id = b.output_item_id
          JOIN settings s
            ON s.firm_id = b.firm_id AND s.setting_key = 'recipe.' || b.id
           AND s.deleted_at_utc IS NULL
          WHERE b.firm_id = ? AND b.deleted_at_utc IS NULL
            AND json_extract(s.setting_value, '\$.hidden') = 1
          ORDER BY s.updated_at_utc DESC, b.id DESC
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.boms, _db.items, _db.settings},
        )
        .get();
    return [
      for (final r in rows)
        HiddenRecipe(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          outputName: r.read<String>('output_name'),
        ),
    ];
  }

  static bool _hidden(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map && decoded['hidden'] == true;
    } on FormatException {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Who, and when
  // -------------------------------------------------------------------------

  /// When each thing in the bin went in, and who put it there, keyed
  /// `table/id` as the hiding act's audit row names it — the latest such
  /// row, since a thing hidden, brought back and hidden again is in the bin
  /// for the second time.
  ///
  /// Read from the activity log rather than kept on the rows, because the
  /// log is the one record every one of these acts already writes, inside
  /// its own transaction, and cannot skip.
  Future<Map<String, HiddenMark>> hiddenMarks(String firmId) async {
    final codes = hidingActions.keys.toList();
    final marks = List.filled(codes.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT l.entity_table, l.entity_id, l.at_utc,
                 COALESCE(u.name, '') AS by_name
          FROM audit_log l
          LEFT JOIN users u ON u.id = l.created_by
          WHERE l.firm_id = ? AND l.action_code IN ($marks)
          ORDER BY l.at_utc, l.id
          ''',
          variables: [
            Variable<String>(firmId),
            for (final c in codes) Variable<String>(c),
          ],
          readsFrom: {_db.auditLog, _db.users},
        )
        .get();
    return {
      for (final r in rows)
        '${r.read<String>('entity_table')}/${r.read<String>('entity_id')}':
            HiddenMark(
              atUtc: DateTime.fromMillisecondsSinceEpoch(
                r.read<int>('at_utc'),
                isUtc: true,
              ),
              by: r.read<String>('by_name'),
            ),
    };
  }
}
