// parent_validation.dart — shared two-parent / splice validators (single source).
//
// 02_STANDARDS §2.13: any entry combining two parent rolls must enforce the SAME
// rules on client and server, and they must NOT be re-implemented per screen —
// that copy-paste pattern is exactly how Stock Take Initial Child shipped with no
// validation. This mirrors the backend validate_parent_set() (main.py) and the web
// validateParentSet() (public/validation.js) byte-for-byte in intent:
//   R1  distinct       — two parents must be different roll IDs  (ALWAYS enforced)
//   R2  exist          — every parent must resolve via lookupFn  (requireExist only)
//   R2b not consumed   — a consumed parent cannot be used        (requireExist only)
//   R3  material+basis — two parents must match on material_type AND basis_weight,
//                        compared only when BOTH parents resolve AND both values present
//
// requireExist (default true): when false (Stock Take Initial Child + Annual Child
// inline-create) an unknown parent is ALLOWED — a stock-take child can legitimately
// exist without a known parent (old/consumed/leftover stock, parent long gone). R2/R2b
// are then skipped; R1 still ALWAYS applies and R3 applies only when both parents
// resolve. Mirrors backend validate_parent_set(require_exist=False).
import 'package:flutter/services.dart';
import 'api_service.dart';

/// Forces an ID entry field to UPPERCASE as the operator types/scans (§2.14).
/// Wire onto EVERY roll-id / parent / scan field so what's shown matches what's
/// stored/looked-up — the mobile counterpart of web `IMSValidation.bindUpperCase`.
class UpperCaseRollIdFormatter extends TextInputFormatter {
  const UpperCaseRollIdFormatter();
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final up = newValue.text.toUpperCase();
    if (up == newValue.text) return newValue;
    // Preserve the caret/selection — only the case changed, not the length.
    return newValue.copyWith(text: up);
  }
}

/// Result of a parent-set validation: ok, or a single operator-facing message.
class ParentValidationResult {
  final bool ok;
  final String? error;
  const ParentValidationResult.ok()
      : ok = true,
        error = null;
  const ParentValidationResult.fail(this.error) : ok = false;
}

/// Looks up a roll by ID, returning its data map or null if not found.
/// Mirrors production_screen's _fetchParentRoll (handles both response shapes).
typedef RollLookup = Future<Map<String, dynamic>?> Function(String rollId);

class ParentValidation {
  /// Canonical form of any ID — roll IDs AND product IDs — per 02_STANDARDS §2.14:
  /// trimmed + UPPERCASE. IDs are case-insensitive (any case = same record), so
  /// normalize at EVERY write, lookup, and compare. This is the ONE mobile helper —
  /// never scatter inline .toUpperCase() that can drift. Mirrors backend
  /// normalize_roll_id() and web IMSValidation.normalizeRollId.
  static String normalizeRollId(String? value) => (value ?? '').trim().toUpperCase();

  /// Intent-revealing alias — product IDs share the same case-insensitive rule.
  static String normalizeProductId(String? value) => normalizeRollId(value);

  /// Composite barcode "ProductID-ParentID" -> record, or null if malformed.
  /// Split on the LAST hyphen: product IDs contain hyphens (e.g. BRK-607800),
  /// parent roll IDs don't. Byte-identical to the web parseComposite. BOTH halves
  /// are normalized to uppercase — they are IDs and must match storage/lookups.
  static ({String productId, String parentId})? parseComposite(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final i = v.lastIndexOf('-');
    if (i <= 0 || i >= v.length - 1) return null;
    final pid = normalizeProductId(v.substring(0, i));
    final parent = normalizeRollId(v.substring(i + 1));
    if (pid.isEmpty || parent.isEmpty) return null;
    return (productId: pid, parentId: parent);
  }

  /// Child roll display label (single source — §2.13, mirrors web
  /// IMSValidation.childDisplayLabel). A child roll's internal id is the opaque
  /// "CHILD-<product>-<timestamp>" string, meaningless to users; everywhere a child
  /// is shown it must read as product + parent(s), e.g. "BVR-696000 · T26B20025M".
  /// The internal id is kept only as a key/hover, NEVER as the visible label.
  /// Returns product·parent(s), or just the product when parents are unknown.
  static String childDisplayLabel(dynamic productId, dynamic parentRollIds) {
    final pid = (productId == null || productId.toString().isEmpty)
        ? '—'
        : productId.toString();
    final parents = <String>[];
    if (parentRollIds is List) {
      for (final p in parentRollIds) {
        if (p != null && p.toString().isNotEmpty) parents.add(p.toString());
      }
    }
    return parents.isEmpty ? pid : '$pid · ${parents.join(' + ')}';
  }

