import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class CashTenderDialog extends StatefulWidget {
  final double totalAmount;
  final ValueChanged<double> onComplete;

  const CashTenderDialog({
    super.key,
    required this.totalAmount,
    required this.onComplete,
  });

  @override
  State<CashTenderDialog> createState() => _CashTenderDialogState();
}

class _CashTenderDialogState extends State<CashTenderDialog> {
  final _tenderController = TextEditingController();
  double _tenderedAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _tenderedAmount = widget.totalAmount;
    _tenderController.text = widget.totalAmount.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _tenderController.dispose();
    super.dispose();
  }

  void _addNote(double noteValue) {
    setState(() {
      _tenderedAmount += noteValue;
      _tenderController.text = _tenderedAmount.toStringAsFixed(0);
    });
  }

  void _setExact() {
    setState(() {
      _tenderedAmount = widget.totalAmount;
      _tenderController.text = widget.totalAmount.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final changeDue = _tenderedAmount - widget.totalAmount;
    final isSufficient = _tenderedAmount >= widget.totalAmount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.payments_outlined, color: AppTheme.primaryEmerald),
          SizedBox(width: 8),
          Text('Cash Tender & Change'),
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

            // Cash Received Input
            TextField(
              controller: _tenderController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Cash Received (Rs)',
                prefixText: '${AppConstants.currencySymbol} ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) {
                setState(() {
                  _tenderedAmount = double.tryParse(val) ?? 0.0;
                });
              },
            ),
            const SizedBox(height: 12),

            // Quick Currency Note Buttons (PKR Notes)
            const Text('Quick Cash Notes (PKR):', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickNoteButton('+500', 500),
                _buildQuickNoteButton('+1,000', 1000),
                _buildQuickNoteButton('+5,000', 5000),
                ActionChip(
                  label: const Text('Exact Bill'),
                  backgroundColor: Colors.grey.shade200,
                  onPressed: _setExact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Change Return Calculation Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSufficient ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSufficient ? Colors.green.shade300 : Colors.red.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSufficient ? 'Change to Return:' : 'Amount Short:',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSufficient ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                  Text(
                    '${AppConstants.currencySymbol} ${changeDue.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSufficient ? Colors.green.shade900 : Colors.red.shade900,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: isSufficient
              ? () {
                  Navigator.pop(context);
                  widget.onComplete(_tenderedAmount);
                }
              : null,
          child: const Text('Complete & Print Receipt'),
        ),
      ],
    );
  }

  Widget _buildQuickNoteButton(String label, double value) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: Colors.green.shade50,
      side: BorderSide(color: Colors.green.shade200),
      onPressed: () => _addNote(value),
    );
  }
}
