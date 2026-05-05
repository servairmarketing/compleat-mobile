import 'package:flutter/material.dart';
import 'login_screen.dart';
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
  int _lastTabIndex = 0;

  // Label Printing tab
  final _lpParent1 = TextEditingController();
  final _lpParent2 = TextEditingController();
  bool _lpTwoParent = false;
  String? _lpSelectedProduct;
  String? _lpSelectedProductName;
  final _lpQtyController = TextEditingController();
  bool _lpPrinting = false;
  final _lpParent1Focus = FocusNode();
  final _lpParent2Focus = FocusNode();
  final _lpProductFocus = FocusNode();
  final _lpQtyFocus = FocusNode();
  final _lpPrintFocus = FocusNode();
  final _lpProductKey = GlobalKey<DropdownSearchState<String>>();
  final _lpScrollController = ScrollController();

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
  final _rpParent1Focus = FocusNode();
  final _rpParent2Focus = FocusNode();
  final _rpNotesFocus = FocusNode();
  final _rpSubmitFocus = FocusNode();
  final _rpScrollController = ScrollController();

  // Parent roll data fetched from API
  Map<String, dynamic>? _lpParentRoll1Data;
  Map<String, dynamic>? _lpParentRoll2Data;
  Map<String, dynamic>? _rpParentRoll1Data;
  Map<String, dynamic>? _rpParentRoll2Data;
  bool _lpValidatingParent = false;
  bool _rpValidatingParent = false;

  List<Map> _products = [];
  bool _loading = false;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lpParent1Focus.requestFocus();
    });
  }

  void _handleTabChange() {
    if (_tabController.index == _lastTabIndex) return;
    _lastTabIndex = _tabController.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tabController.index == 0) {
        _lpParent1Focus.requestFocus();
      } else {
        _rpParent1Focus.requestFocus();
      }
    });
  }

  void _focusAndOpenLpProduct() {
    _lpProductFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lpProductKey.currentState?.openDropDownSearch();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _lpParent1.dispose(); _lpParent2.dispose();
    _rpParent1.dispose(); _rpParent2.dispose();
    _rpScanController.dispose(); _rpScanFocus.dispose();
    _lpQtyController.dispose(); _rpNotesController.dispose();
    _lpParent1Focus.dispose();
    _lpParent2Focus.dispose();
    _lpProductFocus.dispose();
    _lpQtyFocus.dispose();
    _lpPrintFocus.dispose();
    _lpScrollController.dispose();
    _rpParent1Focus.dispose();
    _rpParent2Focus.dispose();
    _rpNotesFocus.dispose();
    _rpSubmitFocus.dispose();
    _rpScrollController.dispose();
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
    // session expiry handled by ApiService redirect
  }

  void _showMessage(String msg, bool success) {
    setState(() { _message = msg; _messageSuccess = success; });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  List<Map> get _lpFilteredProducts {
    if (_lpParentRoll1Data == null) return [];
    final parentMt = _lpParentRoll1Data!['material_type']?.toString() ?? '';
    final parentBw = _lpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final parentW = double.tryParse(_lpParentRoll1Data!['width']?.toString() ?? '') ?? 0;
    return _products.where((p) {
      final pMt = p['material_type']?.toString() ?? '';
      final pBw = p['basis_weight']?.toString() ?? '';
      final pW = double.tryParse(p['width']?.toString() ?? '') ?? 0;
      if (parentMt.isNotEmpty && pMt != parentMt) return false;
      if (parentBw.isNotEmpty && pBw != parentBw) return false;
      if (parentW > 0 && pW > parentW) return false;
      return true;
    }).toList();
  }

  Future<bool> _confirmNarrowerWidth(
      BuildContext context, double parentW, double prodW, String productId,
      {bool isScan = false}) async {
    final body = isScan
        ? 'Scanned product $productId width is ${prodW}" but parent roll width is ${parentW}". Are you sure you want to add this child roll?'
        : 'Selected product width is ${prodW}" but parent roll width is ${parentW}". Are you sure you want to create a child roll of smaller width?';
    final yesLabel = isScan ? 'Yes, add' : 'Yes, continue';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm narrower child roll'),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(yesLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<Map<String, dynamic>?> _fetchParentRoll(String rollId) async {
    final res = await ApiService.get('/rolls/${rollId}');
    if (res['roll'] != null) return Map<String, dynamic>.from(res['roll']);
    if (res['roll_id'] != null) return Map<String, dynamic>.from(res);
    return null;
  }

  Future<void> _validateLpParent1() async {
    final id = _lpParent1.text.trim();
    if (id.isEmpty) { setState(() => _lpParentRoll1Data = null); return; }
    setState(() => _lpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _lpValidatingParent = false);
    if (data == null) {
      setState(() => _lpParentRoll1Data = null);
      _showMessage('Parent Roll ID 1 not found. Please check the ID and try again.', false); return;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      setState(() => _lpParentRoll1Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false); return;
    }
    setState(() => _lpParentRoll1Data = data);
    // Clear product selection when parent roll changes
    setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; });
  }

  Future<void> _validateLpParent2() async {
    final id = _lpParent2.text.trim();
    if (id.isEmpty) { setState(() => _lpParentRoll2Data = null); return; }
    if (id == _lpParent1.text.trim()) {
      _showMessage('Parent Roll 2 cannot be the same as Parent Roll 1.', false); return;
    }
    if (_lpParentRoll1Data == null) {
      _showMessage('Please validate Parent Roll ID 1 first.', false); return;
    }
    setState(() => _lpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _lpValidatingParent = false);
    if (data == null) {
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Parent Roll ID 2 not found. Please check the ID and try again.', false); return;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false); return;
    }
    // Cross-validate against Roll 1
    final mt1 = _lpParentRoll1Data!['material_type']?.toString() ?? '';
    final mt2 = data['material_type']?.toString() ?? '';
    if (mt1.isNotEmpty && mt2.isNotEmpty && mt1 != mt2) {
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Material type mismatch: Roll 1 is $mt1 but Roll 2 is $mt2. Both parent rolls must be the same material type.', false); return;
    }
    final bw1 = _lpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final bw2 = data['basis_weight']?.toString() ?? '';
    if (bw1.isNotEmpty && bw2.isNotEmpty && bw1 != bw2) {
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Basis weight mismatch: Roll 1 is $bw1 lbs but Roll 2 is $bw2 lbs. Both parent rolls must have the same basis weight.', false); return;
    }
    final w1 = double.tryParse(_lpParentRoll1Data!['width']?.toString() ?? '') ?? 0;
    final w2 = double.tryParse(data['width']?.toString() ?? '') ?? 0;
    if (w1 > 0 && w2 > 0 && w2 < w1) {
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Width mismatch: Roll 1 is ${w1}" wide but Roll 2 is ${w2}" wide. Parent Roll 2 cannot be narrower than Parent Roll 1.', false); return;
    }
    setState(() => _lpParentRoll2Data = data);
  }

  Future<void> _validateRpParent1() async {
    final id = _rpParent1.text.trim();
    if (id.isEmpty) { setState(() => _rpParentRoll1Data = null); return; }
    setState(() => _rpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _rpValidatingParent = false);
    if (data == null) {
      setState(() => _rpParentRoll1Data = null);
      _showMessage('Parent Roll ID 1 not found. Please check the ID and try again.', false); return;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      setState(() => _rpParentRoll1Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false); return;
    }
    setState(() => _rpParentRoll1Data = data);
    // Clear scanned items when parent roll changes
    setState(() => _scannedItems = {});
  }

  Future<void> _validateRpParent2() async {
    final id = _rpParent2.text.trim();
    if (id.isEmpty) { setState(() => _rpParentRoll2Data = null); return; }
    if (id == _rpParent1.text.trim()) {
      _showMessage('Parent Roll 2 cannot be the same as Parent Roll 1.', false); return;
    }
    if (_rpParentRoll1Data == null) {
      _showMessage('Please validate Parent Roll ID 1 first.', false); return;
    }
    setState(() => _rpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _rpValidatingParent = false);
    if (data == null) {
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Parent Roll ID 2 not found. Please check the ID and try again.', false); return;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false); return;
    }
    // Cross-validate against Roll 1
    final mt1 = _rpParentRoll1Data!['material_type']?.toString() ?? '';
    final mt2 = data['material_type']?.toString() ?? '';
    if (mt1.isNotEmpty && mt2.isNotEmpty && mt1 != mt2) {
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Material type mismatch: Roll 1 is $mt1 but Roll 2 is $mt2. Both parent rolls must be the same material type.', false); return;
    }
    final bw1 = _rpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final bw2 = data['basis_weight']?.toString() ?? '';
    if (bw1.isNotEmpty && bw2.isNotEmpty && bw1 != bw2) {
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Basis weight mismatch: Roll 1 is $bw1 lbs but Roll 2 is $bw2 lbs. Both parent rolls must have the same basis weight.', false); return;
    }
    final w1 = double.tryParse(_rpParentRoll1Data!['width']?.toString() ?? '') ?? 0;
    final w2 = double.tryParse(data['width']?.toString() ?? '') ?? 0;
    if (w1 > 0 && w2 > 0 && w2 < w1) {
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Width mismatch: Roll 1 is ${w1}" wide but Roll 2 is ${w2}" wide. Parent Roll 2 cannot be narrower than Parent Roll 1.', false); return;
    }
    setState(() => _rpParentRoll2Data = data);
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
    // New dual-barcode label: one parent ID per label, same product ID on every
    // label — loop the print call once per parent so each parent gets its own roll.
    final parentIds = (_lpTwoParent && p2.isNotEmpty) ? [p1, p2] : [p1];
    String? errorDetail;
    for (final pid in parentIds) {
      final detail = await PrinterService.printLabel(
        productId: _lpSelectedProduct!,
        productName: _lpSelectedProductName ?? _lpSelectedProduct!,
        parentRollId1: pid,
        parentRollId2: null,
        quantity: qty,
      );
      if (detail.startsWith('ERROR')) { errorDetail = detail; break; }
    }
    setState(() => _lpPrinting = false);

    if (errorDetail == null) {
      final total = qty * parentIds.length;
      _showMessage('$total label(s) sent to printer!', true);
      FocusScope.of(context).unfocus();
      if (_lpScrollController.hasClients) {
        _lpScrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lpParent1Focus.requestFocus();
      });
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
    setState(() { _lpParentRoll1Data = null; _lpParentRoll2Data = null; });
  }

  // ── Roll Production ────────────────────────────────────────────
  Future<void> _processScan(String value) async {
    final productId = value.trim();
    if (productId.isEmpty) return;

    if (_rpParentRoll1Data == null) {
      _showMessage('Please enter and confirm Parent Roll ID 1 before scanning.', false);
      _rpScanController.clear();
      return;
    }

    final product = _products.firstWhere(
      (p) => p['product_id']?.toString() == productId,
      orElse: () => {},
    );

    if (_rpParentRoll1Data != null && product.isNotEmpty) {
      final pMt = product['material_type']?.toString() ?? '';
      final rMt = _rpParentRoll1Data!['material_type']?.toString() ?? '';
      final pBw = product['basis_weight']?.toString() ?? '';
      final rBw = _rpParentRoll1Data!['basis_weight']?.toString() ?? '';
      final pW = double.tryParse(product['width']?.toString() ?? '') ?? 0;
      final rW = double.tryParse(_rpParentRoll1Data!['width']?.toString() ?? '') ?? 0;
      if (rMt.isNotEmpty && pMt.isNotEmpty && pMt != rMt) {
        _showMessage('Material type mismatch: Parent roll is $rMt but scanned product $productId is $pMt. Scan rejected.', false);
        _rpScanController.clear(); return;
      }
      if (rBw.isNotEmpty && pBw.isNotEmpty && pBw != rBw) {
        _showMessage('Basis weight mismatch: Parent roll is $rBw lbs but scanned product $productId requires $pBw lbs. Scan rejected.', false);
        _rpScanController.clear(); return;
      }
      if (rW > 0 && pW > 0 && pW > rW) {
        _showMessage('Width mismatch: Scanned product $productId width ${pW}" exceeds parent roll width ${rW}". Scan rejected.', false);
        _rpScanController.clear(); return;
      }
      if (rW > 0 && pW > 0 && pW < rW) {
        final ok = await _confirmNarrowerWidth(context, rW, pW, productId, isScan: true);
        if (!ok) { _rpScanController.clear(); return; }
      }
    }
    if (product.isEmpty) {
      _showMessage('Product $productId not found in product master. Please check the barcode.', false);
      _rpScanController.clear(); return;
    }

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
    setState(() { _rpParentRoll1Data = null; _rpParentRoll2Data = null; });
    FocusScope.of(context).unfocus();
    if (_rpScrollController.hasClients) {
      _rpScrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rpParent1Focus.requestFocus();
    });
  }

  int get _totalScanned => _scannedItems.values.fold(0, (s, e) => s + (e['count'] as int));

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
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
      controller: _lpScrollController,
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
          _buildTextField('Parent Roll ID 1 *', _lpParent1,
              focusNode: _lpParent1Focus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) async {
                await _validateLpParent1();
                if (!mounted) return;
                if (_lpTwoParent) {
                  _lpParent2Focus.requestFocus();
                } else {
                  _focusAndOpenLpProduct();
                }
              }),
          if (_lpParentRoll1Data != null)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text(
                'Material: ${_lpParentRoll1Data!['material_type'] ?? '-'}  |  Basis Weight: ${_lpParentRoll1Data!['basis_weight'] ?? '-'} lbs  |  Width: ${_lpParentRoll1Data!['width'] ?? '-'}"',
                style: TextStyle(fontSize: 13, color: Colors.green[800]),
              ),
            ),
          if (_lpTwoParent) ...[
            const SizedBox(height: 12),
            _buildTextField('Parent Roll ID 2 *', _lpParent2,
                focusNode: _lpParent2Focus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) async {
                  await _validateLpParent2();
                  if (!mounted) return;
                  _focusAndOpenLpProduct();
                }),
            if (_lpParentRoll2Data != null)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Text(
                  'Material: ${_lpParentRoll2Data!['material_type'] ?? '-'}  |  Basis Weight: ${_lpParentRoll2Data!['basis_weight'] ?? '-'} lbs  |  Width: ${_lpParentRoll2Data!['width'] ?? '-'}"',
                  style: TextStyle(fontSize: 13, color: Colors.green[800]),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Focus(
            focusNode: _lpProductFocus,
            child: DropdownSearch<String>(
            key: _lpProductKey,
            items: _lpFilteredProducts.map((p) => '${p['product_id']} — ${p['product_name']}').toList(),
            selectedItem: _lpSelectedProduct != null && _lpFilteredProducts.any((p) => p['product_id'] == _lpSelectedProduct)
                ? '$_lpSelectedProduct — ${_lpFilteredProducts.firstWhere((p) => p['product_id'] == _lpSelectedProduct)['product_name']}'
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
            onChanged: (val) async {
              if (val == null) return;
              final id = val.split(' — ')[0];
              setState(() {
                _lpSelectedProduct = id;
                _lpSelectedProductName = _products.firstWhere(
                  (p) => p['product_id'] == id, orElse: () => {})['product_name']?.toString();
              });
              if (_lpParentRoll1Data != null) {
                final product = _products.firstWhere((p) => p['product_id'] == id, orElse: () => {});
                final pMt = product['material_type']?.toString() ?? '';
                final rMt = _lpParentRoll1Data!['material_type']?.toString() ?? '';
                final pBw = product['basis_weight']?.toString() ?? '';
                final rBw = _lpParentRoll1Data!['basis_weight']?.toString() ?? '';
                final pW = double.tryParse(product['width']?.toString() ?? '') ?? 0;
                final rW = double.tryParse(_lpParentRoll1Data!['width']?.toString() ?? '') ?? 0;
                if (rMt.isNotEmpty && pMt.isNotEmpty && pMt != rMt) {
                  _showMessage('Material type mismatch: Parent roll is $rMt but selected product is $pMt. Please select a $rMt product.', false);
                  setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; }); return;
                }
                if (rBw.isNotEmpty && pBw.isNotEmpty && pBw != rBw) {
                  _showMessage('Basis weight mismatch: Parent roll is $rBw lbs but product requires $pBw lbs. Please select a matching product.', false);
                  setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; }); return;
                }
                if (rW > 0 && pW > 0 && pW > rW) {
                  _showMessage('Width mismatch: Product width ${pW}" exceeds parent roll width ${rW}". Child roll cannot be wider than the parent roll.', false);
                  setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; }); return;
                }
                if (rW > 0 && pW > 0 && pW < rW) {
                  final ok = await _confirmNarrowerWidth(context, rW, pW, id);
                  if (!ok) {
                    setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; });
                    return;
                  }
                }
              }
              if (mounted && _lpSelectedProduct != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _lpQtyFocus.requestFocus();
                });
              }
            },
          ),
          ),
          const SizedBox(height: 12),
          _buildTextField('Number of Labels *', _lpQtyController,
              focusNode: _lpQtyFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _lpPrintFocus.requestFocus()),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: Focus(
                focusNode: _lpPrintFocus,
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
      controller: _rpScrollController,
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
          _buildTextField('Parent Roll ID 1 *', _rpParent1,
              focusNode: _rpParent1Focus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) async {
                await _validateRpParent1();
                if (!mounted) return;
                if (_rpTwoParent) {
                  _rpParent2Focus.requestFocus();
                } else {
                  _rpScanFocus.requestFocus();
                }
              }),
          if (_rpParentRoll1Data != null)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text(
                'Material: ${_rpParentRoll1Data!['material_type'] ?? '-'}  |  Basis Weight: ${_rpParentRoll1Data!['basis_weight'] ?? '-'} lbs  |  Width: ${_rpParentRoll1Data!['width'] ?? '-'}"',
                style: TextStyle(fontSize: 13, color: Colors.green[800]),
              ),
            ),
          if (_rpTwoParent) ...[
            const SizedBox(height: 12),
            _buildTextField('Parent Roll ID 2 *', _rpParent2,
                focusNode: _rpParent2Focus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) async {
                  await _validateRpParent2();
                  if (!mounted) return;
                  _rpScanFocus.requestFocus();
                }),
            if (_rpParentRoll2Data != null)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Text(
                  'Material: ${_rpParentRoll2Data!['material_type'] ?? '-'}  |  Basis Weight: ${_rpParentRoll2Data!['basis_weight'] ?? '-'} lbs  |  Width: ${_rpParentRoll2Data!['width'] ?? '-'}"',
                  style: TextStyle(fontSize: 13, color: Colors.green[800]),
                ),
              ),
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
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
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
          _buildTextField('Notes (optional)', _rpNotesController,
              focusNode: _rpNotesFocus, multiline: true),
          const SizedBox(height: 20),
          Focus(
            focusNode: _rpSubmitFocus,
            child: SizedBox(
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
      {bool numeric = false, bool autofocus = false, Function(String)? onSubmitted,
       FocusNode? focusNode, TextInputType? keyboardType,
       TextInputAction? textInputAction, bool multiline = false}) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: multiline
          ? TextInputType.multiline
          : (keyboardType ?? (numeric ? TextInputType.number : TextInputType.text)),
      textInputAction: multiline
          ? TextInputAction.newline
          : textInputAction,
      maxLines: multiline ? 3 : 1,
      minLines: multiline ? 1 : null,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      ),
      onSubmitted: onSubmitted,
    );
  }
}