  /// True if a roll record is a child (by `type`, or a CHILD-… roll id).
  /// Accepts an untyped [Map] — several history detail records are `Map` (dynamic).
  static bool isChildRoll(Map? rec) {
    if (rec == null) return false;
    if (rec['type'] == 'child') return true;
    return (rec['roll_id']?.toString() ?? '').toUpperCase().startsWith('CHILD-');
  }

  /// User-facing label for any roll record: product·parent for a child, the
  /// natural roll id for a parent. Mirrors web IMSValidation.rollDisplayLabel.
  static String rollDisplayLabel(Map? rec) {
    if (rec == null) return '—';
    if (isChildRoll(rec)) {
      return childDisplayLabel(rec['product_id'], rec['parent_roll_ids']);
    }
    final rid = rec['roll_id']?.toString() ?? '';
    return rid.isEmpty ? '—' : rid;
  }

  /// Default roll lookup via GET /rolls/{id}. Returns null when not found.
  /// Normalizes the ID so a miscased reference resolves to the stored roll.
  static Future<Map<String, dynamic>?> defaultRollLookup(String rollId) async {
    final res = await ApiService.get('/rolls/${normalizeRollId(rollId)}');
    if (res['roll'] != null) return Map<String, dynamic>.from(res['roll']);
    if (res['roll_id'] != null) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Validate a parent-roll set (1 or 2 raw parent IDs). See file header for the
  /// rule set. [lookupFn] defaults to [defaultRollLookup] (GET /rolls/{id}).
  static Future<ParentValidationResult> validateParentSet(
    List<String> parentIds, {
    RollLookup? lookupFn,
    bool requireExist = true,
  }) async {
    final lookup = lookupFn ?? defaultRollLookup;
    // Canonicalize so R1 distinct, the lookup, and R3 compare are case-insensitive
    // — a parent created "T7Q5M21182A" referenced "t7q5m21182a" resolves to the
    // same roll instead of slotting in as unknown (which would skip R3).
    final ids = parentIds
        .map(normalizeRollId)
        .where((p) => p.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return const ParentValidationResult.fail('Parent Roll ID is required.');
    }

    // R1 — distinct (ALWAYS)
    if (ids.length == 2 && ids[0] == ids[1]) {
      return ParentValidationResult.fail(
          'The two parent rolls must be different (got ${ids[0]} twice).');
    }

    final rolls = <Map<String, dynamic>?>[];
    for (final id in ids) {
      final data = await lookup(id);
      // R2 — exists
      if (data == null) {
        if (requireExist) {
          return ParentValidationResult.fail(
              'Parent roll $id not found — enter it via Initial Stock Entry first.');
        }
        // Stock-take child: unknown parent allowed (old/leftover stock).
        rolls.add(null);
        continue;
      }
      // R2b — not consumed
      if (requireExist && (data['status']?.toString() ?? '') == 'consumed') {
        return ParentValidationResult.fail(
            'Parent roll $id has already been consumed and cannot be used.');
      }
      rolls.add(data);
    }

    // R3 — two parents must match on material_type AND basis_weight, only when
    // BOTH resolved and both values present.
    if (rolls.length == 2 && rolls[0] != null && rolls[1] != null) {
      final mt1 = rolls[0]!['material_type']?.toString() ?? '';
      final mt2 = rolls[1]!['material_type']?.toString() ?? '';
      if (mt1.isNotEmpty && mt2.isNotEmpty && mt1 != mt2) {
        return ParentValidationResult.fail(
            'Material type mismatch: ${ids[0]} is $mt1 but ${ids[1]} is $mt2. '
            'Both parent rolls must be the same material type.');
      }
      final bw1 = rolls[0]!['basis_weight']?.toString() ?? '';
      final bw2 = rolls[1]!['basis_weight']?.toString() ?? '';
      if (bw1.isNotEmpty && bw2.isNotEmpty && bw1 != bw2) {
        return ParentValidationResult.fail(
            'Basis weight mismatch: ${ids[0]} is $bw1 but ${ids[1]} is $bw2. '
            'Both parent rolls must have the same basis weight.');
      }
    }

    return const ParentValidationResult.ok();
  }
}
