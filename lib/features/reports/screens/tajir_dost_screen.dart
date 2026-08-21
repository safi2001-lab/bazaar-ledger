import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/tajir_dost_controller.dart';

class TajirDostScreen extends ConsumerWidget {
  const TajirDostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tajirState = ref.watch(tajirDostControllerProvider);
    final res = tajirState.taxResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tajir Dost Special Scheme (1%)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryEmerald, Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'FBR Tajir Dost Scheme 2024',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Net Advance Tax Payable this Month',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.currencySymbol} ${res.netPayableTax.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (res.carriedForwardCredit > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Excess Electricity Credit: ${AppConstants.currencySymbol} ${res.carriedForwardCredit.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Math Breakdown Card
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
                    'Monthly Tax Offset Breakdown',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  _buildRow(
                    'Monthly Gross Turnover (Sales)',
                    '${AppConstants.currencySymbol} ${res.grossTurnover.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  _buildRow(
                    'Turnover Advance Tax @ 1.0%',
                    '${AppConstants.currencySymbol} ${res.grossTaxLiability.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    'Less: Electricity Bill WHT (Sec 235)',
                    '- ${AppConstants.currencySymbol} ${res.electricityWhtDeductions.toStringAsFixed(2)}',
                    color: Colors.green.shade700,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    'Net Payable FBR Challan Amount',
                    '${AppConstants.currencySymbol} ${res.netPayableTax.toStringAsFixed(2)}',
                    isBold: true,
                    color: AppTheme.primaryEmerald,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Action: Log Electricity Bill
          Card(
            elevation: 0,
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: ListTile(
              leading: const Icon(Icons.bolt, color: Colors.blue, size: 32),
              title: const Text(
                'Log Electricity Bill WHT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Add advance income tax deducted on your shop\'s commercial power bill (LESCO/K-Electric) to offset your 1% tax.',
              ),
              trailing: const Icon(Icons.add_circle, color: Colors.blue),
              onTap: () => _showLogBillDialog(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showLogBillDialog(BuildContext context, WidgetRef ref) {
    final billController = TextEditingController();
    final whtController = TextEditingController();
    final consumerController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Electricity Bill WHT'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: consumerController,
              decoration: const InputDecoration(
                labelText: 'Consumer / Reference No.',
                hintText: 'e.g. 04 11223 3445500',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: billController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total Bill Amount (Rs)',
                prefixText: 'Rs. ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: whtController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Advance Income Tax (Sec 235)',
                prefixText: 'Rs. ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final bill = double.tryParse(billController.text) ?? 0.0;
              final wht = double.tryParse(whtController.text) ?? 0.0;
              if (wht > 0) {
                ref.read(tajirDostControllerProvider.notifier).logElectricityBill(
                      billAmount: bill,
                      whtAmount: wht,
                      consumerNumber: consumerController.text.trim(),
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Electricity WHT recorded and offset applied!')),
                );
              }
            },
            child: const Text('Save WHT Credit'),
          ),
        ],
      ),
    );
  }
}
