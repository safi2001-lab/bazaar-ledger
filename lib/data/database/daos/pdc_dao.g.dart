// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdc_dao.dart';

// ignore_for_file: type=lint
mixin _$PdcDaoMixin on DatabaseAccessor<AppDatabase> {
  $PostDatedChequesTable get postDatedCheques =>
      attachedDatabase.postDatedCheques;
  $PartiesTable get parties => attachedDatabase.parties;
  PdcDaoManager get managers => PdcDaoManager(this);
}

class PdcDaoManager {
  final _$PdcDaoMixin _db;
  PdcDaoManager(this._db);
  $$PostDatedChequesTableTableManager get postDatedCheques =>
      $$PostDatedChequesTableTableManager(
          _db.attachedDatabase, _db.postDatedCheques);
  $$PartiesTableTableManager get parties =>
      $$PartiesTableTableManager(_db.attachedDatabase, _db.parties);
}
