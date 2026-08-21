import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/hardware_scanner_listener.dart';
import '../../../services/scale_barcode_parser.dart';
import '../../inventory/screens/item_list_screen.dart';
import '../../p2p_sync/screens/p2p_sync_screen.dart';
import '../controllers/cart_controller.dart';

class PosCheckoutScreen extends ConsumerWidget {
  const PosCheckoutScreen({super.key});

  void _handleBarcode(BuildContext context, WidgetRef ref, String rawBarcode) {
    final cartNotifier = ref.read(cartProvider.notifier);

    // 1. Check if it's a GS1 variable-measure scale barcode (Prefixes 20-29)
    final scaleItem = ScaleBarcodeParser.parse(rawBarcode);
    if (scaleItem != null) {
      final weight = scaleItem.weightInKg ?? 1.0;
      final pricePerKg = scaleItem.priceInRupees != null
          ? scaleItem.priceInRupees! / weight
          : 450.0; // Default price if barcode encodes weight

      cartNotifier.addItem(
        CartItem(
          itemId: int.tryParse(scaleItem.plu) ?? (DateTime.now().millisecondsSinceEpoch % 10000),
          name: 'Scale Item (PLU ${scaleItem.plu})',
          barcode: rawBarcode,
          unit: 'Kg',
          unitPrice: pricePerKg,
          quantity: weight,
          taxRate: 0.0,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text('Scale item added: ${weight.toStringAsFixed(3)} Kg (PLU: ${scaleItem.plu})'),
        ),
      );
      return;
    }

    // 2. Standard EAN-13 / Code-128 Barcode Scan
    cartNotifier.addItem(
      CartItem(
        itemId: DateTime.now().millisecondsSinceEpoch % 10000,
        name: 'Scanned Item ($rawBarcode)',
        barcode: rawBarcode,
        unit: 'Piece',
        unitPrice: 150.0,
        quantity: 1.0,
        taxRate: 18.0,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('Scanned barcode: $rawBarcode added to cart'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryEmerald.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.point_of_sale, color: AppTheme.primaryEmerald, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('POS Billing Counter', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Inventory Catalog',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ItemListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Multi-Counter Wi-Fi Sync',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const P2pSyncScreen()),
              );
            },
          ),
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.dangerRed),
              tooltip: 'Clear Cart',
              onPressed: () => cartNotifier.clearCart(),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode',
            onPressed: () {
              _handleBarcode(context, ref, '2000125015004'); // Simulates 1.500 Kg scale item
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: HardwareScannerListener(
        onBarcodeScanned: (code) => _handleBarcode(context, ref, code),
        child: Column(
        children: [
          // Quick Barcode / Product Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Scan barcode or search item name...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: AppTheme.primaryEmerald),
                        onPressed: () {
                          cartNotifier.addItem(
                            CartItem(
                              itemId: DateTime.now().millisecondsSinceEpoch % 10000,
                              name: 'Super Basmati Rice (5 Kg)',
                              unit: 'Bag',
                              unitPrice: 1650.0,
                              quantity: 1.0,
                              taxRate: 0.0,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cart Items List
          Expanded(
            child: cart.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Cart is empty',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Scan barcode or tap + to add items',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${AppConstants.currencySymbol} ${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            // Quantity Controls
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () => cartNotifier.updateQuantity(index, item.quantity - 1),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.remove, size: 18),
                                    ),
                                  ),
                                  Text(
                                    '${item.quantity.toInt()}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  InkWell(
                                    onTap: () => cartNotifier.updateQuantity(index, item.quantity + 1),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.add, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '${AppConstants.currencySymbol} ${item.lineTotal.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Summary & Checkout Panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Payment Mode Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['Cash', 'Raast', 'JazzCash', 'EasyPaisa', 'Credit (Udhaar)'].map((mode) {
                        final isSelected = cart.paymentMode == mode;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(mode),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryEmerald.withAlpha(40),
                            onSelected: (_) => cartNotifier.setPaymentMode(mode),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Bill Breakdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal (${cart.totalItemCount} items)', style: TextStyle(color: Colors.grey.shade600)),
                      Text('${AppConstants.currencySymbol} ${cart.subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (cart.totalTaxAmount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('FBR Sales Tax (18%)', style: TextStyle(color: Colors.grey.shade600)),
                        Text('${AppConstants.currencySymbol} ${cart.totalTaxAmount.toStringAsFixed(2)}'),
                      ],
                    ),
                  ],
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(
                        '${AppConstants.currencySymbol} ${cart.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Checkout Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Charge & Print Receipt'),
                      onPressed: cart.items.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppTheme.successGreen,
                                  content: Text(
                                    'Bill of ${AppConstants.currencySymbol} ${cart.grandTotal.toStringAsFixed(2)} processed via ${cart.paymentMode}!',
                                  ),
                                ),
                              );
                              cartNotifier.clearCart();
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
