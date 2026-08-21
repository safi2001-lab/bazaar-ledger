import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class SplitPaymentDialog extends StatefulWidget {
  final double totalAmount;
  final Function(double cashPortion, double creditPortion) onComplete;

  const SplitPaymentDialog({
    super.key,
    required this.totalAmount,
    required this.onComplete,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  final _cashController = TextEditingController();
  double _cashPortion = 0.0;

  @override
  void initState() {
    super.initState();
    _cashPortion = widget.totalAmount / 2; // Default 50/50 split
    _cashController.text = _cashPortion.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creditPortion = widget.totalAmount - _cashPortion;
    final isValid = _cashPortion >= 0 && _cashPortion <= widget.totalAmount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.call_split, color: AppTheme.primaryEmerald),
          SizedBox(width: 8),
          Text('Split Payment (Cash + Khata)'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Total Bill Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Bill:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  Text(
                    '${AppConstants.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cash Portion Input
            TextField(
              controller: _cashController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cash Paid Now (Rs)',
                prefixText: '${AppConstants.currencySymbol} ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                setState(() {
                  _cashPortion = double.tryParse(val) ?? 0.0;
                });
              },
            ),
            const SizedBox(height: 16),

            // Remaining Balance (Khata / Credit)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remaining Udhaar (Added to Khata):',
                    style: TextStyle(fontSize: 13, color: Colors.brown),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${AppConstants.currencySymbol} ${creditPortion.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryEmerald,
            foregroundColor: Colors.white,
          ),
          onPressed: isValid
              ? () {
                  Navigator.pop(context);
                  widget.onComplete(_cashPortion, creditPortion);
                }
              : null,
          child: const Text('Confirm Split'),
        ),
      ],
    );
  }
}
