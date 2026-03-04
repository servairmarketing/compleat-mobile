import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/printer_service.dart';
import 'printer_settings_screen.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});
  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  final _parentRollController = TextEditingController();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map> _products = [];
  String? _selectedProduct;
  String? _selectedProductName;
  bool _loading = false;
  bool _submitting = false;
  bool _printLabel = true;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final res = await ApiService.get('/masters/products');
    if (res['records'] != null) {
      await LocalDb.cacheMasters('products', jsonEncode(res['records']));
      setState(() => _products = List<Map>.from(res['records']));
    } else {
      final cached = await LocalDb.getCachedMasters('products');
      if (cached != null) setState(() => _products = List<Map>.from(jsonDecode(cached)));
    }
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (_parentRollController.text.trim().isEmpty || _selectedProduct == null || _quantityController.text.trim().isEmpty) {
      setState(() { _message = 'Parent Roll, Product and Quantity are required.'; _messageSuccess = false; });
      return;
    }
    setState(() => _submitting = true);
    final qty = double.tryParse(_quantityController.text) ?? 1;
    final payload = {
      'parent_roll_id': _parentRollController.text.trim(),
      'child_product_id': _selectedProduct,
      'quantity': qty,
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/production/submit', payload);
    if (res['success'] == true) {
      if (_printLabel && _selectedProductName != null) {
        final prefs = await SharedPreferences.getInstance();
        final ip = prefs.getString('printer_ip') ?? '192.168.1.100';
        final printed = await PrinterService.printLabel(
          printerIp: ip,
          productId: _selectedProduct!,
          productName: _selectedProductName!,
          parentRollId: _parentRollController.text.trim(),
          quantity: qty.toInt(),
        );
        setState(() {
          _message = printed
            ? 'Production submitted & label printed!'
            : 'Production saved but printing failed. Check printer IP.';
          _messageSuccess = printed;
        });
      } else {
        setState(() { _message = 'Production submitted successfully!'; _messageSuccess = true; });
      }
      _clearForm();
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _messageSuccess = false; });
    }
    setState(() => _submitting = false);
  }

  void _clearForm() {
    _parentRollController.clear();
    _quantityController.clear();
    _notesController.clear();
    setState(() { _selectedProduct = null; _selectedProductName = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_message != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _messageSuccess ? Colors.green[100] : Colors.red[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _messageSuccess ? Colors.green : Colors.red),
                    ),
                    child: Text(_message!, style: TextStyle(
                      color: _messageSuccess ? Colors.green[800] : Colors.red[800],
                      fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                _buildField('Parent Roll ID *', _parentRollController, autofocus: true),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedProduct,
                  style: const TextStyle(fontSize: 18, color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Child Product *',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                  ),
                  items: _products.map((p) => DropdownMenuItem<String>(
                    value: p['product_id']?.toString(),
                    child: Text('${p['product_id']} — ${p['product_name']}', style: const TextStyle(fontSize: 16)),
                  )).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedProduct = v;
                      _selectedProductName = _products.firstWhere(
                        (p) => p['product_id'] == v, orElse: () => {})['product_name']?.toString();
                    });
                  },
                ),
                const SizedBox(height: 14),
                _buildField('Quantity *', _quantityController, numeric: true),
                const SizedBox(height: 14),
                _buildField('Notes', _notesController),
                const SizedBox(height: 14),
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Switch(value: _printLabel, onChanged: (v) => setState(() => _printLabel = v)),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Print label after submission', style: TextStyle(fontSize: 16))),
                        TextButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
                          child: const Text('Printer Settings'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.precision_manufacturing, size: 24),
                        label: Text(_submitting ? 'Saving...' : 'Submit Production',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a73e8),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _clearForm,
                      child: const Text('Clear', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {bool numeric = false, bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }
}
