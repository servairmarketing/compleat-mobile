import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/parent_validation.dart';
import '../services/local_db.dart';
import '../services/field_focus.dart';
import '../services/scanner_status_service.dart';
import '../widgets/load_error_card.dart';
import 'login_screen.dart';
import 'validation_dialog.dart';
import '../brand.dart';

/// Receive Parent Roll — shipment batch flow (Joe's rulings 2026-09-25, rev 2).
///
/// Rolls are NOT saved as they are scanned. They collect in an on-screen list
/// and ONE Submit at the bottom saves the whole shipment through
/// POST /rolls/receive/batch (all-or-nothing on the server) — the same pattern
/// as Roll Production. Screen parts:
///
///   1. SHIPMENT DETAILS (top), filled once:
///      - Vendor + PO Number: lock once the first roll is in the list
///        ("New shipment" resets).
///      - Material Type / Basis Weight / Width: EDITABLE mid-shipment — rolls
///        ADDED after a change carry the new values (each roll keeps its own copy).
///   2. ROLLS: a counter ("N rolls") ABOVE the Roll ID field that expands INLINE
///      to the list of roll IDs; a roll expands to its details — editable and
///      removable, since nothing is saved yet. Then the entry fields:
///      Roll ID (scan → Enter → Length) → Enter → Weight → Enter → the roll is
///      ADDED to the list (locally) and the cursor returns to Roll ID. Enter on
///      an empty field skips it. Notes: tap in, type, Enter completes the roll.
///   3. ONE plain Submit button at the bottom → result "N received" → cleared.
///      The result keeps a per-roll Undo (DELETE /rolls/{id}/receive) for
///      post-submit corrections.
///
/// DRAFT PERSISTENCE (ruling #6): the whole state (header + list + half-typed
/// roll) is written to SharedPreferences on every change and restored when the
/// screen — or the app — comes back, clearly marked as unsubmitted. Cleared only
/// by Submit or New shipment. This supersedes the in-memory-only FormStateCache
/// for THIS screen only (Joe, 2026-09-25); other screens are unchanged.
///
/// PO Number OPTIONAL; Length + Weight OPTIONAL; Roll ID REQUIRED. kBrandColor only.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

