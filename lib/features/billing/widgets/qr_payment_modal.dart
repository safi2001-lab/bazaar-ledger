import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/offline_qr_engine.dart';

class QrPaymentModal extends StatelessWidget {
  final double totalAmount;
  final String paymentChannel; // 'Raast', 'JazzCash', 'EasyPaisa'
  final VoidCallback onPaymentConfirmed;

  const QrPaymentModal({
    super.key,
    required this.totalAmount,
    required this.paymentChannel,
    required this.onPaymentConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    // Generate dynamic QR with exact PKR amount and merchant info
    final qrPayload = OfflineQrEngine.generateMerchantQr(
      merchantIdentifier: paymentChannel == 'Raast'
          ? 'PK36MEZN0001234567890101'
          : (paymentChannel == 'JazzCash' ? '00124578' : '03001234567'),
      merchantName: 'AL-MADINA STORE',
      merchantCity: 'LAHORE',
      amount: totalAmount,
      invoiceNumber: 'INV-${DateTime.now().millisecondsSinceEpoch % 10000}',
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      paymentChannel == 'Raast' ? Icons.account_balance : Icons.phone_android,
                      color: AppTheme.primaryEmerald,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$paymentChannel Payment QR',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Show this screen to customer to scan with their banking / wallet app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // QR Code Frame
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Amount Display
            Text(
              'Payable: ${AppConstants.currencySymbol} ${totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryEmerald,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Zero Gateway Transaction Fees (100% Direct)',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('Payment Received (Print Receipt)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onPaymentConfirmed();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
