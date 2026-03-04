import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _rollIdController = TextEditingController();
  final _poController = TextEditingController();
  final _widthController = TextEditingController();
  final _lengthController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  List<Map> _vendors = [];
  List<Map> _products = [];
  String? _selectedVendor;
  String? _selectedProduct;
  bool _loading = false;
  bool _submitting = false;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadMasters();
  }

  Future<void> _loadMasters() async {
    setState(() => _loading = true);
    final vRes = await ApiService.get('/masters/vendors');
    final pRes = await ApiService.get('/masters/products');
    if (vRes['records'] != null) {
      await LocalDb.cacheMasters('vendors', jsonEncode(vRes['records']));
      setState(() => _vendors = List<Map>.from(vRes['records']));
    } else {
      final cached = await LocalDb.getCachedMasters('vendors');
      if (cached != null) setState(() => _vendors = List<Map>.from(jsonDecode(cached)));
    }
    if (pRes['records'] != null) {
      await LocalDb.cacheMasters('products', jsonEncode(pRes['records']));
      setState(() => _products = List<Map>.from(pRes['records']));
    } else {
      final cached = await LocalDb.getCachedMasters('products');
      if (cached != null) setState(() => _products = List<Map>.from(jsonDecode(cached)));
    }
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (_rollIdController.text.trim().isEmpty || _selectedVendor == null || _selectedProduct == null) {
      setState(() { _message = 'Roll ID, Vendor and Product are required.'; _messageSuccess = false; });
      return;
    }
    setState(() => _submitting = true);
    final payload = {
      'roll_id': _rollIdController.text.trim(),
      'vendor_id': _selectedVendor,
      'product_id': _selectedProduct,
      'po_number': _poController.text.trim(),
      'width': double.tryParse(_widthController.text),
      'length': double.tryParse(_lengthController.text),
      'weight': double.tryParse(_weightController.text),
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/rolls/receive', payload);
    if (res['success'] == true) {
      setState(() { _message = 'Roll ${_rollIdController.text.trim()} received!'; _messageSuccess = true; });
      _clearForm();
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _messageSuccess = false; });
    }
    setState(() => _submitting = false);
  }

  void _clearForm() {
    _rollIdController.clear();
    _poController.clear();
    _widthController.clear();
    _lengthController.clear();
    _weightController.clear();
    _notesController.clear();
    setState(() { _selectedVendor = null; _selectedProduct = null; });
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
                _buildField('Roll ID / Barcode *', _rollIdController, autofocus: true),
                const SizedBox(height: 14),
                _buildDropdown('Vendor *', _vendors, 'vendor_id', 'vendor_name', _selectedVendor, (v) => setState(() => _selectedVendor = v)),
                const SizedBox(height: 14),
                _buildDropdown('Product *', _products, 'product_id', 'product_name', _selectedProduct, (v) => setState(() => _selectedProduct = v)),
                const SizedBox(height: 14),
                _buildField('PO Number', _poController),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _buildField('Width (in)', _widthController, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField('Length (ft)', _lengthController, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField('Weight (lbs)', _weightController, numeric: true)),
                ]),
                const SizedBox(height: 14),
                _buildField('Notes', _notesController),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded, size: 24),
                        label: Text(_submitting ? 'Saving...' : 'Receive Roll', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1a73e8), foregroundColor: Colors.white),
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

  Widget _buildDropdown(String label, List<Map> items, String idKey, String nameKey, String? value, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      style: const TextStyle(fontSize: 18, color: Colors.black),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14)),
      items: items.map((item) => DropdownMenuItem<String>(
        value: item[idKey]?.toString(),
        child: Text('${item[idKey]} — ${item[nameKey]}', style: const TextStyle(fontSize: 16)),
      )).toList(),
      onChanged: onChanged,
    );
  }
}