/// One roll in the shipment list (unsubmitted) or in the last result.
class _ShipRoll {
  final int key;
  String rollId;
  String? materialType;
  String? basisWeight;
  String? width;
  double? length;
  double? weight;
  String notes;
  final DateTime addedAt;
  String? serverError;   // set from a refused submit's per-roll results (not persisted)
  bool undone;           // result list only
  _ShipRoll({required this.key, required this.rollId, this.materialType, this.basisWeight, this.width,
      this.length, this.weight, this.notes = '', DateTime? addedAt, this.serverError, this.undone = false})
      : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'key': key, 'rollId': rollId, 'materialType': materialType, 'basisWeight': basisWeight,
        'width': width, 'length': length, 'weight': weight, 'notes': notes,
        'addedAt': addedAt.toIso8601String(),
      };
  static _ShipRoll fromJson(Map m) => _ShipRoll(
        key: (m['key'] as num?)?.toInt() ?? 0, rollId: m['rollId'] ?? '', materialType: m['materialType'],
        basisWeight: m['basisWeight'], width: m['width']?.toString(),
        length: (m['length'] as num?)?.toDouble(), weight: (m['weight'] as num?)?.toDouble(),
        notes: m['notes'] ?? '', addedAt: DateTime.tryParse(m['addedAt'] ?? '') ?? DateTime.now());
  _ShipRoll copy() => _ShipRoll(key: key, rollId: rollId, materialType: materialType, basisWeight: basisWeight,
      width: width, length: length, weight: weight, notes: notes, addedAt: addedAt);

  Map<String, dynamic> toPayload() => {
        'roll_id': rollId,
        'material_type': materialType,
        'basis_weight': basisWeight,
        'width': double.tryParse(width ?? ''),
        'length': length,
        'weight': weight,
        'notes': notes,
      };
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  static const _draftKey = 'receive_shipment_draft_v1';

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

  // Shipment (rev 2): Vendor + PO lock once the first roll is in the list; the
  // list is local until Submit. _submitId = idempotent retry key for the batch.
  bool _headerLocked = false;
  final List<_ShipRoll> _rolls = [];
  String _submitId = _newSubmitId();
  int _nextKey = 1;
  bool _listOpen = false;
  int? _openRollKey;
  bool _flash = false;                 // green flash on the roll card after an add
  String? _restoredNote;               // "Unsubmitted shipment restored — N rolls"
  Timer? _persistTimer;
  bool _draftLoaded = false;

  // Last submitted shipment (result + per-roll Undo).
  List<_ShipRoll>? _lastSubmitted;
  DateTime? _lastSubmittedAt;
  String? _lastVendor;
  String? _lastPo;
  String? _undoingRollId;

  // Bug #6 — inline duplicate Roll ID check.
  String? _rollIdError;          // shown under the Roll ID field
  String _lastCheckedRollId = '';// avoid hitting the API for unchanged value

  // Joe's ruling 2026-09-25 (option 1) — "no-read = skip": a scan-trigger pull
  // with nothing to decode advances the cursor exactly like Enter on the
  // focused entry field. DataWedge keystroke output sends nothing on a
  // no-read, so we listen to DataWedge SCANNER_STATUS instead (see
  // scanner_status_service.dart). Silent on a device without DataWedge.
  late final NoReadDetector _noRead = NoReadDetector(onNoRead: _onNoRead);
  StreamSubscription<ScannerEvent>? _scanSub;
  // Walkthrough diagnostics (TEST builds only): last status / last key seen.
  // Diagnostics (TEST builds): state, reason, counters and last events all
  // live in ScannerStatusService (durable across screens — v1.0.77 fix); this
  // screen just repaints when the service says something changed.
  void _onScannerChange() { if (mounted && appEnvironment == 'test') setState(() {}); }

  static String _newSubmitId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${r.nextInt(1 << 30).toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
  }

  int get _count => _rolls.length;
  String get _countLabel => '$_count ${_count == 1 ? 'roll' : 'rolls'}';

  @override
  void initState() {
    super.initState();
    _loadMasters();
    _restoreDraft();
    // Keep the draft current as the operator types.
    for (final c in [_rollIdController, _poController, _lengthController, _weightController, _notesController]) {
      c.addListener(_persistDraft);
    }
    // No-read detection: any text arriving in an entry field means the pull
    // decoded something (DataWedge keystrokes), so it is NOT a no-read.
    for (final c in [_rollIdController, _lengthController, _weightController, _notesController]) {
      c.addListener(_noRead.noteInput);
    }
    ScannerStatusService.instance.loadTriggerKeyCodes();  // configured trigger keys (default 563 + 564)
    _scanSub = ScannerStatusService.instance.events.listen(_onScannerEvent);
    ScannerStatusService.instance.changes.addListener(_onScannerChange);
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
    // Ruling #6 — nav-away keeps the whole unsubmitted shipment. Snapshot the
    // controllers BEFORE disposing them, then write (fire-and-forget).
    _persistTimer?.cancel();
    _persistDraftNow();
    _scanSub?.cancel();
    ScannerStatusService.instance.changes.removeListener(_onScannerChange);
    _noRead.dispose();
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
    _scrollController.dispose();
    super.dispose();
  }

  // ── Draft persistence (SharedPreferences; Receive only) ────────────────────
  Map<String, dynamic> _draftSnapshot() => {
        'v': 1,
        'submitId': _submitId,
        'nextKey': _nextKey,
        'headerLocked': _headerLocked,
        'vendor': _selectedVendor,
        'po': _poController.text,
        'materialType': _selectedMaterialType,
        'basisWeight': _selectedBasisWeight,
        'width': _selectedWidth,
        'rollId': _rollIdController.text,
        'length': _lengthController.text,
        'weight': _weightController.text,
        'notes': _notesController.text,
        'rolls': _rolls.map((r) => r.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  bool get _draftIsEmpty =>
      _rolls.isEmpty && _selectedVendor == null && _selectedMaterialType == null &&
      _selectedBasisWeight == null && _selectedWidth == null && _poController.text.isEmpty &&
      _rollIdController.text.isEmpty && _lengthController.text.isEmpty &&
      _weightController.text.isEmpty && _notesController.text.isEmpty;

  /// Debounced write — called on every change.
  void _persistDraft() {
    if (!_draftLoaded) return;             // never overwrite a draft we have not read yet
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), _persistDraftNow);
  }

  void _persistDraftNow() {
    if (!_draftLoaded) return;
    final empty = _draftIsEmpty;
    final payload = empty ? null : jsonEncode(_draftSnapshot());
    SharedPreferences.getInstance().then((p) async {
      if (payload == null) {
        await p.remove(_draftKey);
      } else {
        await p.setString(_draftKey, payload);
      }
    }).catchError((_) {});
  }

  Future<void> _clearDraftStorage() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _restoreDraft() async {
    Map<String, dynamic>? snap;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_draftKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) snap = decoded;
      }
    } catch (_) {
      snap = null;
    }
    if (!mounted) return;
    if (snap != null) {
      final s = snap;
      final rolls = s['rolls'];
      setState(() {
        final sid = s['submitId'];
        if (sid is String && sid.isNotEmpty) _submitId = sid;
        _nextKey = (s['nextKey'] as num?)?.toInt() ?? 1;
        _selectedVendor = s['vendor'];
        _selectedMaterialType = s['materialType'];
        _selectedBasisWeight = s['basisWeight'];
        _selectedWidth = s['width']?.toString();
        _poController.text = s['po'] ?? '';
        _rollIdController.text = s['rollId'] ?? '';
        _lengthController.text = s['length'] ?? '';
        _weightController.text = s['weight'] ?? '';
        _notesController.text = s['notes'] ?? '';
        _rolls.clear();
        if (rolls is List) _rolls.addAll(rolls.whereType<Map>().map(_ShipRoll.fromJson));
        for (final r in _rolls) {
          if (r.key >= _nextKey) _nextKey = r.key + 1;
        }
        _headerLocked = _rolls.isNotEmpty || s['headerLocked'] == true;
        final n = _rolls.length;
        _restoredNote = 'Unsubmitted shipment restored — $n ${n == 1 ? 'roll' : 'rolls'}'
            '${n == 0 ? ' (header only)' : ' in the list'}. Nothing is saved until you press Submit.';
      });
    }
    _draftLoaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Header first when the shipment is not set up yet; otherwise straight to the scan field.
      if (_selectedVendor == null && !_headerLocked) {
        _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey);
      } else {
        _rollIdFocusNode.requestFocus();
      }
    });
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

  /// Resolves true when the Roll ID is present, not already in this shipment
  /// and not on the server.
  Future<bool> _checkRollIdDuplicate(String rollId) async {
    rollId = ParentValidation.normalizeRollId(rollId);
    if (rollId.isEmpty) {
      // Roll ID is REQUIRED; an empty field is reported at add time
      // (validation dialog), not as an inline error while scanning.
      if (_rollIdError != null) setState(() => _rollIdError = null);
      _lastCheckedRollId = '';
      return false;
    }
    if (_rolls.any((r) => r.rollId == rollId)) {
      setState(() => _rollIdError = 'This roll is already in the shipment list.');
      _lastCheckedRollId = rollId;
      _rollIdFocusNode.requestFocus();
      return false;
    }
    if (rollId == _lastCheckedRollId) return _rollIdError == null;
    _lastCheckedRollId = rollId;
    final res = await ApiService.get('/rolls/$rollId');
    if (!mounted) return false;
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

  // ── Add one roll to the LIST (local; nothing is sent to the server) ────────
  void _onScannerEvent(ScannerEvent e) {
    if (!mounted) return;
    if (e.isStatus) {
      _noRead.onStatus(e.status);
    } else if (e.isKey) {
      // Second feed (Joe's ruling 2026-09-25): the scan-trigger KEY. Down
      // arms, up = beam-off; repeats while held are ignored. Same detector as
      // the DataWedge path → one no-read per pull, never a double-fire. The key
      // may arrive from the native feed, the Dart feed, or both (v1.0.77):
      // a second down only re-arms, a second up finds nothing armed.
      if (ScannerStatusService.instance.isTriggerKey(e)) {
        if (e.action == 0 && e.repeat == 0) _noRead.onTriggerDown();
        if (e.action == 1) _noRead.onTriggerUp();
      }
    }
    // 'listening' and the diagnostics are handled by the service itself.
  }

  /// A trigger pull that decoded nothing: behave exactly like Enter on the
  /// focused entry field. An EMPTY Roll ID is the one exception — there is
  /// nothing to skip to without a roll, so the pull is ignored there.
  Future<void> _onNoRead() async {
    if (!mounted || _submitting) return;
    if (appEnvironment == 'test') setState(() {});   // refresh the no-read counter
    if (_rollIdFocusNode.hasFocus) {
      final val = _rollIdController.text.trim();
      if (val.isEmpty) return;
      final ok = await _checkRollIdDuplicate(val);
      if (!mounted) return;
      if (!ok) { _rollIdFocusNode.requestFocus(); return; }
      FieldFocus.advance(context, target: _lengthFocusNode);
    } else if (_lengthFocusNode.hasFocus) {
      FieldFocus.advance(context, target: _weightFocusNode);
    } else if (_weightFocusNode.hasFocus || _notesFocusNode.hasFocus) {
      await _addRoll();
    }
    // Header fields / nothing focused: a no-read means nothing there.
  }

  /// TEST builds only: one small grey line under the Rolls card so the
  /// walkthrough on the real TC22 can read what DataWedge delivers.
  Widget _buildScannerDiagnostics() {
    if (appEnvironment != 'test') return const SizedBox.shrink();
    final svc = ScannerStatusService.instance;
    final txt = 'Scanner diag · ${svc.stateText}'
        ' · trigger keys ${svc.triggerKeysText}'
        ' · no-reads ${_noRead.noReads}${_noRead.isArmed ? ' (armed)' : ''}'
        ' · ${svc.countersText}'
        '${svc.lastStatus == null ? '' : ' · last ${svc.lastStatus}'}'
        '${svc.lastKey == null ? '' : ' · last ${svc.lastKey}'}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(txt, key: const Key('scannerDiag'),
          style: const TextStyle(fontSize: 11, color: Colors.black45)),
    );
  }

  Future<void> _addRoll() async {
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
    if (rollId.isNotEmpty && _rolls.any((r) => r.rollId == rollId)) {
      issues.add('This roll is already in the shipment list');
    } else if (_rollIdError != null) {
      issues.add('Roll ID already exists — please correct before adding it');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues, title: 'Cannot add roll');
      return;
    }
    final roll = _ShipRoll(
      key: _nextKey++,
      rollId: rollId,
      materialType: _selectedMaterialType,
      basisWeight: _selectedBasisWeight,
      width: _selectedWidth,
      length: lengthText.isEmpty ? null : double.tryParse(lengthText),
      weight: weightText.isEmpty ? null : double.tryParse(weightText),
      notes: _notesController.text.trim(),
    );
    setState(() {
      _rolls.add(roll);
      _headerLocked = true;                // Vendor + PO fixed from the first roll
      _lastSubmitted = null;               // a new shipment is under way
      _message = '✔ $rollId added — $_countLabel in this shipment';
      _messageSuccess = true;
    });
    _confirmAdded();
    _clearRollFields();
    _persistDraft();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _messageSuccess) setState(() => _message = null);
    });
  }

  // Confirmation: haptic pulse + green flash on the roll card (no sound
  // dependency — Joe's ruling 2026-09-24).
  void _confirmAdded() {
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

  // ── Local edits + removal (nothing is saved yet) ───────────────────────────
  void _editRoll(_ShipRoll r, void Function() change) {
    setState(() {
      change();
      r.serverError = null;
    });
    _persistDraft();
  }

  Future<void> _removeRoll(_ShipRoll r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${r.rollId}?'),
        content: const Text('It has not been submitted, so nothing else changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _rolls.remove(r);
      if (_openRollKey == r.key) _openRollKey = null;
      if (_rolls.isEmpty) { _headerLocked = false; _listOpen = false; }
      _message = '${r.rollId} removed — $_countLabel in this shipment';
      _messageSuccess = true;
    });
    _persistDraft();
    _rollIdFocusNode.requestFocus();
  }

  // ── ONE Submit → POST /rolls/receive/batch (all-or-nothing) ────────────────
  Future<void> _submitShipment() async {
    if (_submitting) return;
    final issues = <String>[];
    if (_selectedVendor == null) issues.add('Vendor is required');
    if (_rolls.isEmpty) issues.add('Scan at least one roll before submitting');
    for (var i = 0; i < _rolls.length; i++) {
      final r = _rolls[i];
      if (r.materialType == null || r.basisWeight == null || r.width == null) {
        issues.add('Roll ${i + 1} (${r.rollId}) is missing material, basis weight or width — open the list and complete it');
      }
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }
    setState(() { _submitting = true; _message = null; });
    final po = _poController.text.trim();
    final payload = {
      'vendor_id': _selectedVendor,
      'po_number': po.isEmpty ? null : po,
      'submit_id': _submitId,
      'rolls': _rolls.map((r) => r.toPayload()).toList(),
    };
    final res = await ApiService.post('/rolls/receive/batch', payload);
    if (!mounted) return;
    if (res['success'] == true) {
      final n = (res['received'] as num?)?.toInt() ?? _rolls.length;
      final replayed = res['replayed'] == true;
      final submitted = _rolls.map((r) => r.copy()).toList();
      final vendor = _selectedVendor;
      _resetShipment();
      setState(() {
        _lastSubmitted = submitted;
        _lastSubmittedAt = DateTime.now();
        _lastVendor = vendor;
        _lastPo = po.isEmpty ? null : po;
        _message = '✔ $n ${n == 1 ? 'roll' : 'rolls'} received${replayed ? ' (already saved by an earlier submit)' : ''}';
        _messageSuccess = true;
        _submitting = false;
      });
      HapticFeedback.mediumImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey);
      });
    } else {
      // Nothing was saved. Mark the exact rolls the server refused and open the list.
      final detail = res['detail'];
      final byId = <String, String>{};
      if (detail is Map && detail['results'] is List) {
        for (final x in (detail['results'] as List).whereType<Map>()) {
          if (x['ok'] != true && x['error'] != null) byId[x['roll_id'].toString()] = x['error'].toString();
        }
      }
      setState(() {
        for (final r in _rolls) {
          r.serverError = byId[r.rollId];
        }
        if (byId.isNotEmpty) _listOpen = true;
        _message = 'Nothing saved: ${ApiService.readableDetail(res, 'Error submitting.')}';
        _messageSuccess = false;
        _submitting = false;
      });
    }
  }

  /// After a successful Submit (or "New shipment"): the screen is empty again.
  void _resetShipment() {
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
      _rolls.clear();
      _submitId = _newSubmitId();
      _nextKey = 1;
      _listOpen = false;
      _openRollKey = null;
      _rollIdError = null;
      _restoredNote = null;
    });
    _lastCheckedRollId = '';
    _persistTimer?.cancel();
    _clearDraftStorage();
  }

  /// "New shipment": discard the unsubmitted list (confirm), unlock Vendor + PO.
  Future<void> _newShipment() async {
    if (_count > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new shipment?'),
          content: Text('The $_countLabel in the list have NOT been submitted and will be discarded.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard & start new')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    _resetShipment();
    setState(() { _lastSubmitted = null; _message = null; });
    FocusScope.of(context).unfocus();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAndOpenDropdown(_vendorFocusNode, _vendorDropdownKey);
    });
  }

  /// Per-roll undo on the LAST SUBMITTED shipment — the server enforces: own
  /// receive, in stock, no children, within 4 h; anything else comes back 4xx
  /// with a readable reason.
  Future<void> _undo(_ShipRoll r) async {
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
        final live = _lastSubmitted?.where((x) => !x.undone).length ?? 0;
        _message = '↩ ${r.rollId} undone — $live still received';
        _messageSuccess = true;
      } else {
        _message = 'Could not undo: ${ApiService.readableDetail(res, 'unknown error')}';
        _messageSuccess = false;
      }
    });
  }

  String _headerSummary() {
    if (_selectedVendor == null) return '';
    final po = _poController.text.trim();
    return '${_selectedVendor}${po.isEmpty ? '' : ' · PO $po'}';
  }

  static String _fmt(double? v) =>
      v == null ? '—' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

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
            key: const Key('newShipmentButton'),
            onPressed: _newShipment,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New shipment'),
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

                // Ruling #6 — the restored, still-unsubmitted shipment is clearly marked.
                if (_restoredNote != null)
                  Container(
                    key: const Key('draftRestoredBanner'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF4C542)),
                    ),
                    child: Text('📝 $_restoredNote', style: const TextStyle(
                      color: Color(0xFF5C4500), fontSize: 14, fontWeight: FontWeight.bold)),
                  ),

                if (_mastersLoadError != null)
                  LoadErrorCard(
                    message: _mastersLoadError!,
                    onRetry: _loadMasters,
                  ),

                // ── 1. SHIPMENT DETAILS ───────────────────────────────────
                _sectionTitle('Shipment Details', trailing: _headerLocked
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
                    _persistDraft();
                    // Mid-shipment edit: go back to scanning; initial setup: continue the header.
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
                    _persistDraft();
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
                    _persistDraft();
                    FieldFocus.advance(context, target: _rollIdFocusNode);
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Material, basis weight and width can be changed mid-shipment — rolls added after the change carry the new values.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 22),

                // ── 2. ROLLS: counter + inline list ABOVE the Roll ID field ──
                _sectionTitle('Rolls'),
                const SizedBox(height: 10),
                _buildCounter(),
                if (_listOpen) _buildRollList(),
                const SizedBox(height: 14),

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
                          // Scan → duplicate check → Length (stay put on a duplicate or when empty).
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
                            // Enter on Weight (empty allowed) ADDS the roll to the list.
                            onSubmitted: (_) => _addRoll()),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _buildField('Notes (this roll)', _notesController,
                        widgetKey: const Key('notesField'),
                        focusNode: _notesFocusNode,
                        textInputAction: TextInputAction.done,
                        // Tap in, type, Enter completes the roll.
                        onSubmitted: (_) => _addRoll()),
                  ]),
                ),
                _buildScannerDiagnostics(),
                const SizedBox(height: 22),

                // ── 3. ONE Submit at the bottom ────────────────────────────
                Row(children: [
                  Expanded(
                    child: Text(
                      _count == 0
                          ? 'No rolls yet'
                          : '$_countLabel ready${_headerSummary().isEmpty ? '' : ' · ${_headerSummary()}'}',
                      key: const Key('submitSummary'),
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    width: 180,
                    child: ElevatedButton(
                      key: const Key('submitButton'),
                      onPressed: (_submitting || _count == 0) ? null : _submitShipment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrandColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE0E0E0),
                        disabledForegroundColor: Colors.black38),
                      child: _submitting
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),

                // ── 4. RESULT of the last submit, with per-roll Undo ───────
                if (_lastSubmitted != null && _lastSubmitted!.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _buildResult(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Row(children: [
      Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
      const Spacer(),
      if (trailing != null) trailing,
    ]);
  }

  /// "N rolls" tile — tapping expands the list INLINE (no popup).
  Widget _buildCounter() {
    final radius = BorderRadius.vertical(
        top: const Radius.circular(10), bottom: Radius.circular(_listOpen ? 0 : 10));
    return Material(
      color: const Color(0xFFF7F9FF),
      borderRadius: radius,
      child: InkWell(
        key: const Key('rollCounter'),
        onTap: () => setState(() {
          _listOpen = !_listOpen;
          if (!_listOpen) _openRollKey = null;
        }),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDBE4F3)),
            borderRadius: radius,
          ),
          child: Row(children: [
            _Chip(text: '$_count', color: kBrandColor, fg: Colors.white, key: const Key('rollCount')),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${_count == 1 ? 'roll' : 'rolls'} in this shipment — not yet submitted',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
            ),
            Icon(_listOpen ? Icons.expand_less : Icons.expand_more, color: kBrandColor),
          ]),
        ),
      ),
    );
  }

  Widget _buildRollList() {
    return Container(
      key: const Key('rollList'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFCFF),
        border: Border(
          left: BorderSide(color: Color(0xFFDBE4F3)),
          right: BorderSide(color: Color(0xFFDBE4F3)),
          bottom: BorderSide(color: Color(0xFFDBE4F3)),
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Tap a roll to edit or remove it', style: TextStyle(fontSize: 13, color: Colors.black54))),
          TextButton.icon(
            key: const Key('collapseListButton'),
            onPressed: () => setState(() { _listOpen = false; _openRollKey = null; }),
            icon: const Icon(Icons.expand_less, size: 20),
            label: const Text('Collapse'),
          ),
        ]),
        if (_rolls.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No rolls yet — scan the first roll below.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          ),
        ..._rolls.asMap().entries.map((e) => _rollTile(e.key + 1, e.value)),
      ]),
    );
  }

  Widget _rollTile(int n, _ShipRoll r) {
    final open = _openRollKey == r.key;
    final err = r.serverError;
    return Container(
      key: Key('rollRow-${r.rollId}'),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: err != null ? const Color(0xFFFFF5F5) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: err != null ? const Color(0xFFE57373) : Colors.black12),
      ),
      child: Column(children: [
        InkWell(
          key: Key('rollRowHead-${r.rollId}'),
          onTap: () => setState(() => _openRollKey = open ? null : r.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
            child: Row(children: [
              SizedBox(width: 26, child: Text('$n', style: const TextStyle(fontSize: 13, color: Colors.black54))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.rollId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.black87)),
                  Text('${r.materialType ?? '—'} / ${r.basisWeight ?? '—'} / ${r.width == null ? '—' : '${r.width}"'}'
                      '  ·  L ${_fmt(r.length)}  ·  W ${_fmt(r.weight)}${r.notes.isEmpty ? '' : '  ·  📝'}',
                      style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  if (err != null)
                    Text('⚠ $err', style: const TextStyle(fontSize: 13, color: Color(0xFFC62828), fontWeight: FontWeight.bold)),
                ]),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: kBrandColor),
            ]),
          ),
        ),
        if (open) _rollEditor(r),
      ]),
    );
  }

  /// Editable details of one unsubmitted roll — length, weight, notes and the
  /// header values it carries — plus Remove. All local.
  Widget _rollEditor(_ShipRoll r) {
    const numType = TextInputType.numberWithOptions(decimal: true);
    List<String> withCurrent(List<String> items, String? v) =>
        (v == null || items.contains(v)) ? items : [...items, v];
    InputDecoration deco(String label) => InputDecoration(
        labelText: label, border: const OutlineInputBorder(), isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10));
    return Container(
      key: Key('rollEditor-${r.rollId}'),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12))),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('edit-length-${r.key}'),
              initialValue: r.length == null ? '' : _fmt(r.length),
              keyboardType: numType,
              decoration: deco('Length (ft)'),
              onChanged: (v) {
                final t = v.trim();
                if (t.isNotEmpty && double.tryParse(t) == null) return;
                _editRoll(r, () => r.length = t.isEmpty ? null : double.tryParse(t));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              key: ValueKey('edit-weight-${r.key}'),
              initialValue: r.weight == null ? '' : _fmt(r.weight),
              keyboardType: numType,
              decoration: deco('Weight (lbs)'),
              onChanged: (v) {
                final t = v.trim();
                if (t.isNotEmpty && double.tryParse(t) == null) return;
                _editRoll(r, () => r.weight = t.isEmpty ? null : double.tryParse(t));
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('edit-notes-${r.key}'),
          initialValue: r.notes,
          decoration: deco('Notes'),
          onChanged: (v) => _editRoll(r, () => r.notes = v.trim()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          // key carries the value so an interlock change (Crepe) re-seeds the field
          key: ValueKey('edit-material-${r.key}-${r.materialType}'),
          initialValue: r.materialType,
          isExpanded: true,
          decoration: deco('Material Type'),
          items: withCurrent(_materialTypes, r.materialType)
              .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => _editRoll(r, () {
            r.materialType = v;
            if (v == 'Crepe') r.basisWeight = 'Crepe';
          }),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('edit-basis-${r.key}-${r.basisWeight}'),
              initialValue: r.basisWeight,
              isExpanded: true,
              decoration: deco('Basis Weight'),
              items: withCurrent(_basisWeights, r.basisWeight)
                  .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => _editRoll(r, () {
                r.basisWeight = v;
                if (v == 'Crepe') r.materialType = 'Crepe';
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('edit-width-${r.key}-${r.width}'),
              initialValue: r.width,
              isExpanded: true,
              decoration: deco('Width (in)'),
              items: withCurrent(_widths, r.width)
                  .map((m) => DropdownMenuItem(value: m, child: Text('$m"'))).toList(),
              onChanged: (v) => _editRoll(r, () => r.width = v),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton.icon(
            key: Key('removeRoll-${r.rollId}'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFE57373))),
            onPressed: () => _removeRoll(r),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove from shipment'),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => setState(() => _openRollKey = null),
            child: const Text('Done'),
          ),
        ]),
      ]),
    );
  }

  Widget _buildResult() {
    final rows = _lastSubmitted!;
    final live = rows.where((r) => !r.undone).length;
    final at = _lastSubmittedAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Submitted — $live ${live == 1 ? 'roll' : 'rolls'} received',
          trailing: Text(
              '${_lastVendor ?? ''}${_lastPo == null ? '' : ' · PO $_lastPo'}'
              '${at == null ? '' : ' · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}',
              style: const TextStyle(fontSize: 13, color: Colors.black54))),
      ...rows.asMap().entries.map((e) => _resultRow(e.key + 1, e.value)),
    ]);
  }

  Widget _resultRow(int n, _ShipRoll r) {
    final muted = TextStyle(fontSize: 13, color: r.undone ? Colors.black38 : Colors.black54,
        decoration: r.undone ? TextDecoration.lineThrough : null);
    return Container(
      key: Key('resultRow-${r.rollId}'),
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
                '  ·  L ${_fmt(r.length)}  ·  W ${_fmt(r.weight)}', style: muted),
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
          if (val == null) { setState(() => _selectedVendor = null); _persistDraft(); return; }
          setState(() => _selectedVendor = val.split(' — ')[0]);
          _persistDraft();
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
