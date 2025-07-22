import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:uuid/uuid.dart';
import 'encryption-service.dart';

class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key});

  @override
  _WriteScreenState createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();

  // Hardcoded password constants (4-byte password and 2-byte PACK)
  final List<int> _PASSWORD = [0x12, 0x34, 0x56, 0x78]; // Example password
  final List<int> _PACK = [0x90, 0xAB]; // Example PACK value

  // Pages for configuration (NTAG-213 specific)
  final int _PWD_PAGE = 0x2B; // Page for password (typically 0x2B)
  final int _PACK_PAGE = 0x2C; // Page for PACK (typically start of 0x2C)
  final int _AUTH0_PAGE = 0x2C; // Page for AUTH0 (typically in 0x2C)
  final int _ACCESS_PAGE = 0x2C; // Page for ACCESS byte (typically in 0x2C)

  // First page to protect (adjust based on your needs)
  final int _FIRST_PROTECTED_PAGE = 0x04;

  // Authentication method needed before writing to protected tags
  Future<bool> _authenticateTag(NfcTag tag) async {
    try {
      // For NTAG 213, we need to use transceive with specific commands
      final tech = MifareUltralight.from(tag);
      if (tech == null) return false;

      // PWD_AUTH command: 0x1B followed by 4-byte password
      List<int> authCommand = [0x1B, ..._PASSWORD];

      // Convert to Uint8List and use named parameter
      final Uint8List commandData = Uint8List.fromList(authCommand);
      final response = await tech.transceive(data: commandData);

      // Check if response matches PACK value
      return response.length >= 2 &&
          response[0] == _PACK[0] &&
          response[1] == _PACK[1];
    } catch (e) {
      print("Authentication error: $e");
      return false;
    }
  }

  // Method to setup password protection on a tag
  Future<bool> _setupPasswordProtection(NfcTag tag) async {
    try {
      final tech = MifareUltralight.from(tag);
      if (tech == null) return false;

      // Write password to PWD page
      await tech.writePage(
        pageOffset: _PWD_PAGE,
        data: Uint8List.fromList(_PASSWORD),
      );

      // Write PACK value and configure AUTH0/ACCESS settings
      // First 2 bytes: PACK, 3rd byte: AUTH0, 4th byte: ACCESS
      List<int> configData = [
        _PACK[0], _PACK[1],
        _FIRST_PROTECTED_PAGE, // AUTH0: first page requiring authentication
        0x00, // ACCESS: 0x00 for write-only protection (bit 7 = 0)
      ];
      await tech.writePage(
        pageOffset: _ACCESS_PAGE,
        data: Uint8List.fromList(configData),
      );

      return true;
    } catch (e) {
      print("Password setup error: $e");
      return false;
    }
  }

  void _writeToNFC() async {
    if (!await NfcManager.instance.isAvailable()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('NFC not available')));
      return;
    }

    // Generate a product ID
    final String productId = _uuid.v4();

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        Ndef? ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('NFC tag not writable')));
          return;
        }

        try {
          // Try to authenticate with the tag first (for already protected tags)
          bool isAuthenticated = await _authenticateTag(tag);

          // If authentication failed, this might be a new tag
          // so we'll try to write normally and then set up protection
          if (!isAuthenticated) {
            // Encrypt the product ID before writing to NFC
            final String encryptedProductId = EncryptionService.encrypt(
              productId,
            );

            // Write the encrypted product ID to the NFC tag
            NdefMessage message = NdefMessage([
              NdefRecord.createText(encryptedProductId),
            ]);

            await ndef.write(message);

            // Now set up password protection on this new tag
            bool setupSuccess = await _setupPasswordProtection(tag);
            if (!setupSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Warning: Password protection setup failed'),
                ),
              );
            }
          } else {
            // Tag is already password protected and we authenticated successfully
            // Now we can write our data
            final String encryptedProductId = EncryptionService.encrypt(
              productId,
            );

            NdefMessage message = NdefMessage([
              NdefRecord.createText(encryptedProductId),
            ]);

            await ndef.write(message);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product ID written to NFC successfully'),
            ),
          );

          // Save product details with the original (unencrypted) ID to Firestore
          await _saveToFirestore(productId);

          NfcManager.instance.stopSession();
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to write to NFC: ${e.toString()}')),
          );
          NfcManager.instance.stopSession();
        }
      },
    );
  }

  Future<void> _saveToFirestore(String productId) async {
    try {
      // Save all product details to Firestore with the product ID
      // Added quantity field initialized to 1
      await _firestore.collection('products').doc(productId).set({
        'productId': productId,
        'name': _nameController.text,
        'date': _dateController.text,
        'price': _priceController.text,
        'quantity': 1, // Initialize quantity to 1 for new products
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product details saved to Firestore')),
      );
    } catch (e) {
      String errorMessage =
          e is FirebaseException
              ? 'Firebase error: ${e.code} - ${e.message}'
              : 'Error: ${e.toString()}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save to Firestore: $errorMessage')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // No changes to the build method
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write Tag'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tap to scan', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Name',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dateController,
              decoration: InputDecoration(
                hintText: 'MM/DD/YYYY',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              decoration: InputDecoration(
                hintText: '\$0.00',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _writeToNFC,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 50, 15, 133),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Write',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}