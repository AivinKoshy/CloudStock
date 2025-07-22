import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'encryption-service.dart';

class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  _ReadScreenState createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  String _statusMessage = 'Tap to read NFC tag';
  bool _isLoading = false;
  Map<String, dynamic>? _productData;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _readNFC() async {
    setState(() {
      _statusMessage = 'Scanning for NFC tag...';
      _isLoading = true;
      _productData = null;
    });

    if (!await NfcManager.instance.isAvailable()) {
      _handleError('NFC not available on this device');
      return;
    }

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          Ndef? ndef = Ndef.from(tag);
          if (ndef == null) {
            _handleError('NFC tag not readable');
            return;
          }

          NdefMessage message = await ndef.read();
          // Get the encrypted product ID from the NFC tag
          String encryptedProductId = String.fromCharCodes(
            message.records.first.payload.sublist(3),
          );
          
          // Decrypt the product ID
          String productId = EncryptionService.decrypt(encryptedProductId);

          // Fetch product data from Firestore using the decrypted product ID
          await _fetchProductData(productId);

          NfcManager.instance.stopSession();
        } catch (e) {
          _handleError('Error reading NFC tag: ${e.toString()}');
          NfcManager.instance.stopSession();
        }
      },
    );
  }

  Future<void> _fetchProductData(String productId) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('products').doc(productId).get();

      setState(() {
        _isLoading = false;
        if (doc.exists) {
          _productData = doc.data() as Map<String, dynamic>;
          // If quantity field doesn't exist (for older products), initialize it
          if (!_productData!.containsKey('quantity')) {
            _productData!['quantity'] = 1;
            // Update the product in Firestore with the quantity field
            _firestore.collection('products').doc(productId).update({
              'quantity': 1
            });
          }
          _statusMessage = 'Product found!';
        } else {
          _statusMessage = 'Product not found in database';
        }
      });
    } catch (e) {
      _handleError('Error fetching product data: ${e.toString()}');
    }
  }

  Future<void> _incrementQuantity() async {
    if (_productData == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // Get the current quantity and increment it
      int currentQuantity = _productData!['quantity'] ?? 1;
      int newQuantity = currentQuantity + 1;

      // Update the product in Firestore
      await _firestore
          .collection('products')
          .doc(_productData!['productId'])
          .update({'quantity': newQuantity});

      // Update local data
      setState(() {
        _productData!['quantity'] = newQuantity;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quantity updated to $newQuantity')),
      );
    } catch (e) {
      _handleError('Error updating quantity: ${e.toString()}');
    }
  }

  Future<void> _removeProduct() async {
    if (_productData == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // Get the current quantity
      int currentQuantity = _productData!['quantity'] ?? 1;
      
      if (currentQuantity <= 1) {
        // If quantity is 1 or less, delete the product
        await _firestore
            .collection('products')
            .doc(_productData!['productId'])
            .delete();

        setState(() {
          _isLoading = false;
          _productData = null;
          _statusMessage = 'Product removed successfully';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product removed from database')),
        );
      } else {
        // If quantity is greater than 1, decrement it
        int newQuantity = currentQuantity - 1;
        
        await _firestore
            .collection('products')
            .doc(_productData!['productId'])
            .update({'quantity': newQuantity});

        // Update local data
        setState(() {
          _productData!['quantity'] = newQuantity;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantity decreased to $newQuantity')),
        );
      }
    } catch (e) {
      _handleError('Error removing product: ${e.toString()}');
    }
  }

  void _handleError(String errorMessage) {
    setState(() {
      _statusMessage = errorMessage;
      _isLoading = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(errorMessage)));
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int currentQuantity = _productData!['quantity'] ?? 1;
        String message = currentQuantity > 1 
            ? 'Current quantity is $currentQuantity. This will decrease the quantity by 1.'
            : 'Current quantity is 1. This will remove the product from the database.';
            
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text('Confirm Action'),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeProduct();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('CONFIRM'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product'),
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
            Card(
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else if (_productData != null)
                      _buildProductDetails()
                    else
                      Text(
                        _statusMessage,
                        style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _readNFC,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 50, 15, 133),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey,
              ),
              child: const Text(
                'Scan NFC Tag',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (_productData != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _incrementQuantity,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: const Text(
                  'Increment Quantity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _showDeleteConfirmation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: const Text(
                  'Decrement Quantity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Product Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Divider(color: Colors.grey),
        _buildDetailRow('Product ID', _productData!['productId'] ?? 'N/A'),
        _buildDetailRow('Name', _productData!['name'] ?? 'N/A'),
        _buildDetailRow('Date', _productData!['date'] ?? 'N/A'),
        _buildDetailRow('Price', _productData!['price'] ?? 'N/A'),
        _buildDetailRow('Quantity', '${_productData!['quantity'] ?? 1}'),
        if (_productData!['timestamp'] != null)
          _buildDetailRow(
            'Added On',
            (_productData!['timestamp'] as Timestamp).toDate().toString().split(
              '.',
            )[0],
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[400])),
          Text(
            value,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}