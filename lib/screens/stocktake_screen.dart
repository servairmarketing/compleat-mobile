import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/printer_service.dart';
import '../services/form_state_cache.dart';
import '../services/roll_status.dart';
import '../services/field_focus.dart';
import '../services/parent_validation.dart';
import '../widgets/two_parent_scan_fields.dart';
import '../widgets/save_print_clear_bar.dart';
import '../widgets/load_error_card.dart';
import 'login_screen.dart';
import 'validation_dialog.dart';
import '../brand.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});
  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

enum _StMode { initial, printLabels }
enum _StSub { parent, child }

class _StocktakeScreenState extends State<StocktakeScreen> {
  _StMode? _mode;
  _StSub? _sub;

  // Shared masters (loaded once on screen init)
  List<Map> _vendors = [];
  List<Map> _products = [];
  List<String> _materialTypes = [];
  List<String> _basisWeights = [];
  List<String> _widths = [];
  bool _loadingMasters = false;

  // Bug #14 — in-memory cache key for the mode/sub-mode selection.
  static const _cacheKey = 'stocktake';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore the mode/sub-mode the operator was last in.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _mode = snap['mode'];
      _sub = snap['sub'];
    }
    _loadMasters();
  }

  @override
  void dispose() {
    // Bug #14 — preserve mode/sub-mode across nav-away (in-memory only).
    FormStateCache.write(_cacheKey, {'mode': _mode, 'sub': _sub});
    super.dispose();
  }

  Future<void> _loadMasters() async {
    setState(() => _loadingMasters = true);
    try {
      final vRes = await ApiService.get('/masters/vendors');
      final pRes = await ApiService.get('/masters/products');
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
        _vendors = List<Map>.from(vRes['records']);
      } else {
        final c = await LocalDb.getCachedMasters('vendors');
        if (c != null) _vendors = List<Map>.from(jsonDecode(c));
      }
      if (pRes['records'] != null) {
        await LocalDb.cacheMasters('products', jsonEncode(pRes['records']));
        _products = List<Map>.from(pRes['records']);
      } else {
        final c = await LocalDb.getCachedMasters('products');
        if (c != null) _products = List<Map>.from(jsonDecode(c));
      }
      if (wRes['values'] != null) {
        await LocalDb.cacheMasters('widths', jsonEncode(wRes['values']));
        _widths = List<String>.from(wRes['values']);
      } else {
        final c = await LocalDb.getCachedMasters('widths');
        if (c != null) _widths = List<String>.from(jsonDecode(c));
      }
      if (mRes['values'] != null) {
        await LocalDb.cacheMasters('material_types', jsonEncode(mRes['values']));
        _materialTypes = List<String>.from(mRes['values']);
      } else {
        final c = await LocalDb.getCachedMasters('material_types');
        if (c != null) _materialTypes = List<String>.from(jsonDecode(c));
      }
      if (bRes['values'] != null) {
        await LocalDb.cacheMasters('basis_weights', jsonEncode(bRes['values']));
        _basisWeights = List<String>.from(bRes['values']);
      } else {
        final c = await LocalDb.getCachedMasters('basis_weights');
        if (c != null) _basisWeights = List<String>.from(jsonDecode(c));
      }
    } catch (_) {}
    setState(() => _loadingMasters = false);
  }

  String _modeTitle() {
    if (_mode == null) return 'Stock Take';
    final m = switch (_mode!) {
      _StMode.initial => 'Initial Stock Entry',
      _StMode.printLabels => 'Print Labels',
    };
    if (_sub == null) return m;
    final s = _sub == _StSub.parent ? 'Parent' : 'Child';
    return '$m — $s';
  }

  void _back() {
    setState(() {
      if (_sub != null) {
        _sub = null;
      } else if (_mode != null) {
        _mode = null;
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_sub != null || _mode != null) { _back(); return false; }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF00897B),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          title: Text(_modeTitle(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        body: _loadingMasters
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == null) return _buildModePicker();
    if (_sub == null) return _buildSubPicker();
    if (_mode == _StMode.initial && _sub == _StSub.parent) {
      return _InitialParentForm(
        vendors: _vendors,
        materialTypes: _materialTypes,
        basisWeights: _basisWeights,
        widths: _widths,
      );
    }
    if (_mode == _StMode.initial && _sub == _StSub.child) {
      return _InitialChildForm(products: _products);
    }
    if (_mode == _StMode.printLabels && _sub == _StSub.parent) {
      return const _PrintParentForm();
    }
    return _PrintChildForm(products: _products);
  }

  Widget _buildModePicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Choose stock take mode',
              style: TextStyle(color: Colors.black54, fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          _ModeCard(
            key: const Key('initialEntryMode'),
            icon: Icons.add_box_rounded,
            color: kBrandColor,
            label: 'Initial Stock Entry',
            description: 'Add existing inventory to system. Writes to inventory.',
            onTap: () => setState(() => _mode = _StMode.initial),
          ),
          _ModeCard(
            key: const Key('annualStocktakeMode'),
            icon: Icons.fact_check_rounded,
            color: const Color(0xFF00897B),
            label: 'Annual Count (Batches)',
            description: 'Scan into a named batch. Save & exit, resume, or join others.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StocktakeBatchListScreen(
                  vendors: _vendors,
                  products: _products,
                  materialTypes: _materialTypes,
                  basisWeights: _basisWeights,
                  widths: _widths,
                ),
              ),
            ),
          ),
          _ModeCard(
            key: const Key('printLabelsMode'),
            icon: Icons.print_rounded,
            color: const Color(0xFFef6c00),
            label: 'Print Labels',
            description: 'Print parent or child labels. No inventory action.',
            onTap: () => setState(() => _mode = _StMode.printLabels),
          ),
        ],
      ),
    );
  }

  Widget _buildSubPicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Choose roll type',
              style: TextStyle(color: Colors.black54, fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          _ModeCard(
            key: const Key('parentSubMode'),
            icon: Icons.inventory_2_rounded,
            color: kBrandColor,
            label: 'Parent Roll',
            description: 'Operate on parent rolls',
            onTap: () => setState(() => _sub = _StSub.parent),
          ),
          _ModeCard(
            key: const Key('childSubMode'),
            icon: Icons.account_tree_rounded,
            color: const Color(0xFF0f9d58),
            label: 'Child Roll',
            description: 'Operate on child rolls',
            onTap: () => setState(() => _sub = _StSub.child),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;
  const _ModeCard({super.key, required this.icon, required this.label,
      required this.description, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.black87,
                        fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(description, style: const TextStyle(
                        color: Colors.black54, fontSize: 14)),
                  ],
                )),
                const Icon(Icons.chevron_right, color: Colors.black26, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared form helpers ────────────────────────────────────────────
Widget _stField(String label, TextEditingController controller,
    {bool autofocus = false, String? hint,
     FocusNode? focusNode, bool multiline = false,
     TextInputType? keyboardType, TextInputAction? textInputAction,
     Function(String)? onSubmitted, Function(String)? onChanged,
     List<TextInputFormatter>? inputFormatters,
     String? errorText, Key? widgetKey}) {
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
    inputFormatters: inputFormatters,
    maxLines: multiline ? 3 : 1,
    minLines: multiline ? 1 : null,
    onSubmitted: onSubmitted,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 18),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    ),
  );
}

