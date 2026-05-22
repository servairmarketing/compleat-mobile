import 'package:flutter/material.dart';
import '../services/field_focus.dart';
import '../services/scan_dedupe.dart';

/// Bug #15 — two-parent scans use two separate, always-visible scan fields.
///
/// When a screen's two-parent toggle is ON, a child roll carries two
/// composite labels (one per parent). The old UX scanned both labels into a
/// single field sequentially, so the operator never saw label 1 once label 2
/// was being scanned. This widget shows BOTH fields at once:
///  - scanning into field 1 auto-advances (Bug #11 timing) to field 2;
///  - scanning into field 2 hands the raw pair to [onPair];
///  - once [onPair] completes, both fields clear and focus returns to field 1.
///
/// The widget is deliberately "dumb" about validation — each screen passes an
/// [onPair] callback that runs the same pairing/validation logic it used
/// before, so this is genuinely shared code, not copy-paste per screen.
class TwoParentScanFields extends StatefulWidget {
  /// Called with the two raw scan strings once both fields have a value.
  /// The screen runs its existing pair validation here.
  final Future<void> Function(String scan1, String scan2) onPair;

  /// Disables both fields (e.g. while a lookup is in flight).
  final bool enabled;

  /// Optional externally-owned focus node for field 1, so the host screen
  /// can move focus into this widget (e.g. after validating parent rolls).
  /// When null, the widget owns and disposes its own node.
  final FocusNode? firstFieldFocusNode;

  /// Bug #22 — whether to grab focus into scan field 1 when the widget first
  /// mounts. True is right when the scan field is the first input the
  /// operator needs (e.g. Conversion source, Annual Child stock-take). Set
  /// false when an earlier field (e.g. Parent Roll 1) should keep focus —
  /// the host screen then drives focus itself.
  final bool autofocusOnMount;

  /// Bug #24 — fires when the half-finished-splice state changes (label 1
  /// entered but the pair not yet committed). Lets the host screen tell a
  /// pending splice apart from "nothing scanned" when validating a submit.
  final ValueChanged<bool>? onPendingChanged;

  final String field1Label;
  final String field2Label;
  final String field1Hint;
  final String field2Hint;

  const TwoParentScanFields({
    super.key,
    required this.onPair,
    this.enabled = true,
    this.firstFieldFocusNode,
    this.autofocusOnMount = true,
    this.onPendingChanged,
    this.field1Label = 'Scan label 1 of 2',
    this.field2Label = 'Scan label 2 of 2',
    this.field1Hint = "Scan first parent's label",
    this.field2Hint = "Scan second parent's label",
  });

  @override
  State<TwoParentScanFields> createState() => _TwoParentScanFieldsState();
}

class _TwoParentScanFieldsState extends State<TwoParentScanFields> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _f2 = FocusNode();
  // Field-1 focus node: externally supplied (host screen owns it) or created
  // and owned here. Assigned in initState so it can read `widget`.
  late final FocusNode _f1;
  late final bool _ownsF1;
  bool _processing = false;
  // Bug #24 — last reported half-scan state (label 1 entered, pair not yet
  // committed), so onPendingChanged only fires on an actual transition.
  bool _pending = false;

  void _notifyPending() {
    final p = _c1.text.trim().isNotEmpty;
    if (p != _pending) {
      _pending = p;
      widget.onPendingChanged?.call(p);
    }
  }

  @override
  void initState() {
    super.initState();
    _ownsF1 = widget.firstFieldFocusNode == null;
    _f1 = widget.firstFieldFocusNode ?? FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocusOnMount) _f1.requestFocus();
    });
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    if (_ownsF1) _f1.dispose();
    _f2.dispose();
    super.dispose();
  }

  void _onField1Done() {
    if (_c1.text.trim().isEmpty) return;
    if (_c2.text.trim().isNotEmpty) {
      // Both already populated — go straight to the pair.
      _onField2Done();
      return;
    }
    // Bug #11 — brief delay before advancing so label 1 stays visible.
    FieldFocus.advance(context, target: _f2);
  }

  Future<void> _onField2Done() async {
    if (_processing) return;
    if (_c1.text.trim().isEmpty) {
      _f1.requestFocus();
      return;
    }
    if (_c2.text.trim().isEmpty) return;
    setState(() => _processing = true);
    try {
      await widget.onPair(_c1.text, _c2.text);
    } finally {
      if (mounted) {
        _c1.clear();
        _c2.clear();
        setState(() => _processing = false);
        _notifyPending();
        // Bug #33 — return focus to field 1, ready for the next pair scan.
        // Both fields are `enabled: !_processing`, so field 1 is still
        // disabled at this point — the `setState` above only SCHEDULES the
        // rebuild that re-enables it. Calling requestFocus() now would hit a
        // not-yet-focusable field and silently fail, leaving focus on
        // field 2. Defer it to after the rebuild lands so field 1 is
        // focusable when the request is made.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _f1.requestFocus();
        });
      }
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required Key fieldKey,
    required VoidCallback onDone,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      enabled: widget.enabled && !_processing,
      autofocus: false,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        prefixIcon: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      // Bug #17 — trigger only on an explicit scan terminator, never on a
      // length heuristic that could fire mid-burst and truncate the value.
      // The onChanged/onSubmitted double-fire is absorbed by _onField2Done's
      // `_processing` guard + post-pair clear (see below).
      onSubmitted: (_) => onDone(),
      onChanged: (v) {
        final fired = v.contains('\n') || v.contains('\r');
        debugScan('twoParentScan', v, fired);
        if (fired) onDone();
        // Bug #24 — keep the host informed of the half-scan state.
        _notifyPending();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField(
          controller: _c1,
          focusNode: _f1,
          label: widget.field1Label,
          hint: widget.field1Hint,
          fieldKey: const Key('twoParentScanField1'),
          onDone: _onField1Done,
        ),
        const SizedBox(height: 10),
        _buildField(
          controller: _c2,
          focusNode: _f2,
          label: widget.field2Label,
          hint: widget.field2Hint,
          fieldKey: const Key('twoParentScanField2'),
          onDone: _onField2Done,
        ),
      ],
    );
  }
}
