import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/printer_service.dart';
import 'validation_dialog.dart';

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
  // Two-parent pairing state: when in two-parent mode, label 1 sits in these
  // fields until label 2 arrives and the pair is committed.
  String? _rpFirstScanProduct;
  String? _rpFirstScanParent;
  // Batch-mode lock: null = no scans yet; true = batch locked to two-parent;
  // false = batch locked to single-parent. Set on the first commit / first
  // pending label-1 scan so subsequent scans in a different toggle state are
  // blocked (the batch can't mix single-parent and splice rolls in one doc).
  bool? _rpBatchMode;
  // Per-parent status. "In Stock" is no longer selectable on Roll Production
  // — a parent that's been used in production has been at least partially
  // consumed, so it can never logically remain in_stock.
  String _selectedStatus1 = '';
  String _selectedStatus2 = '';
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
    final w1 = double.tryParse(_lpParentRoll1Data!['width']?.toString() ?? '') ?? 0.0;
    final w2 = (_lpTwoParent && _lpParentRoll2Data != null)
        ? (double.tryParse(_lpParentRoll2Data!['width']?.toString() ?? '') ?? 0.0)
        : 0.0;
    final parentWs = <double>[w1, w2].where((w) => w > 0).toList();
    final minParentW = parentWs.isEmpty ? 0.0 : parentWs.reduce((a, b) => a < b ? a : b);
    return _products.where((p) {
      final pMt = p['material_type']?.toString() ?? '';
      final pBw = p['basis_weight']?.toString() ?? '';
      final pW = double.tryParse(p['width']?.toString() ?? '') ?? 0.0;
      if (parentMt.isNotEmpty && pMt != parentMt) return false;
      if (parentBw.isNotEmpty && pBw != parentBw) return false;
      if (minParentW > 0 && pW > minParentW) return false;
      return true;
    }).toList();
  }

  Future<bool> _confirmNarrowerWidth(
      BuildContext context, List<double> parentWs, double prodW, String productId,
      {bool isScan = false}) async {
    final parentClause = parentWs.length >= 2
        ? 'parent roll widths are ${parentWs[0]}" and ${parentWs[1]}"'
        : 'parent roll width is ${parentWs.isNotEmpty ? parentWs[0] : 0}"';
    final body = isScan
        ? 'Scanned product $productId width is ${prodW}" but $parentClause. Are you sure you want to add this child roll?'
        : 'Selected product width is ${prodW}" but $parentClause. Are you sure you want to create a child roll of smaller width?';
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

  Future<bool> _validateLpParent1() async {
    final id = _lpParent1.text.trim();
    if (id.isEmpty) { setState(() => _lpParentRoll1Data = null); return false; }
    setState(() => _lpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _lpValidatingParent = false);
    if (data == null) {
      _lpParent1.clear();
      setState(() => _lpParentRoll1Data = null);
      _showMessage('Parent Roll ID 1 not found. Please check the ID and try again.', false);
      return false;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      _lpParent1.clear();
      setState(() => _lpParentRoll1Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false);
      return false;
    }
    setState(() {
      _lpParentRoll1Data = data;
      // Clear product selection when parent roll changes
      _lpSelectedProduct = null;
      _lpSelectedProductName = null;
    });
    return true;
  }

  Future<bool> _validateLpParent2() async {
    final id = _lpParent2.text.trim();
    if (id.isEmpty) { setState(() => _lpParentRoll2Data = null); return false; }
    if (_lpParentRoll1Data == null) {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Please validate Parent Roll ID 1 first.', false);
      return false;
    }
    if (id == _lpParent1.text.trim()) {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Parent Roll 2 cannot be the same as Parent Roll 1.', false);
      return false;
    }
    setState(() => _lpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _lpValidatingParent = false);
    if (data == null) {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Parent Roll ID 2 not found. Please check the ID and try again.', false);
      return false;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false);
      return false;
    }
    // Cross-validate against Roll 1 (material + basis weight only — width is independent)
    final mt1 = _lpParentRoll1Data!['material_type']?.toString() ?? '';
    final mt2 = data['material_type']?.toString() ?? '';
    if (mt1.isNotEmpty && mt2.isNotEmpty && mt1 != mt2) {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Material type mismatch: Roll 1 is $mt1 but Roll 2 is $mt2. Both parent rolls must be the same material type.', false);
      return false;
    }
    final bw1 = _lpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final bw2 = data['basis_weight']?.toString() ?? '';
    if (bw1.isNotEmpty && bw2.isNotEmpty && bw1 != bw2) {
      _lpParent2.clear();
      setState(() => _lpParentRoll2Data = null);
      _showMessage('Basis weight mismatch: Roll 1 is $bw1 lbs but Roll 2 is $bw2 lbs. Both parent rolls must have the same basis weight.', false);
      return false;
    }
    setState(() {
      _lpParentRoll2Data = data;
      // Clear product selection so filter re-applies with new min width
      _lpSelectedProduct = null;
      _lpSelectedProductName = null;
    });
    return true;
  }

  Future<bool> _validateRpParent1() async {
    final id = _rpParent1.text.trim();
    if (id.isEmpty) { setState(() => _rpParentRoll1Data = null); return false; }
    setState(() => _rpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _rpValidatingParent = false);
    if (data == null) {
      _rpParent1.clear();
      setState(() => _rpParentRoll1Data = null);
      _showMessage('Parent Roll ID 1 not found. Please check the ID and try again.', false);
      return false;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      _rpParent1.clear();
      setState(() => _rpParentRoll1Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false);
      return false;
    }
    setState(() {
      _rpParentRoll1Data = data;
      // Clear scanned items + pairing state when parent roll changes — a
      // different parent means this is a new batch.
      _scannedItems = {};
      _rpFirstScanProduct = null;
      _rpFirstScanParent = null;
      _rpBatchMode = null;
    });
    return true;
  }

  Future<bool> _validateRpParent2() async {
    final id = _rpParent2.text.trim();
    if (id.isEmpty) { setState(() => _rpParentRoll2Data = null); return false; }
    if (_rpParentRoll1Data == null) {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Please validate Parent Roll ID 1 first.', false);
      return false;
    }
    if (id == _rpParent1.text.trim()) {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Parent Roll 2 cannot be the same as Parent Roll 1.', false);
      return false;
    }
    setState(() => _rpValidatingParent = true);
    final data = await _fetchParentRoll(id);
    setState(() => _rpValidatingParent = false);
    if (data == null) {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Parent Roll ID 2 not found. Please check the ID and try again.', false);
      return false;
    }
    final status = data['status']?.toString() ?? '';
    if (status == 'consumed' || status == 'finished') {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Parent Roll $id has already been fully consumed and cannot be used for production.', false);
      return false;
    }
    // Cross-validate against Roll 1 (material + basis weight only — width is independent)
    final mt1 = _rpParentRoll1Data!['material_type']?.toString() ?? '';
    final mt2 = data['material_type']?.toString() ?? '';
    if (mt1.isNotEmpty && mt2.isNotEmpty && mt1 != mt2) {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Material type mismatch: Roll 1 is $mt1 but Roll 2 is $mt2. Both parent rolls must be the same material type.', false);
      return false;
    }
    final bw1 = _rpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final bw2 = data['basis_weight']?.toString() ?? '';
    if (bw1.isNotEmpty && bw2.isNotEmpty && bw1 != bw2) {
      _rpParent2.clear();
      setState(() => _rpParentRoll2Data = null);
      _showMessage('Basis weight mismatch: Roll 1 is $bw1 lbs but Roll 2 is $bw2 lbs. Both parent rolls must have the same basis weight.', false);
      return false;
    }
    setState(() => _rpParentRoll2Data = data);
    return true;
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
    // Composite-barcode label: each label encodes "ProductID-ParentID". In
    // two-parent mode print N labels for parent 1 then N for parent 2 (2N total)
    // so each child roll receives both labels.
    final parentIds = (_lpTwoParent && p2.isNotEmpty) ? [p1, p2] : [p1];
    String? errorDetail;
    outer:
    for (final pid in parentIds) {
      for (var i = 0; i < qty; i++) {
        final detail = await PrinterService.printLabel(
          productId: _lpSelectedProduct!,
          productName: _lpSelectedProductName ?? _lpSelectedProduct!,
          parentRollId1: pid,
          parentRollId2: null,
          quantity: 1,
        );
        if (detail.startsWith('ERROR')) { errorDetail = detail; break outer; }
      }
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

  // Composite parser: split on the LAST hyphen so product IDs that contain
  // their own hyphens (e.g. "BSR-637800-T7Q5M21182A") parse correctly.
  ({String productId, String parentId})? _parseComposite(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final idx = s.lastIndexOf('-');
    if (idx <= 0 || idx >= s.length - 1) return null;
    final pid = s.substring(0, idx).trim();
    final parent = s.substring(idx + 1).trim();
    if (pid.isEmpty || parent.isEmpty) return null;
    return (productId: pid, parentId: parent);
  }

  void _commitScan(String productId, String productName) {
    setState(() {
      if (_scannedItems.containsKey(productId)) {
        _scannedItems[productId]!['count'] = (_scannedItems[productId]!['count'] as int) + 1;
      } else {
        _scannedItems[productId] = {'count': 1, 'name': productName};
      }
      _rpFirstScanProduct = null;
      _rpFirstScanParent = null;
      _rpBatchMode ??= _rpTwoParent;
    });
    _rpScanController.clear();
    HapticFeedback.lightImpact();
    if (mounted) _rpScanFocus.requestFocus();
  }

  Future<void> _processScan(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;

    void rejectAndResetPending(String msg) {
      _rpScanController.clear();
      setState(() {
        _rpFirstScanProduct = null;
        _rpFirstScanParent = null;
      });
      _showMessage(msg, false);
      if (mounted) _rpScanFocus.requestFocus();
    }
    void rejectKeepPending(String msg) {
      _rpScanController.clear();
      _showMessage(msg, false);
      if (mounted) _rpScanFocus.requestFocus();
    }

    if (_rpParentRoll1Data == null) {
      rejectAndResetPending('Please enter and confirm Parent Roll ID 1 before scanning.');
      return;
    }
    if (_rpTwoParent && _rpParentRoll2Data == null) {
      rejectAndResetPending('Please enter and confirm Parent Roll ID 2 before scanning.');
      return;
    }

    // Cross-mode prevention: once a batch is locked to a mode, all further
    // scans must use the same toggle state. Otherwise the batch can't fit in
    // one production doc.
    if (_rpBatchMode != null && _rpBatchMode != _rpTwoParent) {
      rejectAndResetPending('This batch contains both single-parent and two-parent rolls. Submit them as separate batches.');
      return;
    }

    final parsed = _parseComposite(raw);
    if (parsed == null) {
      rejectKeepPending('Invalid composite barcode. Expected Product-Parent format.');
      return;
    }
    final parsedProductId = parsed.productId;
    final parsedParentId = parsed.parentId;

    final product = _products.firstWhere(
      (p) => p['product_id']?.toString() == parsedProductId,
      orElse: () => {},
    );
    if (product.isEmpty) {
      rejectAndResetPending('Product $parsedProductId not found in product master. Please check the barcode.');
      return;
    }

    final pMt = product['material_type']?.toString() ?? '';
    final pBw = product['basis_weight']?.toString() ?? '';
    final pW = double.tryParse(product['width']?.toString() ?? '') ?? 0.0;
    final rMt = _rpParentRoll1Data!['material_type']?.toString() ?? '';
    final rBw = _rpParentRoll1Data!['basis_weight']?.toString() ?? '';
    final w1 = double.tryParse(_rpParentRoll1Data!['width']?.toString() ?? '') ?? 0.0;
    final w2 = (_rpTwoParent && _rpParentRoll2Data != null)
        ? (double.tryParse(_rpParentRoll2Data!['width']?.toString() ?? '') ?? 0.0)
        : 0.0;
    final parentWs = <double>[w1, w2].where((w) => w > 0).toList();

    if (rMt.isNotEmpty && pMt.isNotEmpty && pMt != rMt) {
      rejectAndResetPending('Material type mismatch: Parent roll is $rMt but scanned product $parsedProductId is $pMt. Scan rejected.');
      return;
    }
    if (rBw.isNotEmpty && pBw.isNotEmpty && pBw != rBw) {
      rejectAndResetPending('Basis weight mismatch: Parent roll is $rBw lbs but scanned product $parsedProductId requires $pBw lbs. Scan rejected.');
      return;
    }
    if (parentWs.isNotEmpty && pW > 0) {
      final minP = parentWs.reduce((a, b) => a < b ? a : b);
      final maxP = parentWs.reduce((a, b) => a > b ? a : b);
      if (pW > minP) {
        rejectAndResetPending('Width mismatch: Scanned product $parsedProductId width ${pW}" exceeds parent roll width ${minP}". Scan rejected.');
        return;
      }
      if (pW < maxP) {
        final ok = await _confirmNarrowerWidth(context, parentWs, pW, parsedProductId, isScan: true);
        if (!ok) {
          _rpScanController.clear();
          if (mounted) _rpScanFocus.requestFocus();
          return;
        }
      }
    }

    final p1Id = _rpParent1.text.trim();
    final p2Id = _rpParent2.text.trim();
    final productName = product['product_name']?.toString() ?? parsedProductId;

    if (!_rpTwoParent) {
      // Single-parent mode: parsed parent must equal Parent Roll 1.
      if (parsedParentId != p1Id) {
        rejectAndResetPending('Scanned label is for parent $parsedParentId but Parent Roll 1 is $p1Id.');
        return;
      }
      _commitScan(parsedProductId, productName);
      return;
    }

    // Two-parent mode.
    if (_rpFirstScanProduct == null) {
      // Label 1 of 2 — must match either parent.
      if (parsedParentId != p1Id && parsedParentId != p2Id) {
        rejectAndResetPending('Scanned label is for parent $parsedParentId but parents are $p1Id and $p2Id.');
        return;
      }
      setState(() {
        _rpFirstScanProduct = parsedProductId;
        _rpFirstScanParent = parsedParentId;
        _rpBatchMode = true;
      });
      _rpScanController.clear();
      HapticFeedback.lightImpact();
      if (mounted) _rpScanFocus.requestFocus();
      return;
    }

    // Label 2 of 2 — must be the same product, the OTHER parent.
    if (parsedProductId != _rpFirstScanProduct) {
      rejectAndResetPending('Both labels must be from the same product roll.');
      return;
    }
    if (parsedParentId == _rpFirstScanParent) {
      // Wrong parent — keep label 1 pending, ask operator to scan the other.
      rejectKeepPending('Both labels are from the same parent. Scan the second parent\'s label.');
      return;
    }
    if (parsedParentId != p1Id && parsedParentId != p2Id) {
      rejectAndResetPending('Scanned label is for parent $parsedParentId but parents are $p1Id and $p2Id.');
      return;
    }
    // Valid pair — counter +1 (one paired roll = one increment).
    _commitScan(parsedProductId, productName);
  }

  void _selectStatus(int parentSlot, String status) {
    setState(() {
      if (parentSlot == 1) {
        _selectedStatus1 = status;
      } else {
        _selectedStatus2 = status;
      }
    });
  }

  Future<void> _submitProduction() async {
    final p1 = _rpParent1.text.trim();
    final p2 = _rpParent2.text.trim();

    // Use locked batch mode if set; cross-mode prevention guarantees this
    // matches the toggle state of every committed scan.
    final batchTwoParent = _rpBatchMode ?? _rpTwoParent;

    final issues = <String>[];
    if (p1.isEmpty) issues.add('Parent Roll ID is required');
    if (batchTwoParent && p2.isEmpty) issues.add('Second Parent Roll ID is required');
    if (_scannedItems.isEmpty) issues.add('At least one child roll must be scanned');
    if (_rpFirstScanProduct != null) {
      issues.add('Finish the second scan of the pending splice roll before submitting');
    }
    // A parent used in production has been at least partially consumed — it
    // can't stay "in_stock". Force operator to pick Production or Finished
    // for each parent in scope.
    if (_selectedStatus1.isEmpty) {
      issues.add('Status for parent roll 1 must be Production or Finished');
    }
    if (batchTwoParent && _selectedStatus2.isEmpty) {
      issues.add('Status for parent roll 2 must be Production or Finished');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }

    setState(() => _submitting = true);

    final parentRollIds = batchTwoParent ? [p1, p2] : [p1];
    final parentStatuses = batchTwoParent
        ? [_selectedStatus1, _selectedStatus2]
        : [_selectedStatus1];
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
      _selectedStatus1 = '';
      _selectedStatus2 = '';
      _rpFirstScanProduct = null;
      _rpFirstScanParent = null;
      _rpBatchMode = null;
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
                Tab(key: Key('labelPrintingTab'), icon: Icon(Icons.print, size: 22), text: 'Label Printing'),
                Tab(key: Key('rollProductionTab'), icon: Icon(Icons.precision_manufacturing, size: 22), text: 'Roll Production'),
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
                final ok = await _validateLpParent1();
                if (!mounted) return;
                if (!ok) { _lpParent1Focus.requestFocus(); return; }
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
                  final ok = await _validateLpParent2();
                  if (!mounted) return;
                  if (!ok) { _lpParent2Focus.requestFocus(); return; }
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
            key: const Key('productDropdown'),
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
              void rejectAndReopen(String msg) {
                _showMessage(msg, false);
                setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; });
                _focusAndOpenLpProduct();
              }
              if (_lpParentRoll1Data != null) {
                final product = _products.firstWhere((p) => p['product_id'] == id, orElse: () => {});
                final pMt = product['material_type']?.toString() ?? '';
                final pBw = product['basis_weight']?.toString() ?? '';
                final pW = double.tryParse(product['width']?.toString() ?? '') ?? 0.0;
                final rMt = _lpParentRoll1Data!['material_type']?.toString() ?? '';
                final rBw = _lpParentRoll1Data!['basis_weight']?.toString() ?? '';
                final w1 = double.tryParse(_lpParentRoll1Data!['width']?.toString() ?? '') ?? 0.0;
                final w2 = (_lpTwoParent && _lpParentRoll2Data != null)
                    ? (double.tryParse(_lpParentRoll2Data!['width']?.toString() ?? '') ?? 0.0)
                    : 0.0;
                final parentWs = <double>[w1, w2].where((w) => w > 0).toList();
                if (rMt.isNotEmpty && pMt.isNotEmpty && pMt != rMt) {
                  rejectAndReopen('Material type mismatch: Parent roll is $rMt but selected product is $pMt. Please select a $rMt product.');
                  return;
                }
                if (rBw.isNotEmpty && pBw.isNotEmpty && pBw != rBw) {
                  rejectAndReopen('Basis weight mismatch: Parent roll is $rBw lbs but product requires $pBw lbs. Please select a matching product.');
                  return;
                }
                if (parentWs.isNotEmpty && pW > 0) {
                  final minP = parentWs.reduce((a, b) => a < b ? a : b);
                  final maxP = parentWs.reduce((a, b) => a > b ? a : b);
                  if (pW > minP) {
                    rejectAndReopen('Width mismatch: Product width ${pW}" exceeds parent roll width ${minP}". Child roll cannot be wider than any parent roll.');
                    return;
                  }
                  if (pW < maxP) {
                    final ok = await _confirmNarrowerWidth(context, parentWs, pW, id);
                    if (!ok) {
                      setState(() { _lpSelectedProduct = null; _lpSelectedProductName = null; });
                      _focusAndOpenLpProduct();
                      return;
                    }
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
              widgetKey: const Key('numLabelsField'),
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
                    key: const Key('printLabelsButton'),
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
          // Two parent toggle (per-scan: operator may flip ON/OFF between scans)
          Card(
            color: _rpTwoParent ? Colors.orange[50] : Colors.blue[50],
            child: SwitchListTile(
              key: const Key('twoParentToggle'),
              title: Text(
                _rpTwoParent ? 'Two-parent mode (splice)' : 'Single-parent mode',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _rpTwoParent
                    ? 'Each child roll requires TWO label scans (one per parent)'
                    : 'Each child roll requires ONE label scan',
              ),
              value: _rpTwoParent,
              activeColor: Colors.orange[800],
              onChanged: (v) => setState(() {
                _rpTwoParent = v;
                // Drop any pending first-scan when the mode flips so the next
                // scan starts fresh in the new mode.
                _rpFirstScanProduct = null;
                _rpFirstScanParent = null;
                // Note: do NOT clear _rpParent2 — keep parent 2 populated so
                // flipping back to two-parent mode mid-batch doesn't lose it.
              }),
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField('Parent Roll ID 1 *', _rpParent1,
              widgetKey: const Key('parent1Field'),
              focusNode: _rpParent1Focus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) async {
                final ok = await _validateRpParent1();
                if (!mounted) return;
                if (!ok) { _rpParent1Focus.requestFocus(); return; }
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
                widgetKey: const Key('parent2Field'),
                focusNode: _rpParent2Focus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) async {
                  final ok = await _validateRpParent2();
                  if (!mounted) return;
                  if (!ok) { _rpParent2Focus.requestFocus(); return; }
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

          // Mode badge (always visible) — orange in two-parent mode showing
          // which scan is expected next (and, after label 1, which parent is
          // expected for label 2).
          Builder(builder: (_) {
            final p1Id = _rpParent1.text.trim();
            final p2Id = _rpParent2.text.trim();
            final String badgeText;
            final Color badgeBg;
            final Color badgeFg;
            if (_rpTwoParent) {
              if (_rpFirstScanProduct == null) {
                badgeText = 'Two-parent mode — scan label 1 of 2';
              } else {
                final otherParent = _rpFirstScanParent == p1Id ? p2Id : p1Id;
                badgeText = 'Two-parent mode — scan label 2 of 2 (parent $otherParent)';
              }
              badgeBg = Colors.orange[100]!;
              badgeFg = Colors.orange[900]!;
            } else {
              badgeText = 'Single-parent mode — one scan = one roll';
              badgeBg = Colors.blue[100]!;
              badgeFg = Colors.blue[900]!;
            }
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badgeText,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: badgeFg)),
            );
          }),

          // Scan field — labelText/hintText reflect mode and pending state.
          Builder(builder: (_) {
            final p1Id = _rpParent1.text.trim();
            final p2Id = _rpParent2.text.trim();
            final String labelText;
            final String hintText;
            if (_rpTwoParent) {
              if (_rpFirstScanProduct == null) {
                labelText = 'Scan label 1 of 2';
                hintText = 'Scan first parent\'s composite label';
              } else {
                final otherParent = _rpFirstScanParent == p1Id ? p2Id : p1Id;
                labelText = 'Scan label 2 of 2 (parent $otherParent)';
                hintText = 'Scan composite label for parent $otherParent';
              }
            } else {
              labelText = 'Scan composite barcode';
              hintText = 'Scan here...';
            }
            return TextField(
              key: const Key('scanField'),
              controller: _rpScanController,
              focusNode: _rpScanFocus,
              autofocus: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: labelText,
                hintText: hintText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
              ),
              onSubmitted: (v) { _processScan(v); _rpScanFocus.requestFocus(); },
              onChanged: (v) {
                if (v.endsWith('\n') || v.length > 20) _processScan(v);
              },
            );
          }),
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

          // Parent roll status — Production or Finished only. A parent used
          // in production cannot remain "in_stock", so that option is gone.
          // Each parent in scope needs its own explicit selection.
          Text(
            (_rpBatchMode ?? _rpTwoParent) ? 'Parent Roll 1 Status *' : 'Parent Roll Status *',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _statusButton(1, 'production', '🟡 Production', Colors.orange[700]!),
            const SizedBox(width: 8),
            _statusButton(1, 'finished', '🔴 Finished', Colors.red[700]!),
          ]),
          if (_rpBatchMode ?? _rpTwoParent) ...[
            const SizedBox(height: 12),
            const Text('Parent Roll 2 Status *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              _statusButton(2, 'production', '🟡 Production', Colors.orange[700]!),
              const SizedBox(width: 8),
              _statusButton(2, 'finished', '🔴 Finished', Colors.red[700]!),
            ]),
          ],
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
                key: const Key('submitProductionButton'),
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

  Widget _statusButton(int parentSlot, String status, String label, Color color) {
    final current = parentSlot == 1 ? _selectedStatus1 : _selectedStatus2;
    final selected = current == status;
    return Expanded(
      child: GestureDetector(
        key: Key('parent${parentSlot}Status${status[0].toUpperCase()}${status.substring(1)}'),
        onTap: () => _selectStatus(parentSlot, status),
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
       TextInputAction? textInputAction, bool multiline = false,
       Key? widgetKey}) {
    return TextField(
      key: widgetKey,
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
