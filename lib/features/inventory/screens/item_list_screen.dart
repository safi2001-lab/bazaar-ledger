import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/app_database.dart';
import '../controllers/inventory_controller.dart';
import 'add_edit_item_screen.dart';
import 'stock_movement_screen.dart';

class ItemListScreen extends ConsumerStatefulWidget {
  const ItemListScreen({super.key});

  @override
  ConsumerState<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends ConsumerState<ItemListScreen> {
  String _searchQuery = '';
  bool _onlyLowStock = false;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Catalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Stock Movement Ledger',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StockMovementScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _onlyLowStock ? Icons.warning : Icons.warning_amber_outlined,
              color: _onlyLowStock ? Colors.orange : null,
            ),
            tooltip: 'Filter Low Stock',
            onPressed: () {
              setState(() {
                _onlyLowStock = !_onlyLowStock;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, barcode, or HS code...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                var filtered = items.where((item) {
                  final matchesSearch = item.name.toLowerCase().contains(_searchQuery) ||
                      (item.barcode != null && item.barcode!.toLowerCase().contains(_searchQuery)) ||
                      (item.hsCode != null && item.hsCode!.toLowerCase().contains(_searchQuery));
                  final matchesLowStock = !_onlyLowStock || (item.stockQuantity <= item.minStockAlert);
                  return matchesSearch && matchesLowStock;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _onlyLowStock ? 'No low stock items found!' : 'No items found. Tap + to add items.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final isLowStock = item.stockQuantity <= item.minStockAlert;
                    final isOutStock = item.stockQuantity <= 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isOutStock
                              ? Colors.red.shade300
                              : (isLowStock ? Colors.orange.shade300 : Colors.grey.shade200),
                        ),
                      ),
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (item.trackBatch)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Chip(
                                  label: Text('Rx Batch', style: TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Color(0xFFE0F2FE),
                                ),
                              ),
                            if (item.trackSerial)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Chip(
                                  label: Text('IMEI', style: TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Color(0xFFFEF3C7),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Barcode: ${item.barcode ?? 'N/A'} | Unit: ${item.unit}'),
                            Text('Sale Price: Rs. ${item.salePrice.toStringAsFixed(2)} (Tax: ${item.taxRate}%)'),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${item.stockQuantity} ${item.unit}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isOutStock
                                    ? Colors.red
                                    : (isLowStock ? Colors.orange.shade800 : Colors.green.shade800),
                              ),
                            ),
                            Text(
                              isOutStock ? 'Out of Stock' : (isLowStock ? 'Low Stock' : 'In Stock'),
                              style: TextStyle(
                                fontSize: 11,
                                color: isOutStock ? Colors.red : (isLowStock ? Colors.orange : Colors.grey),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _showQuickAdjustModal(context, item),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditItemScreen()),
          );
        },
      ),
    );
  }

  void _showQuickAdjustModal(BuildContext context, Item item) {
    final qtyController = TextEditingController();
    String reason = 'Stock In';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Adjust Stock: ${item.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Current Stock: ${item.stockQuantity} ${item.unit}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: reason,
                decoration: const InputDecoration(labelText: 'Adjustment Reason'),
                items: const [
                  DropdownMenuItem(value: 'Stock In', child: Text('Stock In (Purchase/Add)')),
                  DropdownMenuItem(value: 'Stock Out', child: Text('Stock Out (Return/Usage)')),
                  DropdownMenuItem(value: 'Wastage', child: Text('Wastage / Damage / Expired')),
                  DropdownMenuItem(value: 'Adjustment', child: Text('Physical Audit Correction')),
                ],
                onChanged: (val) {
                  if (val != null) setModalState(() => reason = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity (${item.unit})',
                  hintText: 'e.g. 10',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final qty = double.tryParse(qtyController.text) ?? 0.0;
                  if (qty > 0) {
                    final delta = (reason == 'Stock Out' || reason == 'Wastage') ? -qty : qty;
                    ref.read(inventoryControllerProvider.notifier).adjustStock(
                          itemId: item.id,
                          quantityDelta: delta,
                          movementType: reason,
                        );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save Stock Adjustment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
