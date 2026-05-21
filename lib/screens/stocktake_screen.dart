import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/printer_service.dart';
import '../services/form_state_cache.dart';
import '../services/roll_status.dart';
import '../services/field_focus.dart';
import '../widgets/two_parent_scan_fields.dart';
import 'login_screen.dart';
import 'validation_dialog.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});
  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

enum _StMode { initial, annual, printLabels }
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
      _StMode.annual => 'Annual Stock Take',
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
    if (_mode == _StMode.annual && _sub == _StSub.parent) {
      return _AnnualParentForm(
        vendors: _vendors,
        materialTypes: _materialTypes,
        basisWeights: _basisWeights,
        widths: _widths,
      );
    }
    if (_mode == _StMode.annual && _sub == _StSub.child) {
      return _AnnualChildForm(products: _products);
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
            color: const Color(0xFF1a73e8),
            label: 'Initial Stock Entry',
            description: 'Add existing inventory to system. Writes to inventory.',
            onTap: () => setState(() => _mode = _StMode.initial),
          ),
          _ModeCard(
            key: const Key('annualStocktakeMode'),
            icon: Icons.fact_check_rounded,
            color: const Color(0xFF00897B),
            label: 'Annual Stock Take',
            description: 'Record annual count. Writes to stock-take log only.',
            onTap: () => setState(() => _mode = _StMode.annual),
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
            color: const Color(0xFF1a73e8),
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
          color: isSelected ? const Color(0xFF1a73e8) : Colors.black,
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

Widget _stMessage(String? message, bool success) {
  if (message == null) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: success ? Colors.green[100] : Colors.red[100],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: success ? Colors.green : Colors.red),
    ),
    child: Text(message, style: TextStyle(
      color: success ? Colors.green[800] : Colors.red[800],
      fontSize: 16, fontWeight: FontWeight.bold)),
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
  String? _message;
  bool _ok = false;

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
    final rollId = _rollIdCtrl.text.trim();
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
      final id = res['roll_id'] ?? rollId;
      final printDetail = await PrinterService.printParentOnlyLabel(parentId: id);
      if (printDetail.startsWith('ERROR')) {
        setState(() { _message = 'Roll $id added but printing failed: $printDetail'; _ok = false; });
      } else {
        setState(() { _message = 'Roll $id added & label printed!'; _ok = true; });
      }
      _clear();
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _ok = false; });
    }
    setState(() => _submitting = false);
  }

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
            _stMessage(_message, _ok),
            _stField('Roll ID *', _rollIdCtrl, focusNode: _rollIdFocus,
                widgetKey: const Key('stocktakeRollIdField'),
                hint: 'Operator-entered, must be unique',
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
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                key: const Key('stocktakeSubmitButton'),
                onPressed: (_submitting || _rollIdError != null) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_box, size: 24),
                label: Text(_submitting ? 'Saving...' : 'Add to Stock + Print Label',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a73e8),
                  foregroundColor: Colors.white),
              ),
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
  String? _message;
  bool _ok = false;

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
    final p1 = _parent1Ctrl.text.trim();
    final p2 = _parent2Ctrl.text.trim();
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
      if (errorDetail == null) {
        final total = qty * parents.length;
        setState(() { _message = 'Child added & $total label(s) printed!'; _ok = true; });
      } else {
        setState(() { _message = 'Child added but printing failed: $errorDetail'; _ok = false; });
      }
      _clear();
    } else {
      setState(() { _message = res['detail'] ?? 'Error submitting.'; _ok = false; });
    }
    setState(() => _submitting = false);
  }

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
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next),
            if (_twoParent) ...[
              const SizedBox(height: 14),
              _stField('Parent Roll ID 2 *', _parent2Ctrl,
                  widgetKey: const Key('stocktakeParent2Field'),
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
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                key: const Key('stocktakeSubmitButton'),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_box, size: 24),
                label: Text(_submitting ? 'Saving...' : 'Add to Stock + Print Labels',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a73e8),
                  foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mode 2a: Annual Parent Stock Take ──────────────────────────────
class _AnnualParentForm extends StatefulWidget {
  final List<Map> vendors;
  final List<String> materialTypes;
  final List<String> basisWeights;
  final List<String> widths;
  const _AnnualParentForm({
    required this.vendors, required this.materialTypes,
    required this.basisWeights, required this.widths,
  });
  @override
  State<_AnnualParentForm> createState() => _AnnualParentFormState();
}

class _AnnualParentFormState extends State<_AnnualParentForm> {
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  bool _busy = false;
  String? _message;
  bool _ok = false;

  // Inline-form fields (shown when scanned roll does not exist)
  bool _showInlineForm = false;
  String _pendingRollId = '';
  final _poCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _vendor, _materialType, _basisWeight, _width;
  bool _submitting = false;

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_annual_parent';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress inline entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _showInlineForm = snap['showInlineForm'] ?? false;
      _pendingRollId = snap['pendingRollId'] ?? '';
      _poCtrl.text = snap['po'] ?? '';
      _lengthCtrl.text = snap['length'] ?? '';
      _weightCtrl.text = snap['weight'] ?? '';
      _notesCtrl.text = snap['notes'] ?? '';
      _vendor = snap['vendor'];
      _materialType = snap['materialType'];
      _basisWeight = snap['basisWeight'];
      _width = snap['width'];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'showInlineForm': _showInlineForm,
      'pendingRollId': _pendingRollId,
      'po': _poCtrl.text,
      'length': _lengthCtrl.text,
      'weight': _weightCtrl.text,
      'notes': _notesCtrl.text,
      'vendor': _vendor,
      'materialType': _materialType,
      'basisWeight': _basisWeight,
      'width': _width,
    });
    _scanCtrl.dispose(); _scanFocus.dispose();
    _poCtrl.dispose(); _lengthCtrl.dispose();
    _weightCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _onScan(String value) async {
    final rollId = value.trim();
    if (rollId.isEmpty) return;
    setState(() { _busy = true; _message = null; });
    final res = await ApiService.get('/rolls/$rollId');
    final exists = res['roll'] != null && (res['roll']['type'] == 'parent');
    if (exists) {
      // Record scan with was_already_in_system=true
      final scanRes = await ApiService.post('/stocktake/scan', {
        'type': 'parent',
        'roll_id': rollId,
        'was_already_in_system': true,
      });
      if (scanRes['success'] == true) {
        setState(() { _message = '✓ Recorded $rollId'; _ok = true; _busy = false; });
        _scanCtrl.clear();
        _scanFocus.requestFocus();
      } else {
        setState(() { _message = scanRes['detail'] ?? 'Scan failed.'; _ok = false; _busy = false; });
      }
    } else {
      // Open inline form for new parent
      setState(() {
        _busy = false;
        _showInlineForm = true;
        _pendingRollId = rollId;
        _message = 'Roll $rollId not found — fill in details below.';
        _ok = false;
      });
      _scanCtrl.clear();
    }
  }

  Future<void> _submitInline() async {
    if (_vendor == null || _materialType == null || _basisWeight == null || _width == null) {
      setState(() { _message = 'Vendor, Material Type, Basis Weight and Width are required.'; _ok = false; }); return;
    }
    if (_lengthCtrl.text.trim().isEmpty || _weightCtrl.text.trim().isEmpty) {
      setState(() { _message = 'Length and Weight are required.'; _ok = false; }); return;
    }
    setState(() => _submitting = true);
    final parentRes = await ApiService.post('/stocktake/parent', {
      'roll_id': _pendingRollId,
      'vendor_id': _vendor,
      'po_number': _poCtrl.text.trim(),
      'material_type': _materialType,
      'basis_weight': _basisWeight,
      'width': double.tryParse(_width ?? '') ?? 0,
      'length': double.tryParse(_lengthCtrl.text) ?? 0,
      'weight': double.tryParse(_weightCtrl.text) ?? 0,
      'notes': _notesCtrl.text.trim(),
    });
    if (parentRes['success'] == true) {
      await ApiService.post('/stocktake/scan', {
        'type': 'parent',
        'roll_id': _pendingRollId,
        'was_already_in_system': false,
      });
      setState(() {
        _message = 'Parent $_pendingRollId added & scan recorded!';
        _ok = true;
        _showInlineForm = false;
        _pendingRollId = '';
      });
      _poCtrl.clear(); _lengthCtrl.clear();
      _weightCtrl.clear(); _notesCtrl.clear();
      _vendor = null; _materialType = null;
      _basisWeight = null; _width = null;
      _scanFocus.requestFocus();
    } else {
      setState(() { _message = parentRes['detail'] ?? 'Submit failed.'; _ok = false; });
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showInlineForm) return _buildInlineForm();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stMessage(_message, _ok),
          const Text('Scan Parent Roll ID barcode',
              style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('stocktakeScanField'),
            controller: _scanCtrl,
            focusNode: _scanFocus,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: _onScan,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              labelText: 'Parent Roll ID',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              prefixIcon: Icon(Icons.qr_code_scanner, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _buildInlineForm() {
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
            _stMessage(_message, _ok),
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
              Expanded(
                child: _stSimpleDropdown(
                  context: context,
                  label: 'Width (in) *',
                  items: widget.widths,
                  value: _width,
                  onChanged: (v) => setState(() => _width = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stField('Length (ft) *', _lengthCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next),
              ),
            ]),
            const SizedBox(height: 14),
            _stField('Weight (lbs) *', _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done),
            const SizedBox(height: 14),
            _stField('Notes', _notesCtrl, multiline: true),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    key: const Key('stocktakeSubmitButton'),
                    onPressed: _submitting ? null : _submitInline,
                    icon: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_submitting ? 'Saving...' : 'Save & Record',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _showInlineForm = false;
                    _pendingRollId = '';
                    _message = null;
                  }),
                  child: const Text('Cancel', style: TextStyle(fontSize: 18)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Mode 2b: Annual Child Stock Take ──────────────────────────────
class _AnnualChildForm extends StatefulWidget {
  final List<Map> products;
  const _AnnualChildForm({required this.products});
  @override
  State<_AnnualChildForm> createState() => _AnnualChildFormState();
}

class _AnnualChildFormState extends State<_AnnualChildForm> {
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  bool _twoParent = false;
  // Pending pair when in two-parent mode and one composite has been scanned
  String? _pendingProductId;
  String? _pendingParent1;

  bool _busy = false;
  String? _message;
  bool _ok = false;

  // Inline form fields (when scanned child does not exist)
  bool _showInlineForm = false;
  String _pendingProductForForm = '';
  List<String> _pendingParentsForForm = [];

  final _qtyCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  // Bug #14 — in-memory form-state cache key for this sub-form.
  static const _cacheKey = 'stocktake_annual_child';

  @override
  void initState() {
    super.initState();
    // Bug #14 — restore any in-progress inline entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _twoParent = snap['twoParent'] ?? false;
      _showInlineForm = snap['showInlineForm'] ?? false;
      _pendingProductForForm = snap['pendingProductForForm'] ?? '';
      if (snap['pendingParentsForForm'] is List) {
        _pendingParentsForForm =
            (snap['pendingParentsForForm'] as List).cast<String>();
      }
      _qtyCtrl.text = snap['qty'] ?? '';
      _lengthCtrl.text = snap['length'] ?? '';
      _weightCtrl.text = snap['weight'] ?? '';
      _notesCtrl.text = snap['notes'] ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    FormStateCache.write(_cacheKey, {
      'twoParent': _twoParent,
      'showInlineForm': _showInlineForm,
      'pendingProductForForm': _pendingProductForForm,
      'pendingParentsForForm': List<String>.from(_pendingParentsForForm),
      'qty': _qtyCtrl.text,
      'length': _lengthCtrl.text,
      'weight': _weightCtrl.text,
      'notes': _notesCtrl.text,
    });
    _scanCtrl.dispose(); _scanFocus.dispose();
    _qtyCtrl.dispose(); _lengthCtrl.dispose();
    _weightCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  // Composite barcode: "ProductID-ParentID". Split at first "-".
  ({String productId, String parentId})? _parseComposite(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final i = v.indexOf('-');
    if (i <= 0 || i >= v.length - 1) return null;
    return (productId: v.substring(0, i), parentId: v.substring(i + 1));
  }

  Future<void> _processPair(String productId, List<String> parents,
      {bool fromTwoParent = false}) async {
    setState(() { _busy = true; _message = null; });
    final pCsv = parents.join(',');
    final res = await ApiService.get('/stocktake/lookup_child?product_id=$productId&parent_roll_ids=$pCsv');
    if (res['error'] == 'session_expired') {
      if (mounted) Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    final found = res['found'] == true;
    if (found) {
      final scanRes = await ApiService.post('/stocktake/scan', {
        'type': 'child',
        'product_id': productId,
        'parent_roll_ids': parents,
        'was_already_in_system': true,
      });
      if (scanRes['success'] == true) {
        setState(() {
          _message = '✓ Recorded child $productId from ${parents.join(' + ')}';
          _ok = true; _busy = false;
        });
        _scanCtrl.clear();
        // In two-parent mode the TwoParentScanFields widget owns + restores
        // focus, so don't yank it back to the single scan field.
        if (!fromTwoParent) _scanFocus.requestFocus();
      } else {
        setState(() {
          _message = scanRes['detail'] ?? 'Scan failed.';
          _ok = false; _busy = false;
        });
      }
    } else {
      setState(() {
        _busy = false;
        _showInlineForm = true;
        _pendingProductForForm = productId;
        _pendingParentsForForm = parents;
        _message = 'Child $productId not found — fill in details below.';
        _ok = false;
      });
      _scanCtrl.clear();
    }
  }

  // Single-parent scan handler. Two-parent mode uses _onTwoParentPair via the
  // shared TwoParentScanFields widget, so this only runs in single mode.
  Future<void> _onScan(String value) async {
    final parsed = _parseComposite(value);
    if (parsed == null) {
      setState(() { _message = 'Invalid composite — expected "ProductID-ParentID".'; _ok = false; });
      _scanCtrl.clear();
      return;
    }
    await _processPair(parsed.productId, [parsed.parentId]);
  }

  // Bug #15 — two-parent pair handler. Receives the two raw composite scans
  // from the shared TwoParentScanFields widget.
  Future<void> _onTwoParentPair(String scan1, String scan2) async {
    final p1 = _parseComposite(scan1);
    final p2 = _parseComposite(scan2);
    if (p1 == null || p2 == null) {
      setState(() { _message = 'Invalid composite — expected "ProductID-ParentID".'; _ok = false; });
      return;
    }
    if (p1.productId != p2.productId) {
      setState(() {
        _message = 'Product ID mismatch between the two labels — both must be the same product.';
        _ok = false;
      });
      return;
    }
    if (p1.parentId == p2.parentId) {
      setState(() {
        _message = 'Both labels are from the same parent. Scan one label per parent.';
        _ok = false;
      });
      return;
    }
    await _processPair(p1.productId, [p1.parentId, p2.parentId], fromTwoParent: true);
  }

  Future<void> _submitInline() async {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty < 1) {
      setState(() { _message = 'Quantity must be 1 or more.'; _ok = false; }); return;
    }
    if (_lengthCtrl.text.trim().isEmpty || _weightCtrl.text.trim().isEmpty) {
      setState(() { _message = 'Length and Weight are required.'; _ok = false; }); return;
    }
    setState(() => _submitting = true);
    final childRes = await ApiService.post('/stocktake/child', {
      'parent_roll_ids': _pendingParentsForForm,
      'product_id': _pendingProductForForm,
      'quantity': qty,
      'length': double.tryParse(_lengthCtrl.text) ?? 0,
      'weight': double.tryParse(_weightCtrl.text) ?? 0,
      'notes': _notesCtrl.text.trim(),
    });
    if (childRes['success'] == true) {
      await ApiService.post('/stocktake/scan', {
        'type': 'child',
        'product_id': _pendingProductForForm,
        'parent_roll_ids': _pendingParentsForForm,
        'was_already_in_system': false,
      });
      setState(() {
        _message = 'Child $_pendingProductForForm added & scan recorded!';
        _ok = true;
        _showInlineForm = false;
        _pendingProductForForm = '';
        _pendingParentsForForm = [];
      });
      _qtyCtrl.clear(); _lengthCtrl.clear();
      _weightCtrl.clear(); _notesCtrl.clear();
      _scanFocus.requestFocus();
    } else {
      setState(() { _message = childRes['detail'] ?? 'Submit failed.'; _ok = false; });
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showInlineForm) return _buildInlineForm();
    return SingleChildScrollView(
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
              onChanged: (v) => setState(() {
                _twoParent = v;
                _pendingProductId = null;
                _pendingParent1 = null;
              }),
            ),
          ]),
          const SizedBox(height: 8),
          Text(_twoParent
              ? 'Scan BOTH composite labels (one per parent) for each child roll.'
              : 'Scan composite barcode (ProductID-ParentID).',
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 8),
          // Bug #15 — two-parent mode shows TWO always-visible scan fields via
          // the shared widget; single-parent keeps the one composite field.
          if (_twoParent)
            TwoParentScanFields(
              key: const Key('stocktakeAnnualChildTwoParentScan'),
              firstFieldFocusNode: _scanFocus,
              enabled: !_busy,
              onPair: _onTwoParentPair,
            )
          else
            TextField(
              key: const Key('stocktakeScanField'),
              controller: _scanCtrl,
              focusNode: _scanFocus,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: _onScan,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Composite Barcode',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                prefixIcon: Icon(Icons.qr_code_scanner, size: 28),
              ),
            ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          if (_pendingProductId != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Pending pair: $_pendingProductId / $_pendingParent1',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineForm() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stMessage(_message, _ok),
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
                  Text('Product: $_pendingProductForForm',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Parents: ${_pendingParentsForForm.join(' + ')}',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
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
            _stField('Notes', _notesCtrl, multiline: true),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    key: const Key('stocktakeSubmitButton'),
                    onPressed: _submitting ? null : _submitInline,
                    icon: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_submitting ? 'Saving...' : 'Save & Record',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _showInlineForm = false;
                    _pendingProductForForm = '';
                    _pendingParentsForForm = [];
                    _message = null;
                  }),
                  child: const Text('Cancel', style: TextStyle(fontSize: 18)),
                ),
              ),
            ]),
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
    if (detail.startsWith('ERROR')) {
      setState(() { _message = 'Printing failed: $detail'; _ok = false; });
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
      setState(() { _message = 'Printing failed: $errorDetail'; _ok = false; });
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
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next),
            if (_twoParent) ...[
              const SizedBox(height: 14),
              _stField('Parent Roll ID 2 *', _parent2Ctrl,
                  widgetKey: const Key('stocktakeParent2Field'),
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
