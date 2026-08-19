import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/app_database.dart';
import '../../../services/share_intent_service.dart';
import '../controllers/party_ledger_controller.dart';

class PartyLedgerScreen extends ConsumerWidget {
  final Party party;

  const PartyLedgerScreen({super.key, required this.party});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              ShareIntentService.shareKhataReminder(party.name, party.currentBalance);
            },
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: party.currentBalance > 0 ? Colors.red.shade50 : Colors.green.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Current Balance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'Rs. ${party.currentBalance.abs().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: party.currentBalance > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text('Journal entries list goes here'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.payment),
            label: const Text('Receive Payment'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () {
              _showReceivePaymentDialog(context, ref);
            },
          ),
        ),
      ),
    );
  }

  void _showReceivePaymentDialog(BuildContext context, WidgetRef ref) {
    final amountController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Receive Payment'),
          content: TextField(
            controller: amountController,
            decoration: const InputDecoration(
              labelText: 'Amount (Rs)',
              prefixText: 'Rs. '
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount > 0) {
                  ref.read(partyLedgerControllerProvider.notifier).recordPaymentReceived(
                    party.id, 
                    amount, 
                    'Cash',
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Save Payment'),
            )
          ],
        );
      }
    );
  }
}
