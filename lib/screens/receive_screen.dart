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
  final _lengthController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  final _rollIdFocusNode = FocusNode();
  final _vendorFocusNode = FocusNode();
  final _poFocusNode = FocusNode();
  final _materialTypeFocusNode = FocusNode();
  final _basisWeightFocusNode = FocusNode();
  final _widthFocusNode = FocusNode();
  final _lengthFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _notesFocusNode = FocusNode();
  final _submitFocusNode = FocusNode();

  final _vendorDropdownKey = GlobalKey<DropdownSearchState<String>>();
  final _materialTypeDropdownKey = GlobalKey<DropdownSearchState<String>>();
  final _basisWeightDropdownKey = GlobalKey<DropdownSearchState<String>>();
  final _widthDropdownKey = GlobalKey<DropdownSearchState<String>>();

  final _scrollController = ScrollController();

  List<Map> _vendors = [];
  List<String> _materialTypes = [];
  List<String> _basisWeights = [];
  List<String> _widths = [];
  String? _selectedVendor;
  String? _selectedMaterialType;
  String? _selectedBasisWeight;
  String? _selectedWidth;
  bool _loading = false;
  bool _submitting = false;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadMasters();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _rollIdController.dispose();
    _poController.dispose();
    _lengthController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    _rollIdFocusNode.dispose();
    _vendorFocusNode.dispose();
    _poFocusNode.dispose();
    _materialTypeFocusNode.dispose();
    _basisWeightFocusNode.dispose();
    _widthFocusNode.dispose();
    _lengthFocusNode.dispose();
    _weightFocusNode.dispose();
    _notesFocusNode.dispose();
    _submitFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusAndOpenDropdown(FocusNode node, GlobalKey<DropdownSearchState<String>> key) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) key.currentState?.openDropDownSearch();
    });
  }

  Future<void> _loadMasters() async {
    setState(() => _loading = true);
    try {
      final vRes = await ApiService.get('/masters/vendors');
      final wRes = await ApiService.get('/masters/widths');
      final mRes = await ApiService.get('/masters/material_types');
      final bRes = await ApiService.get('/masters/basis_weights');

      if (vRes['error'] == 'session_expired') {
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

      if (wRes['values'] != null) {
        await LocalDb.cacheMasters('widths', jsonEncode(wRes['values']));
        setState(() => _widths = List<String>.from(wRes['values']));
      } else {
        final cached = await LocalDb.getCachedMasters('widths');
        if (cached != null) setState(() => _widths = List<String>.from(jsonDecode(cached)));
      }

      if (mRes['values'] != null) {
        await LocalDb.cacheMasters('material_types', jsonEncode(mRes['values']));
        setState(() => _materialTypes = List<String>.from(mRes['values']));
      } else {
        final cached = await LocalDb.getCachedMasters('material_types');
        if (cached != null) setState(() => _materialTypes = List<String>.from(jsonDecode(cached)));
      }

      if (bRes['values'] != null) {
        await LocalDb.cacheMasters('basis_weights', jsonEncode(bRes['values']));
        setState(() => _basisWeights = List<String>.from(bRes['values']));
      } else {
        final cached = await LocalDb.getCachedMasters('basis_weights');
        if (cached != null) setState(() => _basisWeights = List<String>.from(jsonDecode(cached)));
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
    if (_selectedWidth == null ||
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
      'basis_weight': _selectedBasisWeight,
      'width': double.tryParse(_selectedWidth ?? ''),
      'length': double.tryParse(_lengthController.text),
      'weight': double.tryParse(_weightController.text),
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/rolls/receive', payload);
    if (res['success'] == true) {
      final id = res['roll_id'] ?? _rollIdController.text.trim();
      setState(() { _message = 'Roll $id received successfully!'; _messageSuccess = true; });
      _clearForm();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _messageSuccess) setState(() => _message = null);
      });
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _messageSuccess = false; });
    }
    setState(() => _submitting = false);
  }

  void _clearForm() {
    _rollIdController.clear();
    _poController.clear();
    _selectedWidth = null;
    _lengthController.clear();
    _weightController.clear();
    _notesController.clear();
    setState(() {
      _selectedVendor = null;
      _selectedMaterialType = null;
      _selectedBasisWeight = null;
    });
    FocusScope.of(context).unfocus();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Receive Parent Roll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
            controller: _scrollController,
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
                    widgetKey: const Key('rollIdField'),
                    hint: 'Auto-generated if empty',
                    focusNode: _rollIdFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey)),
                const SizedBox(height: 14),

                _buildVendorDropdown(),
                const SizedBox(height: 14),

                _buildField('PO Number', _poController,
                    widgetKey: const Key('poNumberField'),
                    focusNode: _poFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusAndOpenDropdown(_materialTypeFocusNode, _materialTypeDropdownKey)),
                const SizedBox(height: 14),

                _buildSimpleDropdown(
                  widgetKey: const Key('materialTypeDropdown'),
                  label: 'Material Type *',
                  items: _materialTypes,
                  value: _selectedMaterialType,
                  focusNode: _materialTypeFocusNode,
                  dropdownKey: _materialTypeDropdownKey,
                  enabled: _selectedBasisWeight != 'Crepe' || _selectedMaterialType == 'Crepe',
                  onChanged: (v) {
                    setState(() {
                      _selectedMaterialType = v;
                      if (v == 'Crepe') {
                        _selectedBasisWeight = 'Crepe';
                      } else if (_selectedBasisWeight == 'Crepe') {
                        _selectedBasisWeight = null;
                      }
                    });
                    _focusAndOpenDropdown(_basisWeightFocusNode, _basisWeightDropdownKey);
                  },
                ),
                const SizedBox(height: 14),

                _buildSimpleDropdown(
                  widgetKey: const Key('basisWeightDropdown'),
                  label: 'Basis Weight *',
                  items: _basisWeights,
                  value: _selectedBasisWeight,
                  focusNode: _basisWeightFocusNode,
                  dropdownKey: _basisWeightDropdownKey,
                  enabled: _selectedMaterialType != 'Crepe' || _selectedBasisWeight == 'Crepe',
                  onChanged: (v) {
                    setState(() {
                      _selectedBasisWeight = v;
                      if (v == 'Crepe') {
                        _selectedMaterialType = 'Crepe';
                      } else if (_selectedMaterialType == 'Crepe') {
                        _selectedMaterialType = null;
                      }
                    });
                    _focusAndOpenDropdown(_widthFocusNode, _widthDropdownKey);
                  },
                ),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(
                    child: _buildSimpleDropdown(
                      widgetKey: const Key('widthDropdown'),
                      label: 'Width (in) *',
                      items: _widths,
                      value: _selectedWidth,
                      focusNode: _widthFocusNode,
                      dropdownKey: _widthDropdownKey,
                      onChanged: (v) {
                        setState(() => _selectedWidth = v);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _lengthFocusNode.requestFocus();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField('Length (ft) *', _lengthController,
                        widgetKey: const Key('lengthField'),
                        focusNode: _lengthFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _weightFocusNode.requestFocus()),
                  ),
                ]),
                const SizedBox(height: 14),

                _buildField('Weight (lbs) *', _weightController,
                    widgetKey: const Key('weightField'),
                    focusNode: _weightFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    hint: 'Overall weight of the roll',
                    onSubmitted: (_) => _submitFocusNode.requestFocus()),
                const SizedBox(height: 14),

                _buildField('Notes', _notesController,
                    focusNode: _notesFocusNode,
                    multiline: true),
                const SizedBox(height: 24),

                Row(children: [
                  Expanded(
                    child: Focus(
                      focusNode: _submitFocusNode,
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          key: const Key('submitButton'),
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
          ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {bool autofocus = false, String? hint,
       FocusNode? focusNode, bool multiline = false,
       TextInputType? keyboardType, TextInputAction? textInputAction,
       Function(String)? onSubmitted, Key? widgetKey}) {
    return TextField(
      key: widgetKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: multiline
          ? TextInputType.multiline
          : (keyboardType ?? TextInputType.text),
      textInputAction: multiline
          ? TextInputAction.newline
          : textInputAction,
      maxLines: multiline ? 3 : 1,
      minLines: multiline ? 1 : null,
      onSubmitted: onSubmitted,
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
    return Focus(
      key: const Key('vendorDropdown'),
      focusNode: _vendorFocusNode,
      child: DropdownSearch<String>(
        key: _vendorDropdownKey,
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
          FocusManager.instance.primaryFocus?.unfocus();
          if (val == null) { setState(() => _selectedVendor = null); return; }
          setState(() => _selectedVendor = val.split(' — ')[0]);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _poFocusNode.requestFocus();
          });
        },
      ),
    );
  }

  Widget _buildSimpleDropdown({
    required String label,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
    required FocusNode focusNode,
    required GlobalKey<DropdownSearchState<String>> dropdownKey,
    bool enabled = true,
    Key? widgetKey,
  }) {
    return Focus(
      key: widgetKey,
      focusNode: focusNode,
      child: DropdownSearch<String>(
        key: dropdownKey,
        enabled: enabled,
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
        onChanged: (v) {
          FocusManager.instance.primaryFocus?.unfocus();
          onChanged(v);
        },
      ),
    );
  }
}
