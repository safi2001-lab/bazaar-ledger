import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../controllers/inventory_controller.dart';

class StockMovementScreen extends ConsumerWidget {
  const StockMovementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(itemStockMovementsProvider());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movement Ledger'),
      ),
      body: movementsAsync.when(
        data: (movements) {
          if (movements.isEmpty) {
            return const Center(
              child: Text(
                'No stock transactions recorded yet.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

          return ListView.separated(
            itemCount: movements.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final movement = movements[index];
              final isPositive = movement.quantityDelta > 0;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                title: Text(
                  movement.movementType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(dateFormat.format(movement.movementDate)),
                trailing: Text(
                  '${isPositive ? '+' : ''}${movement.quantityDelta}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
