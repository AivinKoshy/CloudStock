import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  _DatabaseScreenState createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String _searchQuery = '';
  List<DocumentSnapshot> _products = [];
  bool _isSearching = false;
  String _sortBy = 'timestamp'; // Default sort by timestamp
  bool _sortDescending = true; // Default sort direction

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('products')
          .orderBy(_sortBy, descending: _sortDescending)
          .get();

      setState(() {
        _products = querySnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      _showErrorSnackBar('Error fetching products: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchProducts() async {
    if (_searchQuery.isEmpty) {
      await _fetchProducts();
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearching = true;
    });

    try {
      // Search by product name, case insensitive
      QuerySnapshot querySnapshot = await _firestore
          .collection('products')
          .orderBy('name')
          .startAt([_searchQuery])
          .endAt(['$_searchQuery\uf8ff'])
          .get();

      // If no results, try searching by product ID
      if (querySnapshot.docs.isEmpty) {
        querySnapshot = await _firestore
            .collection('products')
            .where('productId', isEqualTo: _searchQuery)
            .get();
      }

      setState(() {
        _products = querySnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      _showErrorSnackBar('Error searching products: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _resetSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _isSearching = false;
    });
    _fetchProducts();
  }

  Future<void> _confirmDelete(DocumentSnapshot product) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to delete ${product['name']}?',
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
                _deleteProduct(product);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProduct(DocumentSnapshot product) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _firestore.collection('products').doc(product.id).delete();
      _showSuccessSnackBar('${product['name']} deleted successfully');
      
      setState(() {
        _products.remove(product);
        _isLoading = false;
      });
    } catch (e) {
      _showErrorSnackBar('Error deleting product: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddEditDialog({DocumentSnapshot? product}) {
    final TextEditingController nameController = TextEditingController(
      text: product != null ? product['name'] : '',
    );
    final TextEditingController dateController = TextEditingController(
      text: product != null ? product['date'] : '',
    );
    final TextEditingController priceController = TextEditingController(
      text: product != null ? product['price'] : '',
    );
    final TextEditingController quantityController = TextEditingController(
      text: product != null ? (product['quantity'] ?? 1).toString() : '1',
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(product != null ? 'Edit Product' : 'Add New Product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'Product Name',
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
                  controller: dateController,
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
                  controller: priceController,
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
                const SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  decoration: InputDecoration(
                    hintText: 'Quantity',
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (product != null) {
                  _updateProduct(
                    product,
                    nameController.text,
                    dateController.text,
                    priceController.text,
                    int.tryParse(quantityController.text) ?? 1,
                  );
                } else {
                  _addNewProduct(
                    nameController.text,
                    dateController.text,
                    priceController.text,
                    int.tryParse(quantityController.text) ?? 1,
                  );
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(255, 50, 15, 133),
              ),
              child: Text(product != null ? 'UPDATE' : 'ADD'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateProduct(
    DocumentSnapshot product,
    String name,
    String date,
    String price,
    int quantity,
  ) async {
    if (name.isEmpty || date.isEmpty || price.isEmpty) {
      _showErrorSnackBar('All fields are required');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      await _firestore.collection('products').doc(product.id).update({
        'name': name,
        'date': date,
        'price': price,
        'quantity': quantity,
      });

      _showSuccessSnackBar('Product updated successfully');
      _fetchProducts();
    } catch (e) {
      _showErrorSnackBar('Error updating product: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addNewProduct(
    String name, 
    String date, 
    String price,
    int quantity,
  ) async {
    if (name.isEmpty || date.isEmpty || price.isEmpty) {
      _showErrorSnackBar('All fields are required');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Generate a new product ID
      final String productId = const Uuid().v4();

      await _firestore.collection('products').doc(productId).set({
        'productId': productId,
        'name': name,
        'date': date,
        'price': price,
        'quantity': quantity,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSuccessSnackBar('Product added successfully');
      _fetchProducts();
    } catch (e) {
      _showErrorSnackBar('Error adding product: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _incrementQuantity(DocumentSnapshot product) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get the current quantity and increment it
      int currentQuantity = product['quantity'] ?? 1;
      int newQuantity = currentQuantity + 1;

      // Update the product in Firestore
      await _firestore
          .collection('products')
          .doc(product.id)
          .update({'quantity': newQuantity});

      _showSuccessSnackBar('Quantity increased to $newQuantity');
      _fetchProducts();
    } catch (e) {
      _showErrorSnackBar('Error updating quantity: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _decrementQuantity(DocumentSnapshot product) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Get the current quantity
      int currentQuantity = product['quantity'] ?? 1;
      
      if (currentQuantity <= 1) {
        // Confirm before deleting the product
        _confirmDelete(product);
        setState(() {
          _isLoading = false;
        });
        return;
      } else {
        // If quantity is greater than 1, decrement it
        int newQuantity = currentQuantity - 1;
        
        await _firestore
            .collection('products')
            .doc(product.id)
            .update({'quantity': newQuantity});

        _showSuccessSnackBar('Quantity decreased to $newQuantity');
        _fetchProducts();
      }
    } catch (e) {
      _showErrorSnackBar('Error updating quantity: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    
    try {
      Timestamp ts = timestamp as Timestamp;
      DateTime dateTime = ts.toDate();
      return DateFormat('MM/dd/yyyy hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid date';
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _buildSortOption('Name', 'name'),
              _buildSortOption('Date Added', 'timestamp'),
              _buildSortOption('Price', 'price'),
              _buildSortOption('Quantity', 'quantity'),
              const SizedBox(height: 8),
              const Divider(color: Colors.grey),
              _buildSortDirectionOption(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOption(String label, String field) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: _sortBy == field ? Colors.blue : Colors.white,
        ),
      ),
      leading: Radio<String>(
        value: field,
        groupValue: _sortBy,
        onChanged: (value) {
          Navigator.pop(context);
          setState(() {
            _sortBy = value!;
          });
          _fetchProducts();
        },
        activeColor: Colors.blue,
      ),
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _sortBy = field;
        });
        _fetchProducts();
      },
    );
  }

  Widget _buildSortDirectionOption() {
    return ListTile(
      title: const Text(
        'Sort Direction',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        _sortDescending ? 'Descending (highest first)' : 'Ascending (lowest first)',
        style: TextStyle(color: Colors.grey[400]),
      ),
      trailing: Switch(
        value: _sortDescending,
        onChanged: (value) {
          setState(() {
            _sortDescending = value;
          });
          Navigator.pop(context);
          _fetchProducts();
        },
        activeColor: Colors.blue,
      ),
      onTap: () {
        setState(() {
          _sortDescending = !_sortDescending;
        });
        Navigator.pop(context);
        _fetchProducts();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _resetSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    onSubmitted: (_) => _searchProducts(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchProducts,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isSearching
                                  ? 'No products found'
                                  : 'No products in database',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[400],
                              ),
                            ),
                            if (_isSearching)
                              TextButton(
                                onPressed: _resetSearch,
                                child: const Text('Clear Search'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final int quantity = product['quantity'] ?? 1;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            color: Colors.grey[850],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              title: Text(
                                product['name'] ?? 'Unnamed Product',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Price: ${product['price'] ?? 'N/A'}',
                                    style: TextStyle(color: Colors.grey[400]),
                                  ),
                                  Text(
                                    'Quantity: $quantity',
                                    style: TextStyle(
                                      color: quantity > 0 
                                          ? Colors.green[400] 
                                          : Colors.red[400],
                                    ),
                                  ),
                                ],
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color.fromARGB(255, 50, 15, 133),
                                child: const Icon(
                                  Icons.inventory,
                                  color: Colors.white,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () =>
                                        _showAddEditDialog(product: product),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _confirmDelete(product),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDetailRow(
                                        'Product ID',
                                        product['productId'] ?? 'N/A',
                                      ),
                                      _buildDetailRow(
                                        'Date',
                                        product['date'] ?? 'N/A',
                                      ),
                                      _buildDetailRow(
                                        'Added On',
                                        _formatTimestamp(product['timestamp']),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () => _decrementQuantity(product),
                                            icon: const Icon(Icons.remove),
                                            label: const Text('Decrease'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red[700],
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            '$quantity',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => _incrementQuantity(product),
                                            icon: const Icon(Icons.add),
                                            label: const Text('Increase'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green[700],
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color.fromARGB(255, 50, 15, 133),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child:
                Text(label, style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}