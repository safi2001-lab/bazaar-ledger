import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/inventory_controller.dart';

class AddEditItemScreen extends ConsumerStatefulWidget {
  const AddEditItemScreen({super.key});

  @override
  ConsumerState<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends ConsumerState<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _hsCodeController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _openingStockController = TextEditingController(text: '0');
  final _minStockAlertController = TextEditingController(text: '5');

  String _selectedUnit = 'Piece';
  double _selectedTaxRate = 18.0;
  bool _trackBatch = false;
  bool _trackSerial = false;
  bool _is3rdSchedule = false;

  final List<String> _units = [
    'Piece',
    'Kg',
    'Gram',
    'Carton',
    'Meter',
    'Gaz',
    'Litre',
    'Dozen',
    'Pack',
    'Box',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _hsCodeController.dispose();
    _salePriceController.dispose();
    _purchasePriceController.dispose();
    _openingStockController.dispose();
    _minStockAlertController.dispose();
    super.dispose();
  }

  void _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final barcode = _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim();
    final hsCode = _hsCodeController.text.trim().isEmpty ? null : _hsCodeController.text.trim();
    final salePrice = double.parse(_salePriceController.text.trim());
    final purchasePrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
    final openingStock = double.tryParse(_openingStockController.text.trim()) ?? 0.0;
    final minStock = double.tryParse(_minStockAlertController.text.trim()) ?? 5.0;

    await ref.read(inventoryControllerProvider.notifier).addItem(
          name: name,
          barcode: barcode,
          unit: _selectedUnit,
          hsCode: hsCode,
          salePrice: salePrice,
          purchasePrice: purchasePrice,
          taxRate: _selectedTaxRate,
          initialStock: openingStock,
          minStockAlert: minStock,
          trackBatch: _trackBatch,
          trackSerial: _trackSerial,
          is3rdSchedule: _is3rdSchedule,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item added successfully!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Item'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Basic Details
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Product Identity',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        hintText: 'e.g. Panadol 500mg or Sugar 1kg',
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Please enter item name' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'Barcode / EAN-13',
                              hintText: 'Scan or type',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _hsCodeController,
                            decoration: const InputDecoration(
                              labelText: 'HS Code (Customs)',
                              hintText: 'e.g. 3004.90',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: const InputDecoration(labelText: 'Primary Unit'),
                      items: _units
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedUnit = val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pricing & Taxes Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pricing & FBR Tax Slab',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _salePriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Sale Price (PKR) *',
                              prefixIcon: Icon(Icons.sell),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Required';
                              if (double.tryParse(val) == null) return 'Invalid amount';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _purchasePriceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Purchase Price (PKR)',
                              prefixIcon: Icon(Icons.shopping_cart),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<double>(
                      initialValue: _selectedTaxRate,
                      decoration: const InputDecoration(labelText: 'FBR Sales Tax Rate'),
                      items: const [
                        DropdownMenuItem(value: 18.0, child: Text('18% Standard Sales Tax')),
                        DropdownMenuItem(value: 1.0, child: Text('1% Tajir Dost / Reduced Slab')),
                        DropdownMenuItem(value: 0.0, child: Text('0% Tax Exempt / Zero-Rated')),
                        DropdownMenuItem(value: 5.0, child: Text('5% Concessionary Rate')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedTaxRate = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('3rd Schedule Item (Tax calculated on MRP)'),
                      subtitle: const Text('Required for FMCG/beverages where tax applies on printed retail price'),
                      value: _is3rdSchedule,
                      onChanged: (val) => setState(() => _is3rdSchedule = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stock & Advanced Retail Verticals
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stock & Vertical Tracking',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _openingStockController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Opening Stock Qty'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _minStockAlertController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Low Stock Alert Limit'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pharmacy Mode: Track Batch & Expiry'),
                      subtitle: const Text('Prompt for Batch Number and Expiry Date on stock entry & checkout'),
                      value: _trackBatch,
                      onChanged: (val) => setState(() => _trackBatch = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mobile/Electronics: Track Dual IMEI / Serial'),
                      subtitle: const Text('Records IMEI 1, IMEI 2 & PTA verification status on sale'),
                      value: _trackSerial,
                      onChanged: (val) => setState(() => _trackSerial = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Save Item to Catalog', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveItem,
            ),
          ],
        ),
      ),
    );
  }
}
