import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import 'login_screen.dart';

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
  List<String> _materialTypes = [];
  List<String> _basisWeights = [];
  String? _selectedVendor;
  String? _selectedMaterialType;
  String? _selectedBasisWeight;
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
    try {
    final vRes = await ApiService.get('/masters/vendors');
    final pRes = await ApiService.get('/masters/products');

    if (vRes['error'] == 'session_expired' || pRes['error'] == 'session_expired') {
      if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    if (vRes['records'] != null) {
      await LocalDb.cacheMasters('vendors', jsonEncode(vRes['records']));
      setState(() => _vendors = List<Map>.from(vRes['records']));
    } else {
      final cached = await LocalDb.getCachedMasters('vendors');
      if (cached != null) setState(() => _vendors = List<Map>.from(jsonDecode(cached)));
    }

    if (pRes['records'] != null) {
      await LocalDb.cacheMasters('products', jsonEncode(pRes['records']));
      final products = List<Map>.from(pRes['records']);
      final matTypes = products
          .map((p) => p['material_type']?.toString() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet().toList()..sort();
      final basisWts = products
          .map((p) => p['basis_weight']?.toString() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet().toList()
          ..sort((a, b) => double.tryParse(a)!.compareTo(double.tryParse(b)!));
      setState(() {
        _materialTypes = matTypes;
        _basisWeights = basisWts;
      });
    } else {
      final cached = await LocalDb.getCachedMasters('products');
      if (cached != null) {
        final products = List<Map>.from(jsonDecode(cached));
        final matTypes = products
            .map((p) => p['material_type']?.toString() ?? '')
            .where((v) => v.isNotEmpty)
            .toSet().toList()..sort();
        final basisWts = products
            .map((p) => p['basis_weight']?.toString() ?? '')
            .where((v) => v.isNotEmpty)
            .toSet().toList()
            ..sort((a, b) => double.tryParse(a)!.compareTo(double.tryParse(b)!));
        setState(() {
          _materialTypes = matTypes;
          _basisWeights = basisWts;
        });
      }
    }
    setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedVendor == null || _selectedMaterialType == null || _selectedBasisWeight == null) {
      setState(() {
        _message = 'Vendor, Material Type and Basis Weight are required.';
        _messageSuccess = false;
      });
      return;
    }
    if (_widthController.text.trim().isEmpty ||
        _lengthController.text.trim().isEmpty ||
        _weightController.text.trim().isEmpty) {
      setState(() {
        _message = 'Width, Length and Weight are required.';
        _messageSuccess = false;
      });
      return;
    }
    setState(() => _submitting = true);
    final payload = {
      'roll_id': _rollIdController.text.trim().isEmpty ? null : _rollIdController.text.trim(),
      'vendor_id': _selectedVendor,
      'po_number': _poController.text.trim(),
      'material_type': _selectedMaterialType,
      'basis_weight': double.tryParse(_selectedBasisWeight!),
      'width': double.tryParse(_widthController.text),
      'length': double.tryParse(_lengthController.text),
      'weight': double.tryParse(_weightController.text),
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/rolls/receive', payload);
    if (res['success'] == true) {
      final id = res['roll_id'] ?? _rollIdController.text.trim();
      setState(() { _message = 'Roll $id received successfully!'; _messageSuccess = true; });
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
    setState(() {
      _selectedVendor = null;
      _selectedMaterialType = null;
      _selectedBasisWeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1c2128),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Receive Parent Roll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
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

                _buildField('Roll ID', _rollIdController,
                    hint: 'Auto-generated if empty', autofocus: true),
                const SizedBox(height: 14),

                _buildVendorDropdown(),
                const SizedBox(height: 14),

                _buildField('PO Number', _poController),
                const SizedBox(height: 14),

                _buildSimpleDropdown(
                  label: 'Material Type *',
                  items: _materialTypes,
                  value: _selectedMaterialType,
                  onChanged: (v) => setState(() => _selectedMaterialType = v),
                ),
                const SizedBox(height: 14),

                _buildSimpleDropdown(
                  label: 'Basis Weight *',
                  items: _basisWeights,
                  value: _selectedBasisWeight,
                  onChanged: (v) => setState(() => _selectedBasisWeight = v),
                ),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(child: _buildField('Width (in) *', _widthController, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField('Length (ft) *', _lengthController, numeric: true)),
                ]),
                const SizedBox(height: 14),

                _buildField('Weight (lbs) *', _weightController,
                    numeric: true, hint: 'Overall weight of the roll'),
                const SizedBox(height: 14),

                _buildField('Notes', _notesController),
                const SizedBox(height: 24),

                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, size: 24),
                        label: Text(_submitting ? 'Saving...' : 'Receive Roll',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a73e8),
                          foregroundColor: Colors.white),
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

  Widget _buildField(String label, TextEditingController controller,
      {bool numeric = false, bool autofocus = false, String? hint}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }

  Widget _buildVendorDropdown() {
    final itemList = _vendors.map((v) => '${v['vendor_id']} — ${v['vendor_name']}').toList();
    final selectedItem = _selectedVendor != null
        ? _vendors.where((v) => v['vendor_id']?.toString() == _selectedVendor).isNotEmpty
            ? '${_selectedVendor} — ${_vendors.firstWhere((v) => v['vendor_id']?.toString() == _selectedVendor)['vendor_name']}'
            : null
        : null;
    return DropdownSearch<String>(
      items: itemList,
      selectedItem: selectedItem,
      dropdownDecoratorProps: const DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: 'Vendor *',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        ),
      ),
      popupProps: PopupProps.menu(
        showSearchBox: true,
        searchFieldProps: const TextFieldProps(
          decoration: InputDecoration(
            hintText: 'Search vendors...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          ),
          autofocus: true,
        ),
        constraints: const BoxConstraints(maxHeight: 300),
        itemBuilder: (context, item, isSelected) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Text(item, style: TextStyle(
            fontSize: 16,
            color: isSelected ? const Color(0xFF1a73e8) : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
        ),
      ),
      onChanged: (val) {
        if (val == null) { setState(() => _selectedVendor = null); return; }
        setState(() => _selectedVendor = val.split(' — ')[0]);
      },
    );
  }

  Widget _buildSimpleDropdown({
    required String label,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return DropdownSearch<String>(
      items: items,
      selectedItem: value,
      dropdownDecoratorProps: DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        ),
      ),
      popupProps: PopupProps.menu(
        showSearchBox: items.length > 5,
        constraints: const BoxConstraints(maxHeight: 250),
        itemBuilder: (context, item, isSelected) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Text(item, style: TextStyle(
            fontSize: 16,
            color: isSelected ? const Color(0xFF1a73e8) : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
        ),
      ),
      onChanged: onChanged,
    );
  }
}
