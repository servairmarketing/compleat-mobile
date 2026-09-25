import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/scanner_status_service.dart';
import '../brand.dart';

/// Settings → Scanner (Joe's ruling 2026-09-25): the hardware key code the
/// app treats as the scan TRIGGER(S) for "no-read = skip" on the Receive screen.
/// Default {563, 564} — the two scan buttons of Joe's non-Zebra scanner (v1.0.78,
/// after 564 was found on his second button). Not hard-coded: another brand —
/// or the TC22 — may report other codes, so this screen shows the LAST KEY SEEN
/// live (press a scan button here to read it) and lets the operator add or
/// remove keys. Zebra DataWedge scanner-status detection is unaffected.
class ScannerSettingsScreen extends StatefulWidget {
  const ScannerSettingsScreen({super.key});
  @override
  State<ScannerSettingsScreen> createState() => _ScannerSettingsScreenState();
}

class _ScannerSettingsScreenState extends State<ScannerSettingsScreen> {
  final _codeController = TextEditingController();
  StreamSubscription<ScannerEvent>? _sub;
  void _onScannerChange() { if (mounted) setState(() {}); }

  ScannerStatusService get _svc => ScannerStatusService.instance;

  @override
  void initState() {
    super.initState();
    _svc.loadTriggerKeyCodes();   // repaints through `changes` when loaded
    // Subscribing (re)starts the platform stream if it is not alive; the
    // service keeps state, counters and last events (v1.0.77) — repaint on change.
    _sub = _svc.events.listen((_) {});
    _svc.changes.addListener(_onScannerChange);
  }

  @override
  void dispose() {
    _svc.changes.removeListener(_onScannerChange);
    _sub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addTyped() async {
    final code = int.tryParse(_codeController.text.trim());
    if (code == null || code < 0) {
      _toast('Enter the key code as a whole number (e.g. 563).');
      return;
    }
    await _add(code);
    _codeController.clear();
  }

  Future<void> _add(int code) async {
    if (_svc.triggerKeyCodes.contains(code)) {
      _toast('Key $code is already a scan-trigger key.');
      return;
    }
    await _svc.addTriggerKeyCode(code);
    _toast('Added scan-trigger key $code. Now: ${_svc.triggerKeysText}');
  }

  Future<void> _remove(int code) async {
    await _svc.removeTriggerKeyCode(code);
    _toast(_svc.triggerKeyCodes.isEmpty
        ? 'Removed key $code — no keys left, trigger-skip is OFF until you add one.'
        : 'Removed key $code. Now: ${_svc.triggerKeysText}');
  }

  Future<void> _resetDefaults() async {
    await _svc.resetTriggerKeyCodes();
    _toast('Scan-trigger keys reset to defaults: ${_svc.triggerKeysText}');
  }

  @override
  Widget build(BuildContext context) {
    final keys = _svc.triggerKeyCodes.toList()..sort();
    final last = _svc.lastKey;
    final lastCode = last?.keyCode;
    final canAddLast = lastCode != null && lastCode >= 0 && !_svc.triggerKeyCodes.contains(lastCode);
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Scanner Settings'),
        backgroundColor: kBrandColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SCAN-TRIGGER KEYS (NO-READ SKIP)',
                style: TextStyle(color: Colors.black54, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text(
              'On the Receive screen, pressing a scan button with nothing to read moves the cursor '
              'to the next field (like Enter). The app recognises the scan buttons by their hardware '
              'key codes — a device may have more than one button. Press a scan button now to see the '
              'code it sends, then add it.',
              style: TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 18),
            Container(
              key: const Key('scannerLastKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Last key seen: ${last ?? '—'}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (canAddLast) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('scannerAddLastKey'),
                    onPressed: () => _add(lastCode),
                    icon: const Icon(Icons.add),
                    label: Text('Add key $lastCode as a scan trigger'),
                  ),
                ],
                const SizedBox(height: 6),
                Text('Last scanner status (Zebra DataWedge): ${_svc.lastStatus ?? '—'}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 6),
                Text('Listener: ${_svc.stateText}',
                    key: const Key('scannerListenerState'),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                Text(_svc.countersText,
                    style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ]),
            ),
            const SizedBox(height: 18),
            Text('Scan-trigger keys in use: ${_svc.triggerKeysText}',
                key: const Key('scannerTriggerKeys'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in keys)
                  InputChip(
                    key: Key('scannerTriggerKey_$k'),
                    label: Text('$k', style: const TextStyle(fontSize: 16)),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    deleteButtonTooltipMessage: 'Remove key $k',
                    onDeleted: () => _remove(k),
                  ),
                if (keys.isEmpty)
                  const Text('No keys — trigger-skip is OFF. Add a key or reset to defaults.',
                      style: TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
              ],
            ),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const Key('scannerTriggerKeyCode'),
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Add a key code',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                  ),
                  onSubmitted: (_) => _addTyped(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  key: const Key('scannerSaveKeyCode'),
                  onPressed: _addTyped,
                  icon: const Icon(Icons.add),
                  label: const Text('Add', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                key: const Key('scannerResetKeyCode'),
                onPressed: _resetDefaults,
                child: Text('Reset to defaults (${(kDefaultTriggerKeyCodes.toList()..sort()).join(', ')})'),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Zebra devices (TC22) also report scanner status through DataWedge; that path needs no '
              'setting here. If a scan button never shows a key code above, the DataWedge path is '
              'the one in use.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}
