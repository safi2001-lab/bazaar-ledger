// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parties_dao.dart';

// ignore_for_file: type=lint
mixin _$PartiesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PartiesTable get parties => attachedDatabase.parties;
  $CompaniesTable get companies => attachedDatabase.companies;
  PartiesDaoManager get managers => PartiesDaoManager(this);
}

class PartiesDaoManager {
  final _$PartiesDaoMixin _db;
  PartiesDaoManager(this._db);
  $$PartiesTableTableManager get parties =>
      $$PartiesTableTableManager(_db.attachedDatabase, _db.parties);
  $$CompaniesTableTableManager get companies =>
      $$CompaniesTableTableManager(_db.attachedDatabase, _db.companies);
}