Widget _stSimpleDropdown({
  required BuildContext context,
  required String label,
  required List<String> items,
  required String? value,
  required Function(String?) onChanged,
  bool enabled = true,
  Key? widgetKey,
}) {
  return Builder(builder: (ctx) => DropdownSearch<String>(
    key: widgetKey,
    // Bug #30 — scroll the field up so the popup opens below it.
    onBeforePopupOpening: (_) => FieldFocus.ensureRoomForDropdown(ctx),
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
      // DROPDOWN UX RULE — cap at 40% of screen height so the popup never
      // covers previously-entered form fields (see PROJECT_SPEC.md).
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
      itemBuilder: (context, item, isSelected) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(item, style: TextStyle(
          fontSize: 16,
          color: isSelected ? kBrandColor : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    ),
    onChanged: (v) {
      FocusManager.instance.primaryFocus?.unfocus();
      onChanged(v);
    },
  ));
}

// ─── Bug #20 — operator-selectable initial status ───────────────────
// Initial Stock Entry lets the operator record already-consumed legacy
// inventory by choosing its status. Annual stock-take modes never set
// status (they reconcile physical scans), so they don't use this.
// Labels come from the shared rollStatusLabels map (services/roll_status.dart).

Widget _stStatusDropdown({
  required BuildContext context,
  required List<String> allowedValues,
  required String value,
  required Function(String) onChanged,
}) {
  return _stSimpleDropdown(
    context: context,
    widgetKey: const Key('stocktakeStatusDropdown'),
    label: 'Status *',
    items: [for (final v in allowedValues) rollStatusLabel(v)],
    value: rollStatusLabel(value),
    onChanged: (label) {
      if (label == null) return;
      for (final v in allowedValues) {
        if (rollStatusLabel(v) == label) { onChanged(v); return; }
      }
    },
  );
}

// Three message states: success (green), error (red), and a non-blocking
// [warning] (amber). `warning` is used when a save succeeded but the optional
// print step failed — the save must NOT read as a red error.
Widget _stMessage(String? message, bool success, {bool warning = false}) {
  if (message == null) return const SizedBox.shrink();
  final Color bg, border, fg;
  if (warning) {
    bg = Colors.amber[100]!; border = Colors.amber[700]!; fg = Colors.amber[900]!;
  } else if (success) {
    bg = Colors.green[100]!; border = Colors.green; fg = Colors.green[800]!;
  } else {
    bg = Colors.red[100]!; border = Colors.red; fg = Colors.red[800]!;
  }
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning
              ? Icons.info_outline
              : (success ? Icons.check_circle_outline : Icons.error_outline),
          color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(
            color: fg, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

// ─── Mode 1a: Initial Parent Stock Entry ────────────────────────────
class _InitialParentForm extends StatefulWidget {
  final List<Map> vendors;
  final List<String> materialTypes;
  final List<String> basisWeights;
  final List<String> widths;
  const _InitialParentForm({
    required this.vendors, required this.materialTypes,
    required this.basisWeights, required this.widths,
  });
  @override
  State<_InitialParentForm> createState() => _InitialParentFormState();
}

class _InitialParentFormState extends State<_InitialParentForm> {
  final _rollIdCtrl = TextEditingController();
  final _poCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _rollIdFocus = FocusNode();

  String? _vendor, _materialType, _basisWeight, _width;
  // Bug #20 — operator-chosen initial status (legacy inventory entry).
  String _status = 'in_stock';
  bool _submitting = false;
  bool _printing = false;
  String? _message;
  bool _ok = false;
  bool _warn = false;
  // §2.3 — anchors the inline banner so a validation error is scrolled into
  // view rather than left off-screen above the operator's scroll position.
  final GlobalKey _bannerKey = GlobalKey();

  // Decoupled print: the roll id saved by the last successful Save. Non-null
  // means the Print Label button is enabled and prints THIS roll. Cleared by
  // the Clear button so a stale label can't be printed for a new entry.
  String? _printTarget;

  // Bug #6 — inline duplicate Roll ID check.
  String? _rollIdError;
  String _lastCheckedRollId = '';

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_initial_parent';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _rollIdCtrl.text = snap['rollId'] ?? '';
      _poCtrl.text = snap['po'] ?? '';
      _lengthCtrl.text = snap['length'] ?? '';
      _weightCtrl.text = snap['weight'] ?? '';
      _notesCtrl.text = snap['notes'] ?? '';
      _vendor = snap['vendor'];
      _materialType = snap['materialType'];
      _basisWeight = snap['basisWeight'];
      _width = snap['width'];
      _status = snap['status'] ?? 'in_stock';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocus.requestFocus();
    });
    _rollIdFocus.addListener(() {
      if (!_rollIdFocus.hasFocus) {
        _checkRollIdDuplicate(_rollIdCtrl.text.trim());
      }
    });
  }

  Future<void> _checkRollIdDuplicate(String rollId) async {
    rollId = ParentValidation.normalizeRollId(rollId);
    if (rollId.isEmpty) {
      if (_rollIdError != null) setState(() => _rollIdError = null);
      _lastCheckedRollId = '';
      return;
    }
    if (rollId == _lastCheckedRollId) return;
    _lastCheckedRollId = rollId;
    final res = await ApiService.get('/rolls/$rollId');
    if (!mounted) return;
    if (res['roll'] != null) {
      if (_rollIdCtrl.text.trim() == rollId) {
        setState(() => _rollIdError =
            'Roll ID already exists. Please scan a different roll or correct the value.');
        // Bug #10 — keep focus ON the Roll ID field when a duplicate is
        // detected so the operator can immediately edit or re-scan.
        _rollIdFocus.requestFocus();
      }
    } else {
      if (_rollIdCtrl.text.trim() == rollId) {
        setState(() => _rollIdError = null);
      }
    }
  }

  void _onRollIdChanged(String value) {
    if (_rollIdError != null) {
      setState(() => _rollIdError = null);
    }
    _lastCheckedRollId = '';
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'rollId': _rollIdCtrl.text,
      'po': _poCtrl.text,
      'length': _lengthCtrl.text,
      'weight': _weightCtrl.text,
      'notes': _notesCtrl.text,
      'vendor': _vendor,
      'materialType': _materialType,
      'basisWeight': _basisWeight,
      'width': _width,
      'status': _status,
    });
    _rollIdCtrl.dispose(); _poCtrl.dispose();
    _lengthCtrl.dispose(); _weightCtrl.dispose();
    _notesCtrl.dispose(); _rollIdFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rollId = ParentValidation.normalizeRollId(_rollIdCtrl.text);
    final issues = <String>[];
    if (rollId.isEmpty) issues.add('Roll ID is required');
    if (_rollIdError != null) issues.add('Roll ID already exists — please correct before submitting');
    if (_vendor == null) issues.add('Vendor is required');
    if (_materialType == null) issues.add('Material Type is required');
    if (_basisWeight == null) issues.add('Basis Weight is required');
    if (_width == null) issues.add('Width is required');
    if (_lengthCtrl.text.trim().isEmpty) {
      issues.add('Length is required');
    } else if (double.tryParse(_lengthCtrl.text.trim()) == null) {
      issues.add('Length must be a number');
    }
    if (_weightCtrl.text.trim().isEmpty) {
      issues.add('Weight is required');
    } else if (double.tryParse(_weightCtrl.text.trim()) == null) {
      issues.add('Weight must be a number');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }
    setState(() => _submitting = true);
    final res = await ApiService.post('/stocktake/parent', {
      'roll_id': rollId,
      'vendor_id': _vendor,
      'po_number': _poCtrl.text.trim(),
      'material_type': _materialType,
      'basis_weight': _basisWeight,
      'width': double.tryParse(_width ?? '') ?? 0,
      'length': double.tryParse(_lengthCtrl.text) ?? 0,
      'weight': double.tryParse(_weightCtrl.text) ?? 0,
      'status': _status,
      'notes': _notesCtrl.text.trim(),
    });
    if (res['success'] == true) {
      // Save only — printing is now a separate, optional action. Clear the
      // entry fields for the next roll but retain the print target so the
      // operator can still print this roll's label.
      final id = (res['roll_id'] ?? rollId).toString();
      _clear();
      setState(() {
        _printTarget = id;
        _message = 'Roll $id added to stock. Tap "Print Label" to print, or continue.';
        _ok = true; _warn = false;
      });
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _ok = false; _warn = false; });
      FieldFocus.revealBanner(_bannerKey); // §2.3 — scroll backend error into view.
    }
    setState(() => _submitting = false);
  }

  // Optional, independent print step. A print failure is shown as a
  // non-blocking note (amber) — it never undoes or masks the successful save.
  Future<void> _print() async {
    final id = _printTarget;
    if (id == null) return;
    setState(() => _printing = true);
    final detail = await PrinterService.printParentOnlyLabel(parentId: id);
    setState(() => _printing = false);
    final friendly = PrinterService.friendlyPrintError(detail);
    if (friendly == null) {
      setState(() { _message = 'Label for roll $id sent to printer.'; _ok = true; _warn = false; });
    } else {
      setState(() { _message = 'Roll $id is saved. $friendly'; _ok = false; _warn = true; });
      FieldFocus.revealBanner(_bannerKey); // §2.3 — scroll print-failure note into view.
    }
  }

  // Clears the entry fields only (used after a successful save). Leaves the
  // print target and message untouched.
  void _clear() {
    _rollIdCtrl.clear(); _poCtrl.clear();
    _lengthCtrl.clear(); _weightCtrl.clear(); _notesCtrl.clear();
    setState(() {
      _vendor = null; _materialType = null;
      _basisWeight = null; _width = null;
      _rollIdError = null;
      _status = 'in_stock';
    });
    _lastCheckedRollId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocus.requestFocus();
    });
  }

  // Clear button: reset the form AND drop the print target + message so the
  // screen is fully ready for the next entry.
  void _clearAll() {
    _clear();
    setState(() { _printTarget = null; _message = null; _warn = false; });
  }

  @override
  Widget build(BuildContext context) {
    final vendorItems = widget.vendors.map((v) => '${v['vendor_id']} — ${v['vendor_name']}').toList();
    final selectedVendor = _vendor != null
        ? (widget.vendors.where((v) => v['vendor_id']?.toString() == _vendor).isNotEmpty
            ? '$_vendor — ${widget.vendors.firstWhere((v) => v['vendor_id']?.toString() == _vendor)['vendor_name']}'
            : null)
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
                key: _bannerKey,
                child: _stMessage(_message, _ok, warning: _warn)),
            _stField('Roll ID *', _rollIdCtrl, focusNode: _rollIdFocus,
                widgetKey: const Key('stocktakeRollIdField'),
                hint: 'Operator-entered, must be unique',
                inputFormatters: const [UpperCaseRollIdFormatter()],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: _onRollIdChanged,
                errorText: _rollIdError,
                onSubmitted: (val) => _checkRollIdDuplicate(val.trim())),
            const SizedBox(height: 14),
            Builder(builder: (ctx) => DropdownSearch<String>(
              key: const Key('stocktakeVendorDropdown'),
              // Bug #30 — scroll the field up so the popup opens below it.
              onBeforePopupOpening: (_) => FieldFocus.ensureRoomForDropdown(ctx),
              items: vendorItems,
              selectedItem: selectedVendor,
              dropdownDecoratorProps: const DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Vendor *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                ),
              ),
              popupProps: PopupProps.menu(
                showSearchBox: true,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              ),
              onChanged: (val) {
                FocusManager.instance.primaryFocus?.unfocus();
                if (val == null) { setState(() => _vendor = null); return; }
                setState(() => _vendor = val.split(' — ')[0]);
              },
            )),
            const SizedBox(height: 14),
            _stField('PO Number', _poCtrl,
                widgetKey: const Key('stocktakePoNumberField'),
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _stSimpleDropdown(
              context: context,
              widgetKey: const Key('stocktakeMaterialTypeDropdown'),
              label: 'Material Type *',
              items: widget.materialTypes,
              value: _materialType,
              enabled: _basisWeight != 'Crepe' || _materialType == 'Crepe',
              onChanged: (v) {
                setState(() {
                  _materialType = v;
                  if (v == 'Crepe') _basisWeight = 'Crepe';
                  else if (_basisWeight == 'Crepe') _basisWeight = null;
                });
              },
            ),
            const SizedBox(height: 14),
            _stSimpleDropdown(
              context: context,
              widgetKey: const Key('stocktakeBasisWeightDropdown'),
              label: 'Basis Weight *',
              items: widget.basisWeights,
              value: _basisWeight,
              enabled: _materialType != 'Crepe' || _basisWeight == 'Crepe',
              onChanged: (v) {
                setState(() {
                  _basisWeight = v;
                  if (v == 'Crepe') _materialType = 'Crepe';
                  else if (_materialType == 'Crepe') _materialType = null;
                });
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _stSimpleDropdown(
                  context: context,
                  widgetKey: const Key('stocktakeWidthDropdown'),
                  label: 'Width (in) *',
                  items: widget.widths,
                  value: _width,
                  onChanged: (v) => setState(() => _width = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stField('Length (ft) *', _lengthCtrl,
                    widgetKey: const Key('stocktakeLengthField'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next),
              ),
            ]),
            const SizedBox(height: 14),
            _stField('Weight (lbs) *', _weightCtrl,
                widgetKey: const Key('stocktakeWeightField'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done),
            const SizedBox(height: 14),
            _stStatusDropdown(
              context: context,
              allowedValues: const ['in_stock', 'in_production', 'consumed'],
              value: _status,
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 14),
            _stField('Notes', _notesCtrl, multiline: true),
            const SizedBox(height: 24),
            SavePrintClearBar(
              saveButtonKey: const Key('stocktakeSubmitButton'),
              onSave: (_submitting || _rollIdError != null) ? null : _submit,
              saving: _submitting,
              saveLabel: 'Add to Stock',
              saveIcon: Icons.add_box,
              onPrint: _print,
              printing: _printing,
              canPrint: _printTarget != null,
              printLabel: 'Print Label',
              onClear: _clearAll,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mode 1b: Initial Child Stock Entry ─────────────────────────────
class _InitialChildForm extends StatefulWidget {
  final List<Map> products;
  const _InitialChildForm({required this.products});
  @override
  State<_InitialChildForm> createState() => _InitialChildFormState();
}

class _InitialChildFormState extends State<_InitialChildForm> {
  final _parent1Ctrl = TextEditingController();
  final _parent2Ctrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _parent1Focus = FocusNode();

  bool _twoParent = false;
  String? _productId, _productName;
  // Bug #20 — operator-chosen initial status (legacy inventory entry).
  String _status = 'in_stock';
  bool _submitting = false;
  bool _printing = false;
  String? _message;
  bool _ok = false;
  bool _warn = false;
  // §2.3 — anchors the inline banner so a validation error is scrolled into
  // view rather than left off-screen above the operator's scroll position.
  final GlobalKey _bannerKey = GlobalKey();

  // Decoupled print: snapshot of the last successfully-saved child entry so
  // its labels can be (re)printed independently. Non-null => Print enabled.
  List<String>? _printParents;
  String? _printProductId, _printProductName;
  int _printQty = 0;

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_initial_child';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _parent1Ctrl.text = snap['parent1'] ?? '';
      _parent2Ctrl.text = snap['parent2'] ?? '';
      _qtyCtrl.text = snap['qty'] ?? '';
      _lengthCtrl.text = snap['length'] ?? '';
      _weightCtrl.text = snap['weight'] ?? '';
      _notesCtrl.text = snap['notes'] ?? '';
      _twoParent = snap['twoParent'] ?? false;
      _productId = snap['productId'];
      _productName = snap['productName'];
      _status = snap['status'] ?? 'in_stock';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _parent1Focus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'parent1': _parent1Ctrl.text,
      'parent2': _parent2Ctrl.text,
      'qty': _qtyCtrl.text,
      'length': _lengthCtrl.text,
      'weight': _weightCtrl.text,
      'notes': _notesCtrl.text,
      'twoParent': _twoParent,
      'productId': _productId,
      'productName': _productName,
      'status': _status,
    });
    _parent1Ctrl.dispose(); _parent2Ctrl.dispose();
    _qtyCtrl.dispose(); _lengthCtrl.dispose();
    _weightCtrl.dispose(); _notesCtrl.dispose();
    _parent1Focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p1 = ParentValidation.normalizeRollId(_parent1Ctrl.text);
    final p2 = ParentValidation.normalizeRollId(_parent2Ctrl.text);
    final issues = <String>[];
    if (p1.isEmpty) issues.add('Parent Roll ID is required');
    if (_twoParent && p2.isEmpty) issues.add('Second Parent Roll ID is required');
    if (_productId == null) issues.add('Product is required');
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (_qtyCtrl.text.trim().isEmpty) {
      issues.add('Quantity is required');
    } else if (qty < 1) {
      issues.add('Quantity must be 1 or more');
    }
    if (_lengthCtrl.text.trim().isEmpty) {
      issues.add('Length is required');
    } else if (double.tryParse(_lengthCtrl.text.trim()) == null) {
      issues.add('Length must be a number');
    }
    if (_weightCtrl.text.trim().isEmpty) {
      issues.add('Weight is required');
    } else if (double.tryParse(_weightCtrl.text.trim()) == null) {
      issues.add('Weight must be a number');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }
    setState(() => _submitting = true);
    final parents = _twoParent ? [p1, p2] : [p1];
    // §2.13 — shared two-parent / splice validation. Stock-take child uses
    // requireExist:false: an UNKNOWN parent is allowed (old/leftover stock whose
    // parent is long gone). R1 (the two parents must differ) is ALWAYS enforced;
    // R3 (material/basis match) only fires when both parents resolve.
    final pv = await ParentValidation.validateParentSet(parents,
        requireExist: false);
    if (!pv.ok) {
      setState(() {
        _submitting = false;
        _message = pv.error;
        _ok = false;
        _warn = false;
      });
      // §2.3 — the operator is scrolled down at Submit; bring the error up.
      FieldFocus.revealBanner(_bannerKey);
      return;
    }
    final res = await ApiService.post('/stocktake/child', {
      'parent_roll_ids': parents,
      'product_id': _productId,
      'quantity': qty,
      'length': double.tryParse(_lengthCtrl.text) ?? 0,
      'weight': double.tryParse(_weightCtrl.text) ?? 0,
      'status': _status,
      'notes': _notesCtrl.text.trim(),
    });
    if (res['success'] == true) {
      // Save only — snapshot what to print, then clear the fields for the
      // next entry while keeping the Print Labels button available.
      final printParents = List<String>.from(parents);
      final pid = _productId!;
      final pname = _productName ?? _productId!;
      final pqty = qty;
      _clear();
      final total = pqty * printParents.length;
      setState(() {
        _printParents = printParents;
        _printProductId = pid;
        _printProductName = pname;
        _printQty = pqty;
        _message = 'Child roll added to stock. Tap "Print Labels" to print '
            '$total label(s), or continue.';
        _ok = true; _warn = false;
      });
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _ok = false; _warn = false; });
      FieldFocus.revealBanner(_bannerKey); // §2.3 — scroll backend error into view.
    }
    setState(() => _submitting = false);
  }

  // Optional, independent print step for the last saved child entry. A print
  // failure is a non-blocking note — the save is already done.
  Future<void> _print() async {
    final parents = _printParents;
    final pid = _printProductId;
    if (parents == null || pid == null || _printQty < 1) return;
    setState(() => _printing = true);
    String? errorDetail;
    outer:
    for (final p in parents) {
      for (var i = 0; i < _printQty; i++) {
        final detail = await PrinterService.printLabel(
          productId: pid,
          productName: _printProductName ?? pid,
          parentRollId1: p,
          parentRollId2: null,
          quantity: 1,
        );
        if (detail.startsWith('ERROR')) { errorDetail = detail; break outer; }
      }
    }
    setState(() => _printing = false);
    if (errorDetail == null) {
      final total = _printQty * parents.length;
      setState(() { _message = '$total label(s) sent to printer.'; _ok = true; _warn = false; });
    } else {
      final friendly = PrinterService.friendlyPrintError(errorDetail)!;
      setState(() { _message = 'Child roll is saved. $friendly'; _ok = false; _warn = true; });
      FieldFocus.revealBanner(_bannerKey); // §2.3 — scroll print-failure note into view.
    }
  }

  // Clears entry fields only (used after a successful save).
  void _clear() {
    _parent1Ctrl.clear(); _parent2Ctrl.clear();
    _qtyCtrl.clear(); _lengthCtrl.clear();
    _weightCtrl.clear(); _notesCtrl.clear();
    setState(() {
      _productId = null; _productName = null;
      _status = 'in_stock';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _parent1Focus.requestFocus();
    });
  }

  // Clear button: reset the form AND drop the print target + message.
  void _clearAll() {
    _clear();
    setState(() {
      _printParents = null; _printProductId = null; _printProductName = null;
      _printQty = 0; _message = null; _warn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final productItems = widget.products
        .map((p) => '${p['product_id']} — ${p['product_name'] ?? ''}')
        .toList();
    final selectedProduct = _productId != null
        ? productItems.firstWhere(
            (s) => s.startsWith('$_productId —'),
            orElse: () => '')
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
                key: _bannerKey,
                child: _stMessage(_message, _ok, warning: _warn)),
            Row(children: [
              const Text('Two-Parent Roll',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                key: const Key('stocktakeTwoParentToggle'),
                value: _twoParent,
                // Bug #22 — after the mode flip, focus the first input
                // field (Parent Roll ID 1).
                onChanged: (v) {
                  setState(() => _twoParent = v);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _parent1Focus.requestFocus();
                  });
                },
              ),
            ]),
            const SizedBox(height: 8),
            _stField('Parent Roll ID 1 *', _parent1Ctrl, focusNode: _parent1Focus,
                widgetKey: const Key('stocktakeParent1Field'),
                inputFormatters: const [UpperCaseRollIdFormatter()],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next),
            if (_twoParent) ...[
              const SizedBox(height: 14),
              _stField('Parent Roll ID 2 *', _parent2Ctrl,
                  widgetKey: const Key('stocktakeParent2Field'),
                  inputFormatters: const [UpperCaseRollIdFormatter()],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next),
            ],
            const SizedBox(height: 14),
            Builder(builder: (ctx) => DropdownSearch<String>(
              key: const Key('stocktakeProductDropdown'),
              // Bug #30 — scroll the field up so the popup opens below it.
              onBeforePopupOpening: (_) => FieldFocus.ensureRoomForDropdown(ctx),
              items: productItems,
              selectedItem: (selectedProduct?.isEmpty ?? true) ? null : selectedProduct,
              dropdownDecoratorProps: const DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Product *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                ),
              ),
              popupProps: PopupProps.menu(
                showSearchBox: true,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              ),
              onChanged: (val) {
                FocusManager.instance.primaryFocus?.unfocus();
                if (val == null) {
                  setState(() { _productId = null; _productName = null; });
                  return;
                }
                final parts = val.split(' — ');
                setState(() {
                  _productId = parts[0];
                  _productName = parts.length > 1 ? parts[1] : parts[0];
                });
              },
            )),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _stField('Quantity *', _qtyCtrl,
                    widgetKey: const Key('stocktakeQtyField'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stField('Length (ft) *', _lengthCtrl,
                    widgetKey: const Key('stocktakeLengthField'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next),
              ),
            ]),
            const SizedBox(height: 14),
            _stField('Weight (lbs) *', _weightCtrl,
                widgetKey: const Key('stocktakeWeightField'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done),
            const SizedBox(height: 14),
            _stStatusDropdown(
              context: context,
              allowedValues: const ['in_stock', 'in_production', 'converted', 'sold'],
              value: _status,
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 14),
            _stField('Notes', _notesCtrl, multiline: true),
            const SizedBox(height: 24),
            SavePrintClearBar(
              saveButtonKey: const Key('stocktakeSubmitButton'),
              onSave: _submitting ? null : _submit,
              saving: _submitting,
              saveLabel: 'Add to Stock',
              saveIcon: Icons.add_box,
              onPrint: _print,
              printing: _printing,
              canPrint: _printParents != null,
              printLabel: 'Print Labels',
              onClear: _clearAll,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mode 3a: Print Parent Label ────────────────────────────────────
class _PrintParentForm extends StatefulWidget {
  const _PrintParentForm();
  @override
  State<_PrintParentForm> createState() => _PrintParentFormState();
}

class _PrintParentFormState extends State<_PrintParentForm> {
  final _rollIdCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rollIdFocus = FocusNode();
  bool _printing = false;
  String? _message;
  bool _ok = false;

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_print_parent';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _rollIdCtrl.text = snap['rollId'] ?? '';
      _qtyCtrl.text = snap['qty'] ?? '1';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'rollId': _rollIdCtrl.text,
      'qty': _qtyCtrl.text,
    });
    _rollIdCtrl.dispose(); _qtyCtrl.dispose();
    _rollIdFocus.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    final rollId = _rollIdCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (rollId.isEmpty || qty < 1) {
      setState(() { _message = 'Roll ID and Quantity are required.'; _ok = false; }); return;
    }
    setState(() => _printing = true);
    final detail = await PrinterService.printParentOnlyLabel(parentId: rollId, quantity: qty);
    setState(() => _printing = false);
    final friendly = PrinterService.friendlyPrintError(detail);
    if (friendly != null) {
      setState(() { _message = friendly; _ok = false; });
    } else {
      setState(() { _message = '$qty label(s) sent to printer!'; _ok = true; });
      _rollIdCtrl.clear();
      _rollIdFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stMessage(_message, _ok),
            _stField('Roll ID *', _rollIdCtrl, focusNode: _rollIdFocus,
                widgetKey: const Key('stocktakeRollIdField'),
                inputFormatters: const [UpperCaseRollIdFormatter()],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next),
            const SizedBox(height: 14),
            _stField('Quantity *', _qtyCtrl,
                widgetKey: const Key('stocktakeQtyField'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                key: const Key('stocktakeSubmitButton'),
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print, size: 24),
                label: Text(_printing ? 'Printing...' : 'Print Parent Label(s)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFef6c00),
                  foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mode 3b: Print Child Label (composite) ─────────────────────────
class _PrintChildForm extends StatefulWidget {
  final List<Map> products;
  const _PrintChildForm({required this.products});
  @override
  State<_PrintChildForm> createState() => _PrintChildFormState();
}

class _PrintChildFormState extends State<_PrintChildForm> {
  final _parent1Ctrl = TextEditingController();
  final _parent2Ctrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _parent1Focus = FocusNode();
  bool _twoParent = false;
  String? _productId, _productName;
  bool _printing = false;
  String? _message;
  bool _ok = false;

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_print_child';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _parent1Ctrl.text = snap['parent1'] ?? '';
      _parent2Ctrl.text = snap['parent2'] ?? '';
      _qtyCtrl.text = snap['qty'] ?? '1';
      _twoParent = snap['twoParent'] ?? false;
      _productId = snap['productId'];
      _productName = snap['productName'];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _parent1Focus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'parent1': _parent1Ctrl.text,
      'parent2': _parent2Ctrl.text,
      'qty': _qtyCtrl.text,
      'twoParent': _twoParent,
      'productId': _productId,
      'productName': _productName,
    });
    _parent1Ctrl.dispose(); _parent2Ctrl.dispose();
    _qtyCtrl.dispose(); _parent1Focus.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    final p1 = _parent1Ctrl.text.trim();
    final p2 = _parent2Ctrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (p1.isEmpty || _productId == null || qty < 1) {
      setState(() { _message = 'Parent Roll ID, Product and Quantity are required.'; _ok = false; }); return;
    }
    if (_twoParent && p2.isEmpty) {
      setState(() { _message = 'Second Parent Roll ID is required.'; _ok = false; }); return;
    }
    setState(() => _printing = true);
    final parents = (_twoParent && p2.isNotEmpty) ? [p1, p2] : [p1];
    String? errorDetail;
    outer:
    for (final pid in parents) {
      for (var i = 0; i < qty; i++) {
        final detail = await PrinterService.printLabel(
          productId: _productId!,
          productName: _productName ?? _productId!,
          parentRollId1: pid,
          parentRollId2: null,
          quantity: 1,
        );
        if (detail.startsWith('ERROR')) { errorDetail = detail; break outer; }
      }
    }
    setState(() => _printing = false);
    if (errorDetail == null) {
      final total = qty * parents.length;
      setState(() { _message = '$total label(s) sent to printer!'; _ok = true; });
    } else {
      setState(() { _message = PrinterService.friendlyPrintError(errorDetail!)!; _ok = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final productItems = widget.products
        .map((p) => '${p['product_id']} — ${p['product_name'] ?? ''}')
        .toList();
    final selectedProduct = _productId != null
        ? productItems.firstWhere(
            (s) => s.startsWith('$_productId —'),
            orElse: () => '')
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stMessage(_message, _ok),
            Row(children: [
              const Text('Two-Parent Roll',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                key: const Key('stocktakeTwoParentToggle'),
                value: _twoParent,
                // Bug #22 — after the mode flip, focus the first input
                // field (Parent Roll ID 1).
                onChanged: (v) {
                  setState(() => _twoParent = v);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _parent1Focus.requestFocus();
                  });
                },
              ),
            ]),
            const SizedBox(height: 8),
            _stField('Parent Roll ID 1 *', _parent1Ctrl, focusNode: _parent1Focus,
                widgetKey: const Key('stocktakeParent1Field'),
                inputFormatters: const [UpperCaseRollIdFormatter()],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next),
            if (_twoParent) ...[
              const SizedBox(height: 14),
              _stField('Parent Roll ID 2 *', _parent2Ctrl,
                  widgetKey: const Key('stocktakeParent2Field'),
                  inputFormatters: const [UpperCaseRollIdFormatter()],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next),
            ],
            const SizedBox(height: 14),
            Builder(builder: (ctx) => DropdownSearch<String>(
              key: const Key('stocktakeProductDropdown'),
              // Bug #30 — scroll the field up so the popup opens below it.
              onBeforePopupOpening: (_) => FieldFocus.ensureRoomForDropdown(ctx),
              items: productItems,
              selectedItem: (selectedProduct?.isEmpty ?? true) ? null : selectedProduct,
              dropdownDecoratorProps: const DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Product *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                ),
              ),
              popupProps: PopupProps.menu(
                showSearchBox: true,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              ),
              onChanged: (val) {
                FocusManager.instance.primaryFocus?.unfocus();
                if (val == null) {
                  setState(() { _productId = null; _productName = null; });
                  return;
                }
                final parts = val.split(' — ');
                setState(() {
                  _productId = parts[0];
                  _productName = parts.length > 1 ? parts[1] : parts[0];
                });
              },
            )),
            const SizedBox(height: 14),
            _stField('Quantity *', _qtyCtrl,
                widgetKey: const Key('stocktakeQtyField'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                key: const Key('stocktakeSubmitButton'),
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print, size: 24),
                label: Text(_printing ? 'Printing...' : 'Print Child Label(s)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFef6c00),
                  foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Annual Count — Batch System (Stage 1-4 backend, /api/stocktake/*)
//  Replaces the old free-scan Annual flow. The handheld lets a user create
//  or join a named batch and scan into it (save/exit + resume). Freeze and
//  reconciliation are web-only. Scan resolution is POST-first: the backend
//  decides known-vs-unknown (status-agnostic); a "not found in system"
//  response opens the inline Initial Stock Entry form, which resubmits as
//  the unknown path with an initial_entry payload (backend creates the roll
//  AND records the scan in one call). Core actions are gated server-side by
//  stocktake_batch:execute; corrections (edit/delete) are web-only.
// ═══════════════════════════════════════════════════════════════════════

class StocktakeBatchListScreen extends StatefulWidget {
  final List<Map> vendors;
  final List<Map> products;
  final List<String> materialTypes;
  final List<String> basisWeights;
  final List<String> widths;
  const StocktakeBatchListScreen({
    super.key,
    required this.vendors,
    required this.products,
    required this.materialTypes,
    required this.basisWeights,
    required this.widths,
  });
  @override
  State<StocktakeBatchListScreen> createState() => _StocktakeBatchListScreenState();
}

class _StocktakeBatchListScreenState extends State<StocktakeBatchListScreen> {
  bool _loading = true;
  String? _error;
  List<Map> _open = [];
  List<Map> _paused = [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.get('/api/stocktake/batches');
    if (res['error'] == 'session_expired') {
      if (mounted) Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    if (res['batches'] is List) {
      final list = List<Map>.from(res['batches']);
      list.sort((a, b) => (b['created_at'] ?? '').toString()
          .compareTo((a['created_at'] ?? '').toString()));
      _open = list.where((b) => b['state'] == 'open').toList();
      _paused = list.where((b) => b['state'] == 'paused').toList();
      setState(() { _loading = false; _error = null; });
    } else {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? res['detail'] ?? 'Could not load batches.').toString();
      });
    }
  }

  Future<void> _newBatch() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Stock Take Batch'),
        content: TextField(
          key: const Key('batchNameField'),
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Batch name *',
            hintText: 'e.g. Aisle 3, North dock',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _creating = true);
    final res = await ApiService.post('/api/stocktake/batches', {'name': name.trim()});
    setState(() => _creating = false);
    if (res['success'] == true && res['batch'] != null) {
      _openScan(Map<String, dynamic>.from(res['batch']));
    } else {
      _showError(res, 'create a batch');
    }
  }

  Future<void> _join(Map b) async {
    final res = await ApiService.post(
        '/api/stocktake/batches/${b['batch_id']}/join', {});
    if (res['success'] == true) {
      _openScan(Map<String, dynamic>.from(res['batch'] ?? b));
    } else {
      _showError(res, 'join this batch');
    }
  }

  void _showError(Map res, String what) {
    final d = (res['detail'] ?? '').toString();
    final msg = RegExp('permission denied', caseSensitive: false).hasMatch(d)
        ? "You don't have permission to $what."
        : (d.isNotEmpty ? d : 'Could not $what.');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[700]));
    }
  }

  Future<void> _openScan(Map<String, dynamic> batch) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => StocktakeBatchScanScreen(
        batch: batch,
        vendors: widget.vendors,
        products: widget.products,
        materialTypes: widget.materialTypes,
        basisWeights: widget.basisWeights,
        widths: widget.widths,
      ),
    ));
    _load(); // refresh state/counts on return
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Annual Count — Batches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newBatchButton'),
        backgroundColor: const Color(0xFF00897B),
        onPressed: _creating ? null : _newBatch,
        icon: _creating
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
        label: const Text('New Batch'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  if (_error != null)
                    LoadErrorCard(message: _error!, onRetry: _load),  // §2.16 — Retry, not a dead message
                  _sectionHeader('Open — tap to join', _open.length),
                  if (_open.isEmpty) _emptyNote('No open batches. Tap "New Batch" to start one.'),
                  ..._open.map((b) => _batchCard(b, resume: false)),
                  const SizedBox(height: 18),
                  _sectionHeader('Paused — tap to resume', _paused.length),
                  if (_paused.isEmpty) _emptyNote('No paused batches.'),
                  ..._paused.map((b) => _batchCard(b, resume: true)),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String label, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text('$label  ($count)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: Colors.black54)),
      );

  Widget _emptyNote(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      );

  Widget _batchCard(Map b, {required bool resume}) {
    final participants = (b['participants'] is Map) ? (b['participants'] as Map).length : 0;
    final count = b['scan_count'] ?? 0;
    final color = resume ? const Color(0xFFb36c00) : const Color(0xFF00897B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: InkWell(
          onTap: () => _join(b),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(resume ? Icons.play_arrow_rounded : Icons.login_rounded,
                      color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((b['name'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 3),
                    Text('$count scans · $participants ${participants == 1 ? 'person' : 'people'}'
                        ' · ${b['created_by_name'] ?? '—'}',
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                )),
                Icon(resume ? Icons.chevron_right : Icons.chevron_right,
                    color: Colors.black26, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Batch-scoped scanning ──────────────────────────────────────────────
class StocktakeBatchScanScreen extends StatefulWidget {
  final Map batch;
  final List<Map> vendors;
  final List<Map> products;
  final List<String> materialTypes;
  final List<String> basisWeights;
  final List<String> widths;
  const StocktakeBatchScanScreen({
    super.key,
    required this.batch,
    required this.vendors,
    required this.products,
    required this.materialTypes,
    required this.basisWeights,
    required this.widths,
  });
  @override
  State<StocktakeBatchScanScreen> createState() => _StocktakeBatchScanScreenState();
}

class _StocktakeBatchScanScreenState extends State<StocktakeBatchScanScreen> {
  late String _batchId;
  late String _batchName;
  int _count = 0;

  _StSub _sub = _StSub.parent;
  bool _twoParent = false;
  bool _busy = false;
  bool _exiting = false;
  String? _message;
  bool _ok = false;
  bool _warn = false;

  final List<Map> _recent = [];
  // Issue 3 (TC22) — true while the batch's already-recorded scans are loading
  // on entry/resume (the recent list shows the whole batch, not just this run).
  bool _loadingScans = true;

  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();

  // Inline Initial Stock Entry — PARENT (shown when a parent is not in system)
  bool _showParentForm = false;
  String _pendingRollId = '';
  final _poCtrl = TextEditingController();
  final _pLengthCtrl = TextEditingController();
  final _pWeightCtrl = TextEditingController();
  final _pNotesCtrl = TextEditingController();
  String? _vendor, _materialType, _basisWeight, _width;

  // Inline Initial Stock Entry — CHILD (product + parents come from the scan)
  bool _showChildForm = false;
  String _pendingChildProduct = '';
  List<String> _pendingChildParents = [];
  final _cQtyCtrl = TextEditingController();
  final _cLengthCtrl = TextEditingController();
  final _cWeightCtrl = TextEditingController();
  final _cNotesCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _batchId = (widget.batch['batch_id'] ?? '').toString();
    _batchName = (widget.batch['name'] ?? 'Batch').toString();
    _count = (widget.batch['scan_count'] is int) ? widget.batch['scan_count'] : 0;
    _loadExistingScans(); // Issue 3 — show what's already been counted in this batch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  // Issue 3 (TC22) — pull the batch's existing scans so a resumed/joined batch
  // shows what's already counted (newest first) and the header count reflects the
  // true total, not just this session's adds. Backend already sorts newest-first.
  Future<void> _loadExistingScans() async {
    final res = await ApiService.get('/api/stocktake/batches/$_batchId/scans');
    if (res['error'] == 'session_expired') { _toLogin(); return; }
    if (!mounted) return;
    if (res['scans'] is List) {
      final list = List<Map>.from(res['scans']);
      setState(() {
        _recent
          ..clear()
          ..addAll(list.map((s) => {
                'type': s['type'],
                'label': _labelForScan(s),
                'isNew': s['was_already_in_system'] == false,
                'dup': s['duplicate_in_batch'] == true,
                'at': DateTime.tryParse((s['scanned_at'] ?? '').toString())?.toLocal()
                    ?? DateTime.now(),
              }));
        if (res['count'] is int) _count = res['count'];
        _loadingScans = false;
      });
    } else {
      setState(() => _loadingScans = false);
    }
  }

  // Display label for a loaded scan, matching the in-session format: parent → its
  // roll_id; child → "ProductID / parent1 + parent2".
  String _labelForScan(Map s) {
    if (s['type'] == 'child') {
      final pid = (s['product_id'] ?? '').toString();
      final parents = (s['parent_roll_ids'] is List)
          ? (s['parent_roll_ids'] as List).join(' + ')
          : '';
      return '$pid / $parents';
    }
    return (s['roll_id'] ?? '').toString();
  }

  @override
  void dispose() {
    _scanCtrl.dispose(); _scanFocus.dispose();
    _poCtrl.dispose(); _pLengthCtrl.dispose(); _pWeightCtrl.dispose(); _pNotesCtrl.dispose();
    _cQtyCtrl.dispose(); _cLengthCtrl.dispose(); _cWeightCtrl.dispose(); _cNotesCtrl.dispose();
    super.dispose();
  }

  void _toLogin() {
    if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<Map<String, dynamic>> _postScan(Map<String, dynamic> body) =>
      ApiService.post('/api/stocktake/batches/$_batchId/scans', body);

  bool _isNotFound(Map res) =>
      (res['detail'] ?? '').toString().toLowerCase().contains('not found in system');

  void _afterRecorded(Map res, String type, String label) {
    final dup = res['duplicate_in_batch'] == true;
    final wasNew = res['was_already_in_system'] == false;
    setState(() {
      _count += 1;
      _recent.insert(0, {
        'type': type, 'label': label, 'isNew': wasNew, 'dup': dup,
        'at': DateTime.now(),
      });
      _busy = false;
      _ok = true;
      _warn = dup;
      _message = dup
          ? '⚠ Counted again — $label was already scanned in this batch.'
          : (wasNew ? '✓ Added & counted $label' : '✓ Recorded $label');
    });
  }

  // Issue 2 (TC22) — under the Parent toggle, reject a value that is really a
  // child/product instead of recording it as a bogus parent. Detection (all on
  // the §2.14-normalized value) covers the two child forms the operator can scan:
  //   (a) a composite "ProductID-ParentID"  → ParentValidation.parseComposite
  //        returns non-null (product IDs carry a hyphen, parent roll IDs don't);
  //   (b) a bare product ID (e.g. BVR-696000) → matches the loaded product master.
  // Anything that is NEITHER a known product NOR a composite is a genuine parent
  // roll ID and proceeds normally. Reuses parseComposite + the product master
  // already loaded in StocktakeScreen (no new lookup, no duplicated parsing).
  bool _looksLikeChildUnderParent(String normalizedId) {
    if (ParentValidation.parseComposite(normalizedId) != null) return true;
    return widget.products.any((p) =>
        ParentValidation.normalizeProductId(p['product_id']?.toString()) == normalizedId);
  }

  // ── Parent scan (POST-first) ──
  Future<void> _onScanParent(String value) async {
    final rollId = ParentValidation.normalizeRollId(value);
    if (rollId.isEmpty) return;
    if (_looksLikeChildUnderParent(rollId)) {
      setState(() {
        _busy = false; _ok = false; _warn = false;
        _message = '$rollId looks like a child/product, not a parent roll '
            '— switch to Child mode to scan it.';
      });
      _scanCtrl.clear();
      _scanFocus.requestFocus();
      return;
    }
    setState(() { _busy = true; _message = null; });
    final res = await _postScan(
        {'type': 'parent', 'roll_id': rollId, 'was_already_in_system': true});
    if (res['detail'] == 'session_expired') { _toLogin(); return; }
    if (res['success'] == true) {
      _afterRecorded(res, 'parent', rollId);
      _scanCtrl.clear();
      _scanFocus.requestFocus();
    } else if (_isNotFound(res)) {
      setState(() {
        _busy = false; _showParentForm = true; _pendingRollId = rollId;
        _ok = false; _warn = false;
        _message = 'Roll $rollId is not in the system — add its details to count it.';
      });
      _scanCtrl.clear();
    } else {
      setState(() {
        _busy = false; _ok = false; _warn = false;
        _message = (res['detail'] ?? 'Scan failed.').toString();
      });
    }
  }

  Future<void> _submitParentForm() async {
    if (_vendor == null || _materialType == null || _basisWeight == null || _width == null) {
      setState(() { _message = 'Vendor, Material Type, Basis Weight and Width are required.'; _ok = false; _warn = false; });
      return;
    }
    if (_pLengthCtrl.text.trim().isEmpty || _pWeightCtrl.text.trim().isEmpty) {
      setState(() { _message = 'Length and Weight are required.'; _ok = false; _warn = false; });
      return;
    }
    setState(() => _submitting = true);
    final res = await _postScan({
      'type': 'parent',
      'roll_id': _pendingRollId,
      'was_already_in_system': false,
      'initial_entry': {
        'roll_id': _pendingRollId,
        'vendor_id': _vendor,
        'po_number': _poCtrl.text.trim(),
        'material_type': _materialType,
        'basis_weight': _basisWeight,
        'width': double.tryParse(_width ?? '') ?? 0,
        'length': double.tryParse(_pLengthCtrl.text) ?? 0,
        'weight': double.tryParse(_pWeightCtrl.text) ?? 0,
        'notes': _pNotesCtrl.text.trim(),
      },
    });
    setState(() => _submitting = false);
    if (res['detail'] == 'session_expired') { _toLogin(); return; }
    if (res['success'] == true) {
      final id = _pendingRollId;
      setState(() {
        _showParentForm = false; _pendingRollId = '';
        _poCtrl.clear(); _pLengthCtrl.clear(); _pWeightCtrl.clear(); _pNotesCtrl.clear();
        _vendor = null; _materialType = null; _basisWeight = null; _width = null;
      });
      _afterRecorded(res, 'parent', id);
      _scanFocus.requestFocus();
    } else {
      setState(() { _message = (res['detail'] ?? 'Submit failed.').toString(); _ok = false; _warn = false; });
    }
  }

  // ── Child scan (POST-first) ──
  Future<void> _onScanChild(String value) async {
    final parsed = ParentValidation.parseComposite(value);
    if (parsed == null) {
      setState(() { _message = 'Invalid composite — expected "ProductID-ParentID".'; _ok = false; _warn = false; });
      _scanCtrl.clear();
      return;
    }
    await _recordChild(parsed.productId, [parsed.parentId]);
  }

  Future<void> _onTwoParentPair(String scan1, String scan2) async {
    final p1 = ParentValidation.parseComposite(scan1);
    final p2 = ParentValidation.parseComposite(scan2);
    if (p1 == null || p2 == null) {
      setState(() { _message = 'Invalid composite — expected "ProductID-ParentID".'; _ok = false; _warn = false; });
      return;
    }
    if (p1.productId != p2.productId) {
      setState(() { _message = 'Product ID mismatch between the two labels — both must be the same product.'; _ok = false; _warn = false; });
      return;
    }
    if (p1.parentId == p2.parentId) {
      setState(() { _message = 'Both labels are from the same parent. Scan one label per parent.'; _ok = false; _warn = false; });
      return;
    }
    await _recordChild(p1.productId, [p1.parentId, p2.parentId], fromTwoParent: true);
  }

  Future<void> _recordChild(String productId, List<String> parents,
      {bool fromTwoParent = false}) async {
    productId = ParentValidation.normalizeProductId(productId);
    parents = parents.map(ParentValidation.normalizeRollId).toList();
    setState(() { _busy = true; _message = null; });
    final label = '$productId / ${parents.join(' + ')}';
    final res = await _postScan({
      'type': 'child', 'product_id': productId,
      'parent_roll_ids': parents, 'was_already_in_system': true,
    });
    if (res['detail'] == 'session_expired') { _toLogin(); return; }
    if (res['success'] == true) {
      _afterRecorded(res, 'child', label);
      _scanCtrl.clear();
      if (!fromTwoParent) _scanFocus.requestFocus();
    } else if (_isNotFound(res)) {
      setState(() {
        _busy = false; _showChildForm = true;
        _pendingChildProduct = productId; _pendingChildParents = parents;
        _ok = false; _warn = false;
        _message = 'Child $productId is not in the system — add its details to count it.';
      });
      _scanCtrl.clear();
    } else {
      setState(() {
        _busy = false; _ok = false; _warn = false;
        _message = (res['detail'] ?? 'Scan failed.').toString();
      });
    }
  }

  Future<void> _submitChildForm() async {
    final qty = int.tryParse(_cQtyCtrl.text.trim()) ?? 0;
    if (qty < 1) {
      setState(() { _message = 'Quantity must be 1 or more.'; _ok = false; _warn = false; });
      return;
    }
    if (_cLengthCtrl.text.trim().isEmpty || _cWeightCtrl.text.trim().isEmpty) {
      setState(() { _message = 'Length and Weight are required.'; _ok = false; _warn = false; });
      return;
    }
    setState(() => _submitting = true);
    final res = await _postScan({
      'type': 'child',
      'product_id': _pendingChildProduct,
      'parent_roll_ids': _pendingChildParents,
      'was_already_in_system': false,
      'initial_entry': {
        'parent_roll_ids': _pendingChildParents,
        'product_id': _pendingChildProduct,
        'quantity': qty,
        'length': double.tryParse(_cLengthCtrl.text) ?? 0,
        'weight': double.tryParse(_cWeightCtrl.text) ?? 0,
        'notes': _cNotesCtrl.text.trim(),
      },
    });
    setState(() => _submitting = false);
    if (res['detail'] == 'session_expired') { _toLogin(); return; }
    if (res['success'] == true) {
      final label = '$_pendingChildProduct / ${_pendingChildParents.join(' + ')}';
      setState(() {
        _showChildForm = false; _pendingChildProduct = ''; _pendingChildParents = [];
        _cQtyCtrl.clear(); _cLengthCtrl.clear(); _cWeightCtrl.clear(); _cNotesCtrl.clear();
      });
      _afterRecorded(res, 'child', label);
      _scanFocus.requestFocus();
    } else {
      setState(() { _message = (res['detail'] ?? 'Submit failed.').toString(); _ok = false; _warn = false; });
    }
  }

  // ── Save & exit (pause) ──
  Future<void> _saveExit() async {
    setState(() => _exiting = true);
    await ApiService.post('/api/stocktake/batches/$_batchId/pause', {});
    if (mounted) Navigator.pop(context);
  }

  bool get _inInlineForm => _showParentForm || _showChildForm;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showParentForm) { setState(() { _showParentForm = false; _message = null; }); return false; }
        if (_showChildForm) { setState(() { _showChildForm = false; _message = null; }); return false; }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF00897B),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_batchName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text('$_count scans', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            if (!_inInlineForm)
              TextButton.icon(
                key: const Key('saveExitButton'),
                onPressed: _exiting ? null : _saveExit,
                icon: _exiting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_alt, color: Colors.white, size: 20),
                label: const Text('Save & exit', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: _showParentForm
            ? _buildParentInline()
            : _showChildForm
                ? _buildChildInline()
                : _buildScan(),
      ),
    );
  }

  Widget _buildScan() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stMessage(_message, _ok, warning: _warn),
          // Parent | Child toggle
          Row(children: [
            Expanded(child: _segBtn('Parent', _sub == _StSub.parent, () {
              setState(() { _sub = _StSub.parent; _twoParent = false; _message = null; });
              _scanFocus.requestFocus();
            })),
            const SizedBox(width: 10),
            Expanded(child: _segBtn('Child', _sub == _StSub.child, () {
              setState(() { _sub = _StSub.child; _message = null; });
              _scanFocus.requestFocus();
            })),
          ]),
          const SizedBox(height: 16),
          if (_sub == _StSub.child) Row(children: [
            const Text('Two-Parent Roll',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            Switch(
              key: const Key('batchTwoParentToggle'),
              value: _twoParent,
              onChanged: (v) => setState(() => _twoParent = v),
            ),
          ]),
          Text(
            _sub == _StSub.parent
                ? 'Scan the Parent Roll ID barcode.'
                : (_twoParent
                    ? 'Scan BOTH composite labels (one per parent) for each child roll.'
                    : 'Scan the composite barcode (ProductID-ParentID).'),
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (_sub == _StSub.child && _twoParent)
            TwoParentScanFields(
              key: const Key('batchChildTwoParentScan'),
              firstFieldFocusNode: _scanFocus,
              enabled: !_busy,
              onPair: _onTwoParentPair,
            )
          else
            TextField(
              key: const Key('batchScanField'),
              controller: _scanCtrl,
              focusNode: _scanFocus,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              inputFormatters: const [UpperCaseRollIdFormatter()],
              onSubmitted: _sub == _StSub.parent ? _onScanParent : _onScanChild,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: _sub == _StSub.parent ? 'Parent Roll ID' : 'Composite Barcode',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
              ),
            ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 18),
          _recentList(),
        ],
      ),
    );
  }

  Widget _segBtn(String label, bool active, VoidCallback onTap) {
    return SizedBox(
      height: 46,
      child: active
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white),
              child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          : OutlinedButton(
              onPressed: onTap,
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
    );
  }

  Widget _recentList() {
    if (_loadingScans && _recent.isEmpty) {
      return Row(children: [
        const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Loading scans…', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ]);
    }
    if (_recent.isEmpty) {
      return Text('No scans in this batch yet.',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]));
    }
    final shown = _recent.take(40).toList();
    final header = _recent.length > shown.length
        ? 'Recent scans (this batch) — showing latest ${shown.length} of ${_recent.length}'
        : 'Recent scans (this batch)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(header,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 6),
        ...shown.map((s) {
          final isChild = s['type'] == 'child';
          final isNew = s['isNew'] == true;
          final dup = s['dup'] == true;
          final at = s['at'] as DateTime;
          final hh = at.hour.toString().padLeft(2, '0');
          final mm = at.minute.toString().padLeft(2, '0');
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: isChild ? const Color(0xFFf3e5f5) : const Color(0xFFe0f2f1),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(isChild ? 'CHILD' : 'PARENT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                        color: isChild ? const Color(0xFF6a1b9a) : const Color(0xFF00695c))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text((s['label'] ?? '').toString(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
              if (dup) const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('dup', style: TextStyle(fontSize: 11, color: Color(0xFFb36c00), fontWeight: FontWeight.bold)),
              ),
              if (isNew) const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('NEW', style: TextStyle(fontSize: 11, color: Color(0xFF9a6700), fontWeight: FontWeight.bold)),
              ),
              Text('$hh:$mm', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ]),
          );
        }),
      ],
    );
  }

  // ── Inline PARENT entry (reuses the masters dropdowns) ──
  Widget _buildParentInline() {
    final vendorItems = widget.vendors.map((v) => '${v['vendor_id']} — ${v['vendor_name']}').toList();
    final selectedVendor = _vendor != null
        ? (widget.vendors.where((v) => v['vendor_id']?.toString() == _vendor).isNotEmpty
            ? '$_vendor — ${widget.vendors.firstWhere((v) => v['vendor_id']?.toString() == _vendor)['vendor_name']}'
            : null)
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stMessage(_message, _ok, warning: _warn),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Text('New parent: $_pendingRollId',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 14),
            Builder(builder: (ctx) => DropdownSearch<String>(
              onBeforePopupOpening: (_) => FieldFocus.ensureRoomForDropdown(ctx),
              items: vendorItems,
              selectedItem: selectedVendor,
              dropdownDecoratorProps: const DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Vendor *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                ),
              ),
              popupProps: PopupProps.menu(
                showSearchBox: true,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              ),
              onChanged: (val) {
                FocusManager.instance.primaryFocus?.unfocus();
                if (val == null) { setState(() => _vendor = null); return; }
                setState(() => _vendor = val.split(' — ')[0]);
              },
            )),
            const SizedBox(height: 14),
            _stField('PO Number', _poCtrl),
            const SizedBox(height: 14),
            _stSimpleDropdown(
              context: context,
              label: 'Material Type *',
              items: widget.materialTypes,
              value: _materialType,
              enabled: _basisWeight != 'Crepe' || _materialType == 'Crepe',
              onChanged: (v) {
                setState(() {
                  _materialType = v;
                  if (v == 'Crepe') _basisWeight = 'Crepe';
                  else if (_basisWeight == 'Crepe') _basisWeight = null;
                });
              },
            ),
            const SizedBox(height: 14),
            _stSimpleDropdown(
              context: context,
              label: 'Basis Weight *',
              items: widget.basisWeights,
              value: _basisWeight,
              enabled: _materialType != 'Crepe' || _basisWeight == 'Crepe',
              onChanged: (v) {
                setState(() {
                  _basisWeight = v;
                  if (v == 'Crepe') _materialType = 'Crepe';
                  else if (_materialType == 'Crepe') _materialType = null;
                });
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _stSimpleDropdown(
                context: context,
                label: 'Width (in) *',
                items: widget.widths,
                value: _width,
                onChanged: (v) => setState(() => _width = v),
              )),
              const SizedBox(width: 12),
              Expanded(child: _stField('Length (ft) *', _pLengthCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next)),
            ]),
            const SizedBox(height: 14),
            _stField('Weight (lbs) *', _pWeightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done),
            const SizedBox(height: 14),
            _stField('Notes', _pNotesCtrl, multiline: true),
            const SizedBox(height: 24),
            _inlineButtons(_submitParentForm, () => setState(() {
              _showParentForm = false; _pendingRollId = ''; _message = null;
            })),
          ],
        ),
      ),
    );
  }

  // ── Inline CHILD entry (product + parents come from the scan) ──
  Widget _buildChildInline() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stMessage(_message, _ok, warning: _warn),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product: $_pendingChildProduct',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Parents: ${_pendingChildParents.join(' + ')}',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _stField('Quantity *', _cQtyCtrl,
                  keyboardType: TextInputType.number, textInputAction: TextInputAction.next)),
              const SizedBox(width: 12),
              Expanded(child: _stField('Length (ft) *', _cLengthCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next)),
            ]),
            const SizedBox(height: 14),
            _stField('Weight (lbs) *', _cWeightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done),
            const SizedBox(height: 14),
            _stField('Notes', _cNotesCtrl, multiline: true),
            const SizedBox(height: 24),
            _inlineButtons(_submitChildForm, () => setState(() {
              _showChildForm = false; _pendingChildProduct = ''; _pendingChildParents = []; _message = null;
            })),
          ],
        ),
      ),
    );
  }

  Widget _inlineButtons(Future<void> Function() onSave, VoidCallback onCancel) {
    return Row(children: [
      Expanded(child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          key: const Key('batchInlineSubmit'),
          onPressed: _submitting ? null : () => onSave(),
          icon: _submitting
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: Text(_submitting ? 'Saving...' : 'Save & Count',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B), foregroundColor: Colors.white),
        ),
      )),
      const SizedBox(width: 12),
      SizedBox(
        height: 56,
        child: OutlinedButton(
          onPressed: _submitting ? null : onCancel,
          child: const Text('Cancel', style: TextStyle(fontSize: 18)),
        ),
      ),
    ]);
  }
}
