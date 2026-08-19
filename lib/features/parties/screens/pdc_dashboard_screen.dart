import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/pdc_controller.dart';
import '../../../data/database/app_database.dart';

class PdcDashboardScreen extends ConsumerWidget {
  const PdcDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdcAsync = ref.watch(pdcControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDC Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // Add PDC Dialog
            },
          )
        ],
      ),
      body: pdcAsync.when(
        data: (cheques) {
          if (cheques.isEmpty) {
            return const Center(child: Text('No upcoming Post-Dated Cheques in hand.'));
          }
          return ListView.builder(
            itemCount: cheques.length,
            itemBuilder: (context, index) {
              final pdc = cheques[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cheque: ${pdc.chequeNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Rs. ${pdc.amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Bank: ${pdc.bankName}'),
                      Text('Maturity: ${pdc.chequeDate.toLocal().toString().split(' ')[0]}'),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.account_balance),
                            label: const Text('Deposit'),
                            onPressed: () {
                              ref.read(pdcControllerProvider.notifier).depositPdc(pdc.id);
                            },
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.warning, color: Colors.red),
                            label: const Text('Bounce', style: TextStyle(color: Colors.red)),
                            onPressed: () {
                              _showBounceDialog(context, ref, pdc);
                            },
                          ),
                        ],
                      )
                    ],
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

  void _showBounceDialog(BuildContext context, WidgetRef ref, PostDatedCheque pdc) {
    final memoController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mark Cheque as Bounced'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This will flag the cheque as bounced and generate a Section 489-F PPC Legal Notice.'),
              const SizedBox(height: 16),
              TextField(
                controller: memoController,
                decoration: const InputDecoration(labelText: 'Bank Memo Reference'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                ref.read(pdcControllerProvider.notifier).bouncePdc(pdc.id, memoController.text);
                Navigator.pop(context);
                
                // Show snackbar
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cheque Bounced. Section 489-F notice generated.'))
                );
              },
              child: const Text('Confirm Bounce', style: TextStyle(color: Colors.white)),
            )
          ],
        );
      }
    );
  }
}
