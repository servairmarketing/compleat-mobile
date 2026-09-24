import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/parent_validation.dart';
import '../services/local_db.dart';
import '../services/field_focus.dart';
import '../services/form_state_cache.dart';
import '../widgets/load_error_card.dart';
import 'login_screen.dart';
import 'validation_dialog.dart';
import '../brand.dart';

/// Receive Parent Roll — header + rapid roll entry (Joe's ruling 2026-09-24).
///
/// A paper delivery is many rolls of one variety, so the screen is two parts:
///
///   1. DELIVERY HEADER (top card), filled once:
///      - Vendor + PO Number: FIXED for the delivery once the first roll saves
///        (dropdown/field lock; "New delivery" clears + unlocks).
///      - Material Type / Basis Weight / Width: set at the start, EDITABLE
///        mid-delivery — rolls saved AFTER a change carry the new values
///        (every save posts the header values current at that moment).
///   2. ROLL ENTRY (second card), repeated per roll:
///      Roll ID (required) → Length (ft, optional) → Weight (lbs, optional).
///      Scan/Enter on Roll ID → duplicate check → cursor to Length; Enter on
///      Length → Weight (empty allowed); Enter on Weight → the roll SAVES at
///      once with the header, haptic pulse + green flash, it appears in the
///      running list below with the delivery count, cursor back to Roll ID.
///      Per-roll Undo (own receive, in stock, no children, within 4 h — the
///      server enforces it via DELETE /rolls/{id}/receive).
///
/// PO Number is OPTIONAL (ruling 2026-09-24, matches PROJECT_SPEC); Length +
/// Weight are OPTIONAL; Roll ID is REQUIRED on this client (the server still
/// auto-generates for old clients). kBrandColor only.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _SessionRoll {
  final String rollId;
  final String? materialType;
  final String? basisWeight;
  final String? width;
  final double? length;
  final double? weight;
  final DateTime savedAt;
  bool undone;
  _SessionRoll({required this.rollId, this.materialType, this.basisWeight, this.width,
      this.length, this.weight, required this.savedAt, this.undone = false});

  Map<String, dynamic> toJson() => {
        'rollId': rollId, 'materialType': materialType, 'basisWeight': basisWeight,
        'width': width, 'length': length, 'weight': weight,
        'savedAt': savedAt.toIso8601String(), 'undone': undone,
      };
  static _SessionRoll fromJson(Map m) => _SessionRoll(
        rollId: m['rollId'] ?? '', materialType: m['materialType'], basisWeight: m['basisWeight'],
        width: m['width'], length: (m['length'] as num?)?.toDouble(), weight: (m['weight'] as num?)?.toDouble(),
        savedAt: DateTime.tryParse(m['savedAt'] ?? '') ?? DateTime.now(), undone: m['undone'] == true);
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
  // §2.16 — set when a masters load fails AND no offline cache filled the gap,
  // so the dropdowns would otherwise be silently empty. Drives a Retry card.
  String? _mastersLoadError;
  bool _submitting = false;
  String? _message;
  bool _messageSuccess = false;

  // Delivery session (2026-09-24): Vendor + PO lock after the first save;
  // the running list is this delivery's rolls, newest first.
  bool _headerLocked = false;
  final List<_SessionRoll> _sessionRolls = [];
  bool _flash = false;           // green flash on the roll card after a save
  String? _undoingRollId;        // row whose Undo is in flight

  // Bug #6 — inline duplicate Roll ID check.
  String? _rollIdError;          // shown under the Roll ID field
  String _lastCheckedRollId = '';// avoid hitting the API for unchanged value
  bool _rollIdChecking = false;

  // Bug #14 — in-memory form-state cache key for this screen. The whole
  // delivery (header, lock, running list, half-typed roll) survives nav-away.
  static const _cacheKey = 'receive';

  int get _liveCount => _sessionRolls.where((r) => !r.undone).length;

  @override
  void initState() {
    super.initState();
    _loadMasters();
    // Bug #14 — restore any in-progress delivery preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _rollIdController.text = snap['rollId'] ?? '';
      _poController.text = snap['po'] ?? '';
      _lengthController.text = snap['length'] ?? '';
      _weightController.text = snap['weight'] ?? '';
      _notesController.text = snap['notes'] ?? '';
      _selectedVendor = snap['vendor'];
      _selectedMaterialType = snap['materialType'];
      _selectedBasisWeight = snap['basisWeight'];
      _selectedWidth = snap['width'];
      _headerLocked = snap['headerLocked'] == true;
      final rolls = snap['sessionRolls'];
      if (rolls is List) {
        _sessionRolls.addAll(rolls.whereType<Map>().map(_SessionRoll.fromJson));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Header first when the delivery is not set up yet; otherwise straight to the scan field.
      if (_selectedVendor == null && !_headerLocked) {
        _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey);
      } else {
        _rollIdFocusNode.requestFocus();
      }
    });
    // Check for duplicate Roll ID when the field loses focus (typed entry).
    // Scan-completed events fire onSubmitted, which is wired separately.
    _rollIdFocusNode.addListener(() {
      if (!_rollIdFocusNode.hasFocus) {
        _checkRollIdDuplicate(_rollIdController.text.trim());
      }
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot the current delivery before disposing controllers so
    // returning to the screen restores it. In-memory only — never persisted.
    FormStateCache.write(_cacheKey, {
      'rollId': _rollIdController.text,
      'po': _poController.text,
      'length': _lengthController.text,
      'weight': _weightController.text,
      'notes': _notesController.text,
      'vendor': _selectedVendor,
      'materialType': _selectedMaterialType,
      'basisWeight': _selectedBasisWeight,
      'width': _selectedWidth,
      'headerLocked': _headerLocked,
      'sessionRolls': _sessionRolls.map((r) => r.toJson()).toList(),
    });
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

  // Bug #11 — advance with a short delay (so the just-completed field stays
  // visible for a beat) and keep the new field on-screen via FieldFocus.
  void _focusAndOpenDropdown(FocusNode node, GlobalKey<DropdownSearchState<String>> key) {
    FieldFocus.advance(context, target: node, openDropdown: key);
  }

  Future<void> _loadMasters() async {
    setState(() { _loading = true; _mastersLoadError = null; });
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

      // §2.16 — track whether any fetch failed to return its data (network /
      // timeout / server error). The offline cache still fills in below; we
      // only surface an error if a failure left a dropdown genuinely empty.
      bool anyFailed = false;

      if (vRes['records'] != null) {
        await LocalDb.cacheMasters('vendors', jsonEncode(vRes['records']));
        setState(() => _vendors = List<Map>.from(vRes['records']));
      } else {
        anyFailed = true;
        final cached = await LocalDb.getCachedMasters('vendors');
        if (cached != null) setState(() => _vendors = List<Map>.from(jsonDecode(cached)));
      }

      if (wRes['values'] != null) {
        await LocalDb.cacheMasters('widths', jsonEncode(wRes['values']));
        setState(() => _widths = List<String>.from(wRes['values']));
      } else {
        anyFailed = true;
        final cached = await LocalDb.getCachedMasters('widths');
        if (cached != null) setState(() => _widths = List<String>.from(jsonDecode(cached)));
      }

      if (mRes['values'] != null) {
        await LocalDb.cacheMasters('material_types', jsonEncode(mRes['values']));
        setState(() => _materialTypes = List<String>.from(mRes['values']));
      } else {
        anyFailed = true;
        final cached = await LocalDb.getCachedMasters('material_types');
        if (cached != null) setState(() => _materialTypes = List<String>.from(jsonDecode(cached)));
      }

      if (bRes['values'] != null) {
        await LocalDb.cacheMasters('basis_weights', jsonEncode(bRes['values']));
        setState(() => _basisWeights = List<String>.from(bRes['values']));
      } else {
        anyFailed = true;
        final cached = await LocalDb.getCachedMasters('basis_weights');
        if (cached != null) setState(() => _basisWeights = List<String>.from(jsonDecode(cached)));
      }

      final anyEmpty = _vendors.isEmpty || _widths.isEmpty ||
          _materialTypes.isEmpty || _basisWeights.isEmpty;
      setState(() {
        _loading = false;
        _mastersLoadError = (anyFailed && anyEmpty)
            ? 'Could not load some dropdowns — check your connection and retry.'
            : null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _mastersLoadError =
            'Could not load dropdowns — check your connection and retry.';
      });
    }
  }

  /// Resolves true when the Roll ID is present and not a duplicate.
  Future<bool> _checkRollIdDuplicate(String rollId) async {
    rollId = ParentValidation.normalizeRollId(rollId);
    if (rollId.isEmpty) {
      // Roll ID is REQUIRED on this client; an empty field is reported at
      // save time (validation dialog), not as an inline error while scanning.
      if (_rollIdError != null) setState(() => _rollIdError = null);
      _lastCheckedRollId = '';
      return false;
    }
    if (rollId == _lastCheckedRollId) return _rollIdError == null;
    _lastCheckedRollId = rollId;
    setState(() => _rollIdChecking = true);
    final res = await ApiService.get('/rolls/$rollId');
    if (!mounted) return false;
    setState(() => _rollIdChecking = false);
    // /rolls/{id} returns {"roll": {...}} on hit, {"detail": "...not found."} on
    // 404. Anything else (network error / session_expired) we silently ignore;
    // the server-side check at submit time is the final guard.
    if (res['roll'] != null) {
      // Only set the error if the field hasn't been edited since.
      if (ParentValidation.normalizeRollId(_rollIdController.text) == rollId) {
        setState(() => _rollIdError =
            'Roll ID already exists. Please scan a different roll or correct the value.');
        // Bug #10 — keep focus ON the Roll ID field when a duplicate is
        // detected so the operator can immediately edit or re-scan.
        _rollIdFocusNode.requestFocus();
      }
      return false;
    }
    if (ParentValidation.normalizeRollId(_rollIdController.text) == rollId) {
      setState(() => _rollIdError = null);
    }
    return true;
  }

  void _onRollIdChanged(String value) {
    // If the user edits the value after we flagged it, clear the error until
    // the next focus-out or submit triggers a re-check.
    if (_rollIdError != null) {
      setState(() => _rollIdError = null);
    }
    _lastCheckedRollId = '';
  }

  List<String> _headerIssues() {
    final issues = <String>[];
    if (_selectedVendor == null) issues.add('Vendor is required');
    if (_selectedMaterialType == null) issues.add('Material Type is required');
    if (_selectedBasisWeight == null) issues.add('Basis Weight is required');
    if (_selectedWidth == null) issues.add('Width is required');
    return issues;
  }

  /// Save ONE roll with the header values current now.
  Future<void> _submit() async {
    if (_submitting) return;
    final issues = _headerIssues();
    final rollId = ParentValidation.normalizeRollId(_rollIdController.text);
    final lengthText = _lengthController.text.trim();
    final weightText = _weightController.text.trim();
    if (rollId.isEmpty) issues.add('Roll ID is required — scan or type the roll');
    if (lengthText.isNotEmpty && double.tryParse(lengthText) == null) {
      issues.add('Length must be a number');
    }
    if (weightText.isNotEmpty && double.tryParse(weightText) == null) {
      issues.add('Weight must be a number');
    }
    if (_rollIdError != null) {
      issues.add('Roll ID already exists — please correct before submitting');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }
    setState(() { _submitting = true; _message = null; });
    final po = _poController.text.trim();
    final payload = {
      'roll_id': rollId,
      'vendor_id': _selectedVendor,
      'po_number': po.isEmpty ? null : po,                       // optional (ruling 2026-09-24)
      'material_type': _selectedMaterialType,
      'basis_weight': _selectedBasisWeight,
      'width': double.tryParse(_selectedWidth ?? ''),
      'length': lengthText.isEmpty ? null : double.tryParse(lengthText),   // optional
      'weight': weightText.isEmpty ? null : double.tryParse(weightText),   // optional
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/rolls/receive', payload);
    if (!mounted) return;
    if (res['success'] == true) {
      final id = (res['roll_id'] ?? rollId).toString();
      setState(() {
        _headerLocked = true;               // Vendor + PO fixed from the first save
        _sessionRolls.insert(0, _SessionRoll(
          rollId: id, materialType: _selectedMaterialType, basisWeight: _selectedBasisWeight,
          width: _selectedWidth, length: payload['length'] as double?, weight: payload['weight'] as double?,
          savedAt: DateTime.now()));
        _message = '✔ $id saved — $_liveCount this delivery';
        _messageSuccess = true;
        _submitting = false;
      });
      _confirmSaved();
      _clearRollFields();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _messageSuccess) setState(() => _message = null);
      });
    } else {
      setState(() {
        _message = ApiService.readableDetail(res, 'Error submitting.');
        _messageSuccess = false;
        _submitting = false;
      });
    }
  }

  // Confirmation: haptic pulse + green flash on the roll card (no sound
  // dependency — Joe's ruling 2026-09-24).
  void _confirmSaved() {
    HapticFeedback.mediumImpact();
    setState(() => _flash = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  /// Roll-only reset — the header (and its lock) is untouched; cursor back to Roll ID.
  void _clearRollFields() {
    _rollIdController.clear();
    _lengthController.clear();
    _weightController.clear();
    _notesController.clear();
    setState(() => _rollIdError = null);
    _lastCheckedRollId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollIdFocusNode.requestFocus();
    });
  }

  /// Finish this delivery: clear everything, unlock Vendor + PO, empty the list.
  Future<void> _newDelivery() async {
    if (_liveCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new delivery?'),
          content: Text('The $_liveCount roll(s) already saved stay received — only this screen resets.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('New delivery')),
          ],
        ),
      );
      if (ok != true) return;
    }
    FormStateCache.clear(_cacheKey);
    _rollIdController.clear();
    _poController.clear();
    _lengthController.clear();
    _weightController.clear();
    _notesController.clear();
    setState(() {
      _selectedVendor = null;
      _selectedMaterialType = null;
      _selectedBasisWeight = null;
      _selectedWidth = null;
      _headerLocked = false;
      _sessionRolls.clear();
      _rollIdError = null;
      _message = null;
    });
    _lastCheckedRollId = '';
    FocusScope.of(context).unfocus();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey);
    });
  }

  /// Per-roll undo — the server enforces: own receive, in stock, no children,
  /// within 4 h; anything else comes back 4xx with a readable reason.
  Future<void> _undo(_SessionRoll r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Undo ${r.rollId}?'),
        content: const Text('The roll record is removed from Receiving.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Undo')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _undoingRollId = r.rollId);
    final res = await ApiService.delete('/rolls/${Uri.encodeComponent(r.rollId)}/receive');
    if (!mounted) return;
    setState(() {
      _undoingRollId = null;
      if (res['success'] == true) {
        r.undone = true;
        _message = '↩ ${r.rollId} undone — $_liveCount this delivery';
        _messageSuccess = true;
      } else {
        _message = 'Could not undo: ${ApiService.readableDetail(res, 'unknown error')}';
        _messageSuccess = false;
      }
    });
    _rollIdFocusNode.requestFocus();
  }

  String _headerSummary() {
    if (_selectedVendor == null) return '';
    final po = _poController.text.trim();
    return '${_selectedVendor}${po.isEmpty ? '' : ' · PO $po'} · now '
        '${_selectedMaterialType ?? '?'} / ${_selectedBasisWeight ?? '?'} / '
        '${_selectedWidth == null ? '?' : '$_selectedWidth"'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kBrandColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Receive Parent Roll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            key: const Key('newDeliveryButton'),
            onPressed: _newDelivery,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New delivery'),
          ),
        ],
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
                    key: Key(_messageSuccess ? 'messageBannerSuccess' : 'messageBannerError'),
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

                if (_mastersLoadError != null)
                  LoadErrorCard(
                    message: _mastersLoadError!,
                    onRetry: _loadMasters,
                  ),

                // ── 1. DELIVERY HEADER ─────────────────────────────────────
                _sectionTitle('Delivery', trailing: _headerLocked
                    ? const _Chip(text: '🔒 Vendor & PO locked', color: Color(0xFFFFF8E1), fg: Color(0xFF5C4500))
                    : null),
                const SizedBox(height: 10),

                _buildVendorDropdown(enabled: !_headerLocked),
                const SizedBox(height: 14),

                _buildField('PO Number (optional)', _poController,
                    widgetKey: const Key('poNumberField'),
                    focusNode: _poFocusNode,
                    readOnly: _headerLocked,
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
                    // Mid-delivery edit: go back to scanning; initial setup: continue the header.
                    if (_headerLocked) { _rollIdFocusNode.requestFocus(); return; }
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
                    if (_headerLocked) { _rollIdFocusNode.requestFocus(); return; }
                    _focusAndOpenDropdown(_widthFocusNode, _widthDropdownKey);
                  },
                ),
                const SizedBox(height: 14),

                _buildSimpleDropdown(
                  widgetKey: const Key('widthDropdown'),
                  label: 'Width (in) *',
                  items: _widths,
                  value: _selectedWidth,
                  focusNode: _widthFocusNode,
                  dropdownKey: _widthDropdownKey,
                  onChanged: (v) {
                    setState(() => _selectedWidth = v);
                    FieldFocus.advance(context, target: _rollIdFocusNode);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _headerLocked
                      ? 'Material, basis weight and width can still be changed — rolls saved after the change carry the new values.'
                      : 'Fill the delivery once, then scan roll after roll below.',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 22),

                // ── 2. ROLL ENTRY ──────────────────────────────────────────
                _sectionTitle('Roll entry', subtitle: 'scan → Enter → Enter → Enter'),
                const SizedBox(height: 10),
                AnimatedContainer(
                  key: const Key('rollCard'),
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _flash ? const Color(0xFFE8F5E9) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _flash ? Colors.green : Colors.black12, width: _flash ? 2 : 1),
                  ),
                  child: Column(children: [
                    _buildField('Roll ID *', _rollIdController,
                        widgetKey: const Key('rollIdField'),
                        hint: 'Scan or type the roll ID',
                        focusNode: _rollIdFocusNode,
                        inputFormatters: const [UpperCaseRollIdFormatter()],
                        keyboardType: TextInputType.emailAddress,
                        // Bug #10 — `done` (not `next`) so Flutter's built-in
                        // focus-advance can't race ahead of the duplicate check.
                        textInputAction: TextInputAction.done,
                        onChanged: _onRollIdChanged,
                        errorText: _rollIdError,
                        onSubmitted: (val) async {
                          // Scan → duplicate check → Length (stay put on a duplicate).
                          final ok = await _checkRollIdDuplicate(val.trim());
                          if (!mounted) return;
                          if (!ok) { _rollIdFocusNode.requestFocus(); return; }
                          FieldFocus.advance(context, target: _lengthFocusNode);
                        }),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _buildField('Length (ft)', _lengthController,
                            widgetKey: const Key('lengthField'),
                            hint: 'optional',
                            focusNode: _lengthFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.next,
                            // Enter on an empty Length just moves on.
                            onSubmitted: (_) => FieldFocus.advance(context, target: _weightFocusNode)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildField('Weight (lbs)', _weightController,
                            widgetKey: const Key('weightField'),
                            hint: 'optional',
                            focusNode: _weightFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.done,
                            // Enter on Weight (empty allowed) SAVES the roll.
                            onSubmitted: (_) => _submit()),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _buildField('Notes (this roll)', _notesController,
                        focusNode: _notesFocusNode,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit()),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: Focus(
                          focusNode: _submitFocusNode,
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              key: const Key('submitButton'),
                              onPressed: (_submitting || _rollIdError != null) ? null : _submit,
                              icon: _submitting
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download_rounded, size: 24),
                              label: Text(_submitting ? 'Saving...' : 'Receive Roll',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBrandColor,
                                foregroundColor: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          key: const Key('clearRollButton'),
                          onPressed: _clearRollFields,
                          child: const Text('Clear roll', style: TextStyle(fontSize: 18)),
                        ),
                      ),
                    ]),
                  ]),
                ),

                // ── 3. RUNNING LIST ────────────────────────────────────────
                if (_sessionRolls.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle('This delivery',
                      trailing: _Chip(text: '$_liveCount', color: kBrandColor, fg: Colors.white, key: const Key('sessionCount'))),
                  if (_headerSummary().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(_headerSummary(), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ),
                  ..._sessionRolls.asMap().entries.map((e) => _sessionRow(_sessionRolls.length - e.key, e.value)),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          ),
    );
  }

  Widget _sectionTitle(String text, {String? subtitle, Widget? trailing}) {
    return Row(children: [
      Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Text('— $subtitle', style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ],
      const Spacer(),
      if (trailing != null) trailing,
    ]);
  }

  Widget _sessionRow(int n, _SessionRoll r) {
    final muted = TextStyle(fontSize: 13, color: r.undone ? Colors.black38 : Colors.black54,
        decoration: r.undone ? TextDecoration.lineThrough : null);
    String fmt(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
    return Container(
      key: Key('sessionRow-${r.rollId}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: r.undone ? const Color(0xFFF5F5F5) : const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(children: [
        SizedBox(width: 26, child: Text('$n', style: muted)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.rollId, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace',
                color: r.undone ? Colors.black38 : Colors.black87,
                decoration: r.undone ? TextDecoration.lineThrough : null)),
            Text('${r.materialType ?? '—'} / ${r.basisWeight ?? '—'} / ${r.width == null ? '—' : '${r.width}"'}'
                '  ·  L ${fmt(r.length)}  ·  W ${fmt(r.weight)}'
                '  ·  ${r.savedAt.hour.toString().padLeft(2, '0')}:${r.savedAt.minute.toString().padLeft(2, '0')}',
                style: muted),
          ]),
        ),
        if (r.undone)
          Text('undone', style: muted)
        else
          SizedBox(
            height: 36,
            child: OutlinedButton(
              key: Key('undo-${r.rollId}'),
              onPressed: _undoingRollId == null ? () => _undo(r) : null,
              child: _undoingRollId == r.rollId
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Undo'),
            ),
          ),
      ]),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {bool autofocus = false, String? hint,
       FocusNode? focusNode, bool multiline = false, bool readOnly = false,
       TextInputType? keyboardType, TextInputAction? textInputAction,
       Function(String)? onSubmitted, Function(String)? onChanged,
       List<TextInputFormatter>? inputFormatters,
       String? errorText, Key? widgetKey}) {
    return TextField(
      key: widgetKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: readOnly,
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
      style: TextStyle(fontSize: 18, color: readOnly ? Colors.black54 : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF3F4F6) : null,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }

  Widget _buildVendorDropdown({bool enabled = true}) {
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
        enabled: enabled,
        // Bug #30 — scroll the field up so the popup opens below it.
        onBeforePopupOpening: (_) =>
            FieldFocus.ensureRoomForDropdown(_vendorDropdownKey.currentContext),
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
          // Bug #18 — cap at ~40% of viewport so the auto-opened dropdown
          // leaves the previously-completed field visible above it.
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
        onChanged: (val) {
          FocusManager.instance.primaryFocus?.unfocus();
          if (val == null) { setState(() => _selectedVendor = null); return; }
          setState(() => _selectedVendor = val.split(' — ')[0]);
          FieldFocus.advance(context, target: _poFocusNode);
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
        // Bug #30 — scroll the field up so the popup opens below it.
        onBeforePopupOpening: (_) =>
            FieldFocus.ensureRoomForDropdown(dropdownKey.currentContext),
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
          // Bug #18 — cap at ~40% of viewport so the auto-opened dropdown
          // leaves the previously-completed field visible above it.
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
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final Color fg;
  const _Chip({required this.text, required this.color, required this.fg, super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.bold)),
      );
}
