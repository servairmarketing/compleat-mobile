import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/printer_service.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});
  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Label Printing tab
  final _lpParent1 = TextEditingController();
  final _lpParent2 = TextEditingController();
  bool _lpTwoParent = false;
  String? _lpSelectedProduct;
  String? _lpSelectedProductName;
  final _lpQtyController = TextEditingController();
  bool _lpPrinting = false;

  // Roll Production tab
  final _rpParent1 = TextEditingController();
  final _rpParent2 = TextEditingController();
  bool _rpTwoParent = false;
  final _rpScanController = TextEditingController();
  final _rpScanFocus = FocusNode();
  Map<String, Map<String, dynamic>> _scannedItems = {};
  String _selectedStatus = '';
  final _rpNotesController = TextEditingController();
  bool _submitting = false;

  List<Map> _products = [];
  bool _loading = false;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _lpParent1.dispose(); _lpParent2.dispose();
    _rpParent1.dispose(); _rpParent2.dispose();
    _rpScanController.dispose(); _rpScanFocus.dispose();
    _lpQtyController.dispose(); _rpNotesController.dispose();
    super.dispose();
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

  void _showMessage(String msg, bool success) {
    setState(() { _message = msg; _messageSuccess = success; });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  // ── Label Printing ─────────────────────────────────────────────
  Future<void> _printLabels() async {
    final p1 = _lpParent1.text.trim();
    final p2 = _lpParent2.text.trim();
    final qty = int.tryParse(_lpQtyController.text.trim()) ?? 0;

    if (p1.isEmpty || _lpSelectedProduct == null || qty <= 0) {
      _showMessage('Parent Roll ID, Product and Quantity are required.', false); return;
    }
    if (_lpTwoParent && p2.isEmpty) {
      _showMessage('Please enter the second Parent Roll ID.', false); return;
    }

    setState(() => _lpPrinting = true);
    final printed = await PrinterService.printLabel(
      productId: _lpSelectedProduct!,
      productName: _lpSelectedProductName ?? _lpSelectedProduct!,
      parentRollId1: p1,
      parentRollId2: _lpTwoParent ? p2 : null,
      quantity: qty,
    );
    setState(() => _lpPrinting = false);

    if (printed) {
      _showMessage('$qty label(s) sent to printer!', true);
    } else {
      _showMessage('Printing failed. Make sure Brother iPrint&Label app is installed.', false);
    }
  }

  void _goToProduction() {
    final p1 = _lpParent1.text.trim();
    final p2 = _lpParent2.text.trim();
    if (p1.isNotEmpty) {
      _rpParent1.text = p1;
      if (_lpTwoParent && p2.isNotEmpty) {
        setState(() => _rpTwoParent = true);
        _rpParent2.text = p2;
      }
    }
    _tabController.animateTo(1);
    Future.delayed(const Duration(milliseconds: 300), () => _rpScanFocus.requestFocus());
  }

  void _clearLabelForm() {
    _lpParent1.clear(); _lpParent2.clear(); _lpQtyController.clear();
    setState(() { _lpTwoParent = false; _lpSelectedProduct = null; _lpSelectedProductName = null; });
  }

  // ── Roll Production ────────────────────────────────────────────
  void _processScan(String value) {
    final productId = value.trim();
    if (productId.isEmpty) return;

    final product = _products.firstWhere(
      (p) => p['product_id']?.toString() == productId,
      orElse: () => {},
    );
    final productName = product['product_name']?.toString() ?? productId;

    setState(() {
      if (_scannedItems.containsKey(productId)) {
        _scannedItems[productId]!['count'] = (_scannedItems[productId]!['count'] as int) + 1;
      } else {
        _scannedItems[productId] = {'count': 1, 'name': productName};
      }
    });

    _rpScanController.clear();
    HapticFeedback.lightImpact();
  }

  void _selectStatus(String status) {
    setState(() => _selectedStatus = status);
  }

  Future<void> _submitProduction() async {
    final p1 = _rpParent1.text.trim();
    final p2 = _rpParent2.text.trim();

    if (p1.isEmpty) { _showMessage('Parent Roll ID is required.', false); return; }
    if (_rpTwoParent && p2.isEmpty) { _showMessage('Please enter the second Parent Roll ID.', false); return; }
    if (_scannedItems.isEmpty) { _showMessage('Please scan at least one child roll.', false); return; }
    if (_selectedStatus.isEmpty) { _showMessage('Please select the parent roll status.', false); return; }

    setState(() => _submitting = true);

    final parentRollIds = _rpTwoParent ? [p1, p2] : [p1];
    final parentStatuses = parentRollIds.map((_) => _selectedStatus).toList();
    final items = _scannedItems.entries.map((e) => {
      'product_id': e.key,
      'quantity': e.value['count'],
    }).toList();

    final profile = await ApiService.getUserProfile();
    final payload = {
      'parent_roll_ids': parentRollIds,
      'parent_statuses': parentStatuses,
      'items': items,
      'created_by': profile?['name'] ?? profile?['username'] ?? 'unknown',
      'notes': _rpNotesController.text.trim(),
    };

    final res = await ApiService.post('/production/submit', payload);
    setState(() => _submitting = false);

    if (res['success'] == true) {
      _showMessage('Production submitted successfully!', true);
      _clearProductionForm();
    } else {
      _showMessage(res['detail'] ?? 'Error submitting production.', false);
    }
  }

  void _clearProductionForm() {
    _rpParent1.clear(); _rpParent2.clear(); _rpNotesController.clear();
    _rpScanController.clear();
    setState(() {
      _rpTwoParent = false;
      _scannedItems = {};
      _selectedStatus = '';
    });
  }

  int get _totalScanned => _scannedItems.values.fold(0, (s, e) => s + (e['count'] as int));

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1c2128),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Production', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _innerBuild(context),
    );
  }

  Widget _innerBuild(BuildContext context) {
    return _loading
      ? const Center(child: CircularProgressIndicator())
      : Column(
          children: [
            if (_message != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: _messageSuccess ? Colors.green[100] : Colors.red[100],
                child: Text(_message!,
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: _messageSuccess ? Colors.green[800] : Colors.red[800]),
                ),
              ),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1a73e8),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1a73e8),
              labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.print, size: 22), text: 'Label Printing'),
                Tab(icon: Icon(Icons.precision_manufacturing, size: 22), text: 'Roll Production'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildLabelTab(), _buildProductionTab()],
              ),
            ),
          ],
        );
  }

  // ── Label Printing Tab ─────────────────────────────────────────
  Widget _buildLabelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two parent toggle
          Card(
            color: Colors.blue[50],
            child: SwitchListTile(
              title: const Text('Two parent rolls', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              subtitle: const Text('Enable if child roll spans two parent rolls'),
              value: _lpTwoParent,
              onChanged: (v) => setState(() { _lpTwoParent = v; if (!v) _lpParent2.clear(); }),
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField('Parent Roll ID 1 *', _lpParent1, autofocus: true),
          if (_lpTwoParent) ...[
            const SizedBox(height: 12),
            _buildTextField('Parent Roll ID 2 *', _lpParent2),
          ],
          const SizedBox(height: 12),
          DropdownSearch<String>(
            items: _products.map((p) => '${p['product_id']} — ${p['product_name']}').toList(),
            selectedItem: _lpSelectedProduct != null && _products.any((p) => p['product_id'] == _lpSelectedProduct)
                ? '$_lpSelectedProduct — ${_products.firstWhere((p) => p['product_id'] == _lpSelectedProduct)['product_name']}'
                : null,
            dropdownDecoratorProps: const DropDownDecoratorProps(
              dropdownSearchDecoration: InputDecoration(
                labelText: 'Product *',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              ),
            ),
            popupProps: PopupProps.menu(
              showSearchBox: true,
              searchFieldProps: const TextFieldProps(
                decoration: InputDecoration(
                  hintText: 'Type to search...',
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
              if (val == null) return;
              final id = val.split(' — ')[0];
              setState(() {
                _lpSelectedProduct = id;
                _lpSelectedProductName = _products.firstWhere(
                  (p) => p['product_id'] == id, orElse: () => {})['product_name']?.toString();
              });
            },
          ),
          const SizedBox(height: 12),
          _buildTextField('Number of Labels *', _lpQtyController, numeric: true),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _lpPrinting ? null : _printLabels,
                  icon: _lpPrinting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print, size: 24),
                  label: Text(_lpPrinting ? 'Printing...' : 'Print Labels',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a73e8), foregroundColor: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _goToProduction,
                icon: const Icon(Icons.arrow_forward, size: 22),
                label: const Text('Production', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700], foregroundColor: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _clearLabelForm,
              child: const Text('Clear', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Roll Production Tab ────────────────────────────────────────
  Widget _buildProductionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two parent toggle
          Card(
            color: Colors.blue[50],
            child: SwitchListTile(
              title: const Text('Two parent rolls', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              subtitle: const Text('Enable if child roll spans two parent rolls'),
              value: _rpTwoParent,
              onChanged: (v) => setState(() { _rpTwoParent = v; if (!v) _rpParent2.clear(); }),
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField('Parent Roll ID 1 *', _rpParent1),
          if (_rpTwoParent) ...[
            const SizedBox(height: 12),
            _buildTextField('Parent Roll ID 2 *', _rpParent2),
          ],
          const SizedBox(height: 16),

          // Scan counter
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFe8f0fe),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1a73e8), width: 2),
            ),
            child: Row(
              children: [
                Text('$_totalScanned',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1a73e8))),
                const SizedBox(width: 16),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Child Rolls Scanned', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Scan barcode below to count', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Scan field
          TextField(
            controller: _rpScanController,
            focusNode: _rpScanFocus,
            autofocus: false,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Scan Product Barcode',
              hintText: 'Scan here...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              prefixIcon: Icon(Icons.qr_code_scanner, size: 28),
            ),
            onSubmitted: (v) { _processScan(v); _rpScanFocus.requestFocus(); },
            onChanged: (v) {
              if (v.endsWith('\n') || v.length > 20) _processScan(v);
            },
          ),
          const SizedBox(height: 12),

          // Scanned items list
          if (_scannedItems.isNotEmpty) ...[
            const Text('Scanned Items:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._scannedItems.entries.map((e) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(e.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
                subtitle: Text(e.value['name'].toString(), style: const TextStyle(fontSize: 14)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('×${e.value['count']}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1a73e8))),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() => _scannedItems.remove(e.key)),
                    ),
                  ],
                ),
              ),
            )),
            const SizedBox(height: 8),
          ],

          // Parent roll status
          const Text('Parent Roll Status *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            _statusButton('in_stock', '🟢 In Stock', Colors.green[700]!),
            const SizedBox(width: 8),
            _statusButton('production', '🟡 Production', Colors.orange[700]!),
            const SizedBox(width: 8),
            _statusButton('finished', '🔴 Finished', Colors.red[700]!),
          ]),
          const SizedBox(height: 12),
          _buildTextField('Notes (optional)', _rpNotesController),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitProduction,
              icon: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle, size: 24),
              label: Text(_submitting ? 'Submitting...' : 'Submit Production',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700], foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _clearProductionForm,
              child: const Text('Clear', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton(String status, String label, Color color) {
    final selected = _selectedStatus == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectStatus(status),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : Colors.white,
            border: Border.all(color: selected ? color : Colors.grey[300]!, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: selected ? color : Colors.grey[600]),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool numeric = false, bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      ),
    );
  }
  }
}
