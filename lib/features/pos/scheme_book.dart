import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// The shop's schemes as the counter applies them (M43): each item's bonus
/// and quantity slabs, and the shop's discount on a big bill.
///
/// Read once and kept, not asked for line by line: a counter ringing forty
/// items does not make forty queries to learn that none of them has a
/// scheme. Read again whenever the books move (a bill saved, a scheme
/// changed on this phone or arriving from another counter), and while it
/// reads the scheme it had stands, so a line never loses its slab price
/// for the moment it takes to read the settings again.
///
/// Nothing a scheme gives is applied before this has read: an empty book
/// is a shop with no schemes, which prices every line exactly as it was
/// priced before M43.
final schemeBookProvider = FutureProvider<SchemeBook>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return SchemeBook.empty;
  return services.schemeBook();
});

/// The schemes the counter has read, or none yet.
SchemeBook schemesNow(Ref<Object?> ref) =>
    ref.read(schemeBookProvider).valueOrNull ?? SchemeBook.empty;

/// The same, from a widget.
SchemeBook schemesFor(WidgetRef ref) =>
    ref.read(schemeBookProvider).valueOrNull ?? SchemeBook.empty;
