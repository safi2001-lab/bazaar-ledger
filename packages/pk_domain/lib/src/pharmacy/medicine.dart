/// What a medicine is, as opposed to what its box calls it (M49).
///
/// A chemist's customer asks for "Panadol", or for "paracetamol", or holds
/// up an empty strip of something the shelf does not have. All three are the
/// same question: is there paracetamol 500 mg here, and at what price. So a
/// medicine carries its salt (the generic name) and strength beside its
/// brand, and the counter finds it by either; two medicines with the same
/// salt and strength are substitutes for each other.
///
/// It also carries who made it, which the Schedule register asks for, and
/// its Schedule class when it is a controlled drug.
library;

import '../catalogue/spelling.dart';

/// A controlled drug's schedule under the Punjab Drug Sale Rules 2007.
///
/// Schedule B and D drugs (narcotic, psychotropic and other controlled
/// medicines) are sold only on a registered practitioner's prescription,
/// and every sale is entered in a register. [other] is a medicine the shop
/// keeps the register for although the rules do not name it: a province
/// whose list differs, or a shop that is careful.
enum ScheduleClass {
  b('B'),
  d('D'),
  other('other');

  const ScheduleClass(this.code);

  /// What the database stores.
  final String code;

  /// Null for anything that is not a schedule: an ordinary medicine, and
  /// every item that is not a medicine at all.
  static ScheduleClass? fromCode(String? code) =>
      values.where((c) => c.code == code).firstOrNull;
}

/// The medicine side of an item. Every field is optional: a shop that only
/// wants to find Panadol by "paracetamol" types the salt and nothing else.
final class MedicineDetails {
  const MedicineDetails({
    this.genericName,
    this.strength,
    this.manufacturer,
    this.schedule,
  });

  /// The salt: "Paracetamol", "Amoxicillin + Clavulanic acid".
  final String? genericName;

  /// "500 mg", "250 mg/5 ml".
  final String? strength;

  /// Who made it: the register's "manufacturer" column.
  final String? manufacturer;

  /// Its schedule, when it is a controlled drug.
  final ScheduleClass? schedule;

  /// Nothing at all: the item is not a medicine, or nobody said what it is.
  bool get isEmpty =>
      _blank(genericName) == null &&
      _blank(strength) == null &&
      _blank(manufacturer) == null &&
      schedule == null;

  /// "Paracetamol 500 mg", or null when no salt is known.
  String? get label {
    final generic = _blank(genericName);
    if (generic == null) return null;
    final dose = _blank(strength);
    return dose == null ? generic : '$generic $dose';
  }

  /// What `items.generic_search` holds for this medicine.
  String? get searchKey => genericSearchColumn(genericName, strength);

  /// The same details, every blank made empty, as the item row stores them.
  MedicineDetails get tidied => MedicineDetails(
    genericName: _blank(genericName),
    strength: _blank(strength),
    manufacturer: _blank(manufacturer),
    schedule: schedule,
  );

  static String? _blank(String? text) {
    final t = text?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

/// `items.generic_search`: the salt and strength as M56's search key
/// ([nameSearchColumn]), or null for an item with no salt.
///
/// The strength is written without its spaces first, so "500 mg" and
/// "500mg" are one strength — the two ways every chemist in the country
/// writes it — and the two items are substitutes. The key is derived, never
/// typed, so two counters holding the same salt and strength hold the same
/// key, and the search for "paracetamol" or "parasitamol 500" finds both.
String? genericSearchColumn(String? genericName, String? strength) {
  final generic = genericName?.trim() ?? '';
  if (generic.isEmpty) return null;
  final dose = (strength ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return nameSearchColumn(dose.isEmpty ? generic : '$generic $dose');
}

/// Who a Schedule medicine was sold to and on whose prescription: the two
/// people the register asks for that the bill does not already know.
final class Prescription {
  const Prescription({
    required this.patientName,
    required this.prescriberName,
    required this.prescriberRegNo,
    this.patientAddress,
    this.reference,
  });

  final String patientName;
  final String? patientAddress;

  /// The doctor, as on the pad.
  final String prescriberName;

  /// The doctor's PM&DC registration number.
  final String prescriberRegNo;

  /// What the shop files the paper under.
  final String? reference;

  /// What is missing for a Schedule sale, by what the register calls it:
  /// empty when the prescription is complete.
  List<String> get gaps => [
    if (patientName.trim().isEmpty) 'patient',
    if (prescriberName.trim().isEmpty) 'prescriber',
    if (prescriberRegNo.trim().isEmpty) "prescriber's registration number",
  ];
}

/// A Schedule medicine on a bill that does not say who prescribed it for
/// whom.
final class PrescriptionRefused implements Exception {
  const PrescriptionRefused({required this.medicines, required this.missing});

  /// The Schedule medicines on the bill.
  final List<String> medicines;

  /// What the prescription is missing; everything when there is none.
  final List<String> missing;

  @override
  String toString() =>
      '${medicines.join(', ')} ${medicines.length == 1 ? 'is a' : 'are'} '
      'Schedule ${medicines.length == 1 ? 'medicine' : 'medicines'}, sold '
      "only on a registered practitioner's prescription. The bill needs the "
      '${missing.join(', ')} for the register.';
}
