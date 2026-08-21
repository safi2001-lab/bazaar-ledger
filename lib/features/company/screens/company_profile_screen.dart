import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/offline_qr_engine.dart';

class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _nameController = TextEditingController(text: 'Al-Madina General Store');
  final _addressController = TextEditingController(text: 'Shop 14, Main Bazaar, Lahore');
  final _phoneController = TextEditingController(text: '03001234567');
  final _ntnController = TextEditingController(text: '7765432-1');

  final _raastIbanController = TextEditingController(text: 'PK36MEZN0001234567890101');
  final _jazzcashTillController = TextEditingController(text: '00124578');
  final _easypaisaController = TextEditingController(text: '03001234567');

  String _qrPreviewPayload = '';

  @override
  void initState() {
    super.initState();
    _updateQrPreview();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _ntnController.dispose();
    _raastIbanController.dispose();
    _jazzcashTillController.dispose();
    _easypaisaController.dispose();
    super.dispose();
  }

  void _updateQrPreview() {
    final identifier = _raastIbanController.text.trim().isNotEmpty
        ? _raastIbanController.text.trim()
        : (_jazzcashTillController.text.trim().isNotEmpty
            ? _jazzcashTillController.text.trim()
            : _easypaisaController.text.trim());

    if (identifier.isNotEmpty) {
      final payload = OfflineQrEngine.generateMerchantQr(
        merchantIdentifier: identifier,
        merchantName: _nameController.text.trim(),
        merchantCity: 'LAHORE',
      );
      setState(() {
        _qrPreviewPayload = payload;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Profile & Payment QR'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Business Identity Card
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
                  const Text('Store Identity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Store / Shop Name *'),
                    onChanged: (_) => _updateQrPreview(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Store Address'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(labelText: 'Contact Phone'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ntnController,
                          decoration: const InputDecoration(labelText: 'NTN / STRN'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Digital Payment QR Identifiers
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
                  const Row(
                    children: [
                      Icon(Icons.qr_code_2, color: AppTheme.primaryEmerald, size: 24),
                      SizedBox(width: 8),
                      Text('Offline Payment QR Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your Raast IBAN, JazzCash Till, or EasyPaisa number. This generates customer-scannable payment QR codes on receipts and screen with zero bank API charges.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _raastIbanController,
                    decoration: const InputDecoration(
                      labelText: 'Raast IBAN (Recommended)',
                      hintText: 'e.g. PK36MEZN0001234567890101',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                    onChanged: (_) => _updateQrPreview(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _jazzcashTillController,
                    decoration: const InputDecoration(
                      labelText: 'JazzCash Till Number',
                      hintText: 'e.g. 00123456',
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                    onChanged: (_) => _updateQrPreview(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _easypaisaController,
                    decoration: const InputDecoration(
                      labelText: 'EasyPaisa Number',
                      hintText: 'e.g. 03001234567',
                      prefixIcon: Icon(Icons.wallet),
                    ),
                    onChanged: (_) => _updateQrPreview(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live QR Preview Card
          if (_qrPreviewPayload.isNotEmpty)
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
                  children: [
                    const Text('Receipt Payment QR Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Center(
                      child: QrImageView(
                        data: _qrPreviewPayload,
                        version: QrVersions.auto,
                        size: 160.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'EMVCo CRC-16 Checksum: ${_qrPreviewPayload.substring(_qrPreviewPayload.length - 4)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Store profile and payment QR settings saved!')),
              );
              Navigator.pop(context);
            },
            child: const Text('Save Store Profile', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
