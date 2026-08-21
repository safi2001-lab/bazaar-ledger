import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/party_ledger_controller.dart';

class PartiesListScreen extends ConsumerWidget {
  const PartiesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partiesAsync = ref.watch(partyLedgerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parties & Khata'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _showAddPartyDialog(context, ref);
            },
          )
        ],
      ),
      body: partiesAsync.when(
        data: (parties) {
          if (parties.isEmpty) {
            return const Center(child: Text('No parties found. Add a customer or supplier.'));
          }
          return ListView.builder(
            itemCount: parties.length,
            itemBuilder: (context, index) {
              final party = parties[index];
              final isUdhaar = party.currentBalance > 0;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isUdhaar ? Colors.red.shade100 : Colors.green.shade100,
                  child: Text(party.name[0].toUpperCase()),
                ),
                title: Text(party.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(party.phone ?? 'No phone'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rs. ${party.currentBalance.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isUdhaar ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isUdhaar ? 'They Owe Us' : 'Settled / Advance',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                onTap: () {
                  // Navigate to Ledger Screen
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddPartyDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Party'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Party Name'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(partyLedgerControllerProvider.notifier).addParty(
                  nameController.text,
                  phoneController.text,
                  'Customer',
                  0.0,
                  0.0,
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            )
          ],
        );
      }
    );
  }
}
