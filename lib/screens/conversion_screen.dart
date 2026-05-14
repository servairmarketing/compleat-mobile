import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/field_focus.dart';
import '../services/form_state_cache.dart';
import '../services/scan_dedupe.dart';
import '../widgets/two_parent_scan_fields.dart';
import 'validation_dialog.dart';

class ConversionScreen extends StatefulWidget {
  const ConversionScreen({super.key});
  @override
  State<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends State<ConversionScreen> with ScanDedupe {
  // ── Source identification ─────────────────────────────────────────
  // The source is an existing CHILD roll. Operator scans its composite
  // label(s) to identify it. Single-parent sources need one scan;
  // two-parent (splice) sources need two paired scans (same product,
  // different parents).
  bool _sourceTwoParent = false;
  String? _pendingSourceFirstScan;
  final _sourceScanController = TextEditingController();
  final _sourceScanFocus = FocusNode();
  bool _findingSource = false;
  Map<String, dynamic>? _sourceData;

  // ── Source status (Production or Finished — never In Stock) ──────
  String _sourceStatus = '';

  // ── New rolls being produced ─────────────────────────────────────
  // Each scan = one new physical child roll. All scans in a batch must
  // share the same product_id (locked on the first successful scan).
  final _newRollScanController = TextEditingController();
  final _newRollScanFocus = FocusNode();
  String? _newProductId;
  String? _newProductName;
  int _newRollsCount = 0;

  final _notesController = TextEditingController();
  final _notesFocus = FocusNode();

  bool _submitting = false;
  String? _message;
  bool _messageSuccess = false;

  List<Map> _products = [];
  bool _loadingProducts = false;

  final _scrollController = ScrollController();

  // Bug #14 — in-memory form-state cache key for this screen.
  static const _cacheKey = 'conversion';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    // Bug #14 — restore any in-progress entry preserved on nav-away.
    final snap = FormStateCache.read(_cacheKey);
    if (snap != null) {
      _sourceTwoParent = snap['sourceTwoParent'] ?? false;
      _sourceData = snap['sourceData'];
      _sourceStatus = snap['sourceStatus'] ?? '';
      _newProductId = snap['newProductId'];
      _newProductName = snap['newProductName'];
      _newRollsCount = snap['newRollsCount'] ?? 0;
      _notesController.text = snap['notes'] ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sourceScanFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Bug #14 — snapshot current entry before disposing controllers.
    // In-memory only — never persisted to disk.
    FormStateCache.write(_cacheKey, {
      'sourceTwoParent': _sourceTwoParent,
      'sourceData': _sourceData,
      'sourceStatus': _sourceStatus,
      'newProductId': _newProductId,
      'newProductName': _newProductName,
      'newRollsCount': _newRollsCount,
      'notes': _notesController.text,
    });
    _sourceScanController.dispose();
    _sourceScanFocus.dispose();
    _newRollScanController.dispose();
    _newRollScanFocus.dispose();
    _notesController.dispose();
    _notesFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    final res = await ApiService.get('/masters/products');
    if (res['records'] != null) {
      await LocalDb.cacheMasters('products', jsonEncode(res['records']));
      setState(() => _products = List<Map>.from(res['records']));
    } else {
      final cached = await LocalDb.getCachedMasters('products');
      if (cached != null) setState(() => _products = List<Map>.from(jsonDecode(cached)));
    }
    setState(() => _loadingProducts = false);
  }

  void _showMessage(String msg, bool success) {
    setState(() { _message = msg; _messageSuccess = success; });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  // Composite parser: split on the LAST hyphen so product IDs that
  // contain their own hyphens (e.g. "BSR-637800-T7Q5M21182A") work.
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

  // ── Source scan handler ──────────────────────────────────────────
  // Single-parent source scan handler. Two-parent source uses
  // _onSourceTwoParentPair via the shared TwoParentScanFields widget.
  Future<void> _handleSourceScan(String raw) async {
    if (raw.trim().isEmpty) return;
    final p = _parseComposite(raw);
    if (p == null) {
      _sourceScanController.clear();
      _pendingSourceFirstScan = null;
      if (mounted) _sourceScanFocus.requestFocus();
      _showMessage('Invalid composite barcode. Expected Product-Parent format.', false);
      return;
    }
    await _findSource(p.productId, [p.parentId]);
  }

  // Bug #15 — two-parent source pair handler. Receives the two raw composite
  // scans from the shared TwoParentScanFields widget; runs the same
  // validation the old single-field state machine did.
  Future<void> _onSourceTwoParentPair(String scan1, String scan2) async {
    final p1 = _parseComposite(scan1);
    final p2 = _parseComposite(scan2);
    if (p1 == null || p2 == null) {
      _showMessage('Invalid composite barcode. Expected Product-Parent format.', false);
      return;
    }
    if (p1.productId != p2.productId) {
      _showMessage('Both source labels must be from the same product roll.', false);
      return;
    }
    if (p1.parentId == p2.parentId) {
      _showMessage('Both labels are from the same parent. Scan one label per parent.', false);
      return;
    }
    await _findSource(p1.productId, [p1.parentId, p2.parentId], fromTwoParent: true);
  }

  Future<void> _findSource(String productId, List<String> parentIds,
      {bool fromTwoParent = false}) async {
    setState(() => _findingSource = true);
    final qs = parentIds.join(',');
    final res = await ApiService.get(
      '/conversion/find_source?product_id=${Uri.encodeQueryComponent(productId)}'
      '&parent_roll_ids=${Uri.encodeQueryComponent(qs)}',
    );
    setState(() => _findingSource = false);

    if (res['found'] != true || res['source'] == null) {
      _sourceScanController.clear();
      setState(() => _pendingSourceFirstScan = null);
      _showMessage('No in-stock source roll found for $productId from parent(s) ${parentIds.join(", ")}.', false);
      // In two-parent mode the TwoParentScanFields widget owns + restores focus.
      if (mounted && !fromTwoParent) _sourceScanFocus.requestFocus();
      return;
    }
    setState(() {
      _sourceData = Map<String, dynamic>.from(res['source']);
      _pendingSourceFirstScan = null;
    });
    _sourceScanController.clear();
    HapticFeedback.mediumImpact();
    // Bug #11 — brief delay before advancing to the new-roll scan field.
    FieldFocus.advance(context, target: _newRollScanFocus);
  }

  void _resetSource() {
    setState(() {
      _sourceData = null;
      _pendingSourceFirstScan = null;
      _sourceStatus = '';
      _newProductId = null;
      _newProductName = null;
      _newRollsCount = 0;
    });
    _sourceScanController.clear();
    _newRollScanController.clear();
    if (mounted) _sourceScanFocus.requestFocus();
  }

  // ── New-roll scan handler ────────────────────────────────────────
  Future<void> _handleNewRollScan(String raw) async {
    if (raw.trim().isEmpty) return;
    void reject(String msg) {
      _newRollScanController.clear();
      _showMessage(msg, false);
      if (mounted) _newRollScanFocus.requestFocus();
    }
    if (_sourceData == null) {
      reject('Identify the source roll before scanning new rolls.');
      return;
    }
    final parsed = _parseComposite(raw);
    if (parsed == null) {
      reject('Invalid composite barcode. Expected Product-Parent format.');
      return;
    }
    final pid = parsed.productId;
    final parent = parsed.parentId;

    final product = _products.firstWhere(
      (p) => p['product_id']?.toString() == pid,
      orElse: () => {},
    );
    if (product.isEmpty) {
      reject('Product $pid not found in product master.');
      return;
    }

    // All new-roll scans in one batch must share the same product_id.
    if (_newProductId != null && _newProductId != pid) {
      reject('All new rolls in one conversion must be the same product. Already scanned: $_newProductId.');
      return;
    }

    // Material / basis-weight / width / length compatibility against source.
    final srcMt = _sourceData!['material_type']?.toString() ?? '';
    final srcBw = _sourceData!['basis_weight']?.toString() ?? '';
    final srcW = double.tryParse(_sourceData!['width']?.toString() ?? '') ?? 0.0;
    final srcLen = double.tryParse(_sourceData!['length']?.toString() ?? '') ?? 0.0;
    final pMt = product['material_type']?.toString() ?? '';
    final pBw = product['basis_weight']?.toString() ?? '';
    final pW = double.tryParse(product['width']?.toString() ?? '') ?? 0.0;
    final pLen = double.tryParse(product['length']?.toString() ?? '') ?? 0.0;

    if (srcMt.isNotEmpty && pMt.isNotEmpty && pMt != srcMt) {
      reject('Material mismatch: source is $srcMt but new product $pid is $pMt.');
      return;
    }
    if (srcBw.isNotEmpty && pBw.isNotEmpty && pBw != srcBw) {
      reject('Basis weight mismatch: source is $srcBw lbs but new product $pid requires $pBw lbs.');
      return;
    }
    if (srcW > 0 && pW > 0) {
      if (pW > srcW) {
        reject('Width mismatch: new product $pid width ${pW}" exceeds source width ${srcW}".');
        return;
      }
      if (pW < srcW) {
        final ok = await _confirmNarrowerWidth(srcW, pW, pid);
        if (!ok) {
          _newRollScanController.clear();
          if (mounted) _newRollScanFocus.requestFocus();
          return;
        }
      }
    }
    if (srcLen > 0 && pLen > 0 && pLen > srcLen) {
      reject('Length mismatch: new product $pid length ${pLen} exceeds source length ${srcLen} — conversion does not splice.');
      return;
    }

    // Parent must be one of the source's parents (label was pre-printed
    // via Label Printing tab using source's parent IDs).
    final srcParents = (_sourceData!['parent_roll_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    if (!srcParents.contains(parent)) {
      reject('Scanned label parent $parent is not one of source parents ${srcParents.join(", ")}.');
      return;
    }

    setState(() {
      _newProductId = pid;
      _newProductName = product['product_name']?.toString() ?? pid;
      _newRollsCount += 1;
    });
    _newRollScanController.clear();
    HapticFeedback.lightImpact();
    if (mounted) _newRollScanFocus.requestFocus();
  }

  Future<bool> _confirmNarrowerWidth(double srcW, double prodW, String productId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm narrower new roll'),
        content: Text('Scanned product $productId width is ${prodW}" but source width is ${srcW}". Are you sure you want to add this new roll?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes, add')),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Submit ───────────────────────────────────────────────────────
  Future<void> _submitConversion() async {
    // Bug #12 — if the operator typed a composite into the new-roll scan
    // field without pressing Enter, treat it as a final scan attempt before
    // validating. (The source scan field has no submit button — a scan IS
    // its only action — so there is no unprocessed-text path there.)
    if (_sourceData != null && _newRollScanController.text.trim().isNotEmpty) {
      await _handleNewRollScan(_newRollScanController.text);
      if (!mounted) return;
    }

    final issues = <String>[];
    if (_sourceData == null) issues.add('Source roll must be identified first');
    if (_sourceStatus.isEmpty) issues.add('Source status must be Production or Finished');
    if (_newProductId == null || _newRollsCount < 1) {
      issues.add('At least one new roll must be scanned');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }

    setState(() => _submitting = true);
    final payload = {
      'source_roll_id': _sourceData!['doc_id'] ?? _sourceData!['roll_id'],
      'source_status': _sourceStatus,
      'new_product_id': _newProductId,
      'quantity': _newRollsCount,
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/conversion/submit', payload);
    setState(() => _submitting = false);

    if (res['success'] == true) {
      _showMessage('Conversion submitted! New roll ${res['new_child_id'] ?? ''} created.', true);
      _clearForm();
    } else {
      _showMessage(res['detail']?.toString() ?? 'Error submitting conversion.', false);
    }
  }

  void _clearForm() {
    setState(() {
      _sourceTwoParent = false;
      _sourceData = null;
      _pendingSourceFirstScan = null;
      _sourceStatus = '';
      _newProductId = null;
      _newProductName = null;
      _newRollsCount = 0;
    });
    _sourceScanController.clear();
    _newRollScanController.clear();
    _notesController.clear();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sourceScanFocus.requestFocus();
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Conversion',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _loadingProducts
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
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSourceSection(),
                        if (_sourceData != null) ...[
                          const SizedBox(height: 16),
                          _buildSourceStatusSection(),
                        ],
                        if (_sourceData != null && _sourceStatus.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildNewRollsSection(),
                        ],
                        if (_sourceData != null) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _notesController,
                            focusNode: _notesFocus,
                            keyboardType: TextInputType.multiline,
                            maxLines: 3,
                            minLines: 1,
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (_sourceData != null && _sourceStatus.isNotEmpty && _newRollsCount > 0)
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              key: const Key('submitConversionButton'),
                              onPressed: _submitting ? null : _submitConversion,
                              icon: _submitting
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.swap_horiz, size: 24),
                              label: Text(_submitting ? 'Submitting...' : 'Submit Conversion',
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
                            onPressed: _clearForm,
                            child: const Text('Clear', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSourceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SOURCE ROLL',
            style: TextStyle(color: Colors.black54, fontSize: 12,
                letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_sourceData == null) ...[
          Card(
            color: _sourceTwoParent ? Colors.orange[50] : Colors.blue[50],
            child: SwitchListTile(
              key: const Key('sourceTwoParentToggle'),
              title: Text(
                _sourceTwoParent ? 'Two-parent source (splice)' : 'Single-parent source',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _sourceTwoParent
                    ? 'Scan BOTH composite labels to identify the splice source roll'
                    : 'Scan ONE composite label to identify the source roll',
              ),
              value: _sourceTwoParent,
              activeColor: Colors.orange[800],
              onChanged: _findingSource ? null : (v) => setState(() {
                _sourceTwoParent = v;
                _pendingSourceFirstScan = null;
                _sourceScanController.clear();
              }),
            ),
          ),
          const SizedBox(height: 12),
          // Bug #15 — two-parent source shows TWO always-visible scan fields
          // via the shared widget; single-parent keeps the one composite
          // field.
          if (_sourceTwoParent)
            TwoParentScanFields(
              key: const Key('sourceTwoParentScan'),
              firstFieldFocusNode: _sourceScanFocus,
              enabled: !_findingSource,
              onPair: _onSourceTwoParentPair,
              field1Label: 'Scan source label 1 of 2',
              field2Label: 'Scan source label 2 of 2',
            )
          else
            TextField(
              key: const Key('sourceScanField'),
              controller: _sourceScanController,
              focusNode: _sourceScanFocus,
              autofocus: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 18),
              enabled: !_findingSource,
              decoration: InputDecoration(
                labelText: 'Scan source composite barcode',
                hintText: 'Scan here...',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                prefixIcon: _findingSource
                    ? const Padding(padding: EdgeInsets.all(14),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : const Icon(Icons.qr_code_scanner, size: 28),
              ),
              // Bug #17 — onSubmitted skips the onChanged/onSubmitted
              // double-fire; onChanged triggers only on a scan terminator.
              onSubmitted: (v) {
                if (!isDuplicateScan(v)) _handleSourceScan(v);
              },
              onChanged: (v) {
                final fired = v.contains('\n') || v.contains('\r');
                debugScan('sourceScan', v, fired);
                if (fired) { recordScan(v); _handleSourceScan(v); }
              },
            ),
        ] else ...[
          _sourceDetailsCard(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _resetSource,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset source roll'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sourceDetailsCard() {
    final s = _sourceData!;
    final parents = (s['parent_roll_ids'] as List?)
            ?.map((e) => e.toString())
            .join(' + ') ??
        '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[300]!, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 22),
              const SizedBox(width: 8),
              const Text('Source identified',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          _sourceRow('Product', '${s['product_id'] ?? '—'}'
              '${(s['product_name']?.toString().isNotEmpty == true) ? ' — ${s['product_name']}' : ''}'),
          _sourceRow('Material', s['material_type']?.toString()),
          _sourceRow('Basis Weight', s['basis_weight'] != null && s['basis_weight'].toString().isNotEmpty
              ? '${s['basis_weight']} lbs' : null),
          _sourceRow('Width', s['width'] != null && s['width'].toString().isNotEmpty
              ? '${s['width']}"' : null),
          _sourceRow('Length', s['length']?.toString()),
          _sourceRow('Parent(s)', parents),
          _sourceRow('Available qty', s['quantity']?.toString()),
        ],
      ),
    );
  }

  Widget _sourceRow(String label, String? value) {
    final v = (value == null || value.isEmpty) ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110,
              child: Text('$label:', style: const TextStyle(fontSize: 13, color: Colors.black54))),
          Expanded(child: Text(v,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _buildSourceStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SOURCE STATUS *',
            style: TextStyle(color: Colors.black54, fontSize: 12,
                letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          _statusButton('production', '🟡 Production', Colors.orange[700]!),
          const SizedBox(width: 8),
          _statusButton('finished', '🔴 Finished', Colors.red[700]!),
        ]),
        const SizedBox(height: 4),
        Text(
          (_sourceData?['quantity'] is num && (_sourceData!['quantity'] as num).toInt() <= 1)
              ? 'Source quantity will reach 0 — status will be set to Finished automatically.'
              : 'A source used in production cannot remain in stock.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _statusButton(String status, String label, Color color) {
    final selected = _sourceStatus == status;
    return Expanded(
      child: GestureDetector(
        key: Key('sourceStatus${status[0].toUpperCase()}${status.substring(1)}'),
        onTap: () => setState(() => _sourceStatus = status),
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
                  color: selected ? color : Colors.grey[600])),
        ),
      ),
    );
  }

  Widget _buildNewRollsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('NEW ROLLS BEING PRODUCED',
            style: TextStyle(color: Colors.black54, fontSize: 12,
                letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFe8f0fe),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1a73e8), width: 2),
          ),
          child: Row(
            children: [
              Text('$_newRollsCount',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                      color: Color(0xFF1a73e8))),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Rolls Scanned',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(_newProductId == null
                      ? 'Scan first new roll below'
                      : 'Product: $_newProductId${_newProductName != null && _newProductName != _newProductId ? " — $_newProductName" : ""}',
                      style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('newRollScanField'),
          controller: _newRollScanController,
          focusNode: _newRollScanFocus,
          autofocus: false,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: _newProductId == null
                ? 'Scan first new roll composite barcode'
                : 'Scan another new roll (same product as $_newProductId)',
            hintText: 'Scan here...',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
          ),
          // Bug #17 — onSubmitted skips the onChanged/onSubmitted double-fire;
          // onChanged triggers only on a scan terminator.
          onSubmitted: (v) {
            if (!isDuplicateScan(v)) _handleNewRollScan(v);
          },
          onChanged: (v) {
            final fired = v.contains('\n') || v.contains('\r');
            debugScan('newRollScan', v, fired);
            if (fired) { recordScan(v); _handleNewRollScan(v); }
          },
        ),
      ],
    );
  }
}
