import 'package:flutter/widgets.dart';

/// Bug #17 — composite-scan trigger hardening.
///
/// The old `v.length > 20` onChanged heuristic could fire the scan handler
/// mid-burst (before the scanner finished injecting the barcode), parsing a
/// truncated string. The fix is to trigger only on an explicit scan
/// terminator (`\n`/`\r`) — by definition the last thing the scanner sends —
/// plus the `onSubmitted` (Enter) path. Because both can fire for one
/// physical scan, [ScanDedupe] suppresses the duplicate.

/// Flip to true locally to trace scan-field onChanged events (value length +
/// whether the handler fired) when diagnosing scanner timing on hardware.
/// Leave false in committed builds.
const bool kScanDebug = false;

/// Debug trace for a scan-field onChanged event. No-op unless [kScanDebug].
void debugScan(String field, String value, bool fired) {
  if (kScanDebug) {
    final shown = value.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
    debugPrint('[SCAN] $field len=${value.length} fired=$fired value="$shown"');
  }
}

/// Idempotency guard so a single physical scan isn't counted twice when both
/// `onChanged` (terminator) and `onSubmitted` (Enter) fire for it.
///
/// Usage: the `onChanged` path calls [recordScan] then processes; the
/// `onSubmitted` path calls [isDuplicateScan] and skips processing if true.
/// `onChanged` never consults [isDuplicateScan], so genuinely rapid repeat
/// scans of an identical composite (each arriving via `onChanged`) are still
/// processed — only the trailing `onSubmitted` of the same event is dropped.
mixin ScanDedupe<T extends StatefulWidget> on State<T> {
  String? _lastScanValue;
  DateTime? _lastScanAt;

  /// Record that [raw] is being processed now (call from the onChanged path).
  void recordScan(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    _lastScanValue = v;
    _lastScanAt = DateTime.now();
  }

  /// True if [raw] duplicates a scan recorded within the last 500ms — call
  /// from the onSubmitted path to suppress the onChanged/onSubmitted
  /// double-fire of one physical scan.
  bool isDuplicateScan(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;
    if (_lastScanValue == v &&
        _lastScanAt != null &&
        DateTime.now().difference(_lastScanAt!) <
            const Duration(milliseconds: 500)) {
      return true;
    }
    return false;
  }
}
