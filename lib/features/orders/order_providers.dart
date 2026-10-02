import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../l10n/app_strings.dart';

/// [kind]'s orders, newest first (M41).
final orderListProvider = FutureProvider.autoDispose
    .family<List<OrderRow>, OrderKind>((ref, kind) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      if (!services.orders.canHandle(kind)) return const [];
      return services.orders.list(kind);
    });

/// One order, opened.
final orderViewProvider = FutureProvider.autoDispose.family<OrderView?, String>(
  (ref, orderId) async {
    ref.watch(refreshTickProvider);
    return ref.watch(appServicesProvider).orders.order(orderId);
  },
);

/// What customers asked for that the shelf did not have.
final shortageProvider = FutureProvider.autoDispose<List<ShortageEntry>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  if (!services.orders.canNoteShortage) return const [];
  return services.orders.shortage();
});

/// What to order now, by supplier.
final reorderProvider = FutureProvider.autoDispose<List<ReorderGroup>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).orders.reorder();
});

/// Where [row] stands, in the shopkeeper's words, and how loudly to say it.
(String, BlChipTone) orderStatusChip(
  AppStrings s,
  OrderRow row,
  BusinessDate today,
) {
  final buying = row.kind == OrderKind.purchase;
  if (row.isLateOn(today)) return (s.orderLate, BlChipTone.bad);
  return switch (row.status) {
    OrderStatus.open => (s.orderStatusOpen, BlChipTone.warn),
    OrderStatus.part => (
      buying ? s.orderStatusPartIn : s.orderStatusPartOut,
      BlChipTone.warn,
    ),
    OrderStatus.done => (
      buying ? s.orderStatusDoneIn : s.orderStatusDoneOut,
      BlChipTone.good,
    ),
    OrderStatus.cancelled => (s.orderStatusCancelled, BlChipTone.neutral),
    OrderStatus.closed => (s.orderStatusClosed, BlChipTone.neutral),
  };
}

/// A date the shopkeeper typed, or null when it is not a real one.
BusinessDate? typedDate(String text) => BusinessDate.tryParse(text.trim());
