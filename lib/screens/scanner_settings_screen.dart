import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/scanner_status_service.dart';
import '../brand.dart';

/// Settings → Scanner (Joe's ruling 2026-09-25): the hardware key code the
/// app treats as the scan TRIGGER for "no-read = skip" on the Receive screen.
/// Default 563 (Joe's non-Zebra scanner). Not hard-coded: another brand — or
/// the TC22 — may report a different code, so this screen shows the LAST KEY
/// SEEN live (press the scan button here to read it) and lets the operator
/// save it. Zebra DataWedge scanner-status detection is unaffected.
class ScannerSettingsScreen extends StatefulWidget {
  const ScannerSettingsScreen({super.key});
  @override
  State<ScannerSettingsScreen> createState() => _ScannerSettingsScreenState();
}

class _ScannerSettingsScreenState extends State<ScannerSettingsScreen> {
  final _codeController = TextEditingController();
  StreamSubscription<ScannerEvent>? _sub;
  String _lastKey = '—';
  String _lastStatus = '—';
  int _current = kDefaultTriggerKeyCode;

  @override
  void initState() {
    super.initState();
    ScannerStatusService.instance.loadTriggerKeyCode().then((c) {
      if (!mounted) return;
      setState(() { _current = c; _codeController.text = '$c'; });
    });
    _sub = ScannerStatusService.instance.events.listen((e) {
      if (!mounted) return;
      if (e.isKey && e.repeat == 0) setState(() => _lastKey = e.toString());
      if (e.isStatus) setState(() => _lastStatus = e.toString());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = int.tryParse(_codeController.text.trim());
    if (code == null || code < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the key code as a whole number (e.g. 563).')));
      return;
    }
    await ScannerStatusService.instance.setTriggerKeyCode(code);
    if (!mounted) return;
    setState(() => _current = code);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan-trigger key code saved: $code')));
  }

  Future<void> _resetDefault() async {
    _codeController.text = '$kDefaultTriggerKeyCode';
    await _save();
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('SCAN-TRIGGER KEY (NO-READ SKIP)',
                style: TextStyle(color: Colors.black54, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text(
              'On the Receive screen, pressing the scan button with nothing to read moves the cursor '
              'to the next field (like Enter). The app recognises the scan button by its hardware key '
              'code. Press the scan button now to see the code this device sends, then save it.',
              style: TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 18),
            Container(
              key: const Key('scannerLastKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Last key seen: $_lastKey', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Last scanner status (Zebra DataWedge): $_lastStatus',
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ]),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('scannerTriggerKeyCode'),
              controller: _codeController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Scan-trigger key code',
                helperText: 'Currently in use: $_current · default $kDefaultTriggerKeyCode',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    key: const Key('scannerSaveKeyCode'),
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: const Key('scannerResetKeyCode'),
                  onPressed: _resetDefault,
                  child: Text('Default ($kDefaultTriggerKeyCode)'),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            const Text(
              'Zebra devices (TC22) also report scanner status through DataWedge; that path needs no '
              'setting here. If the scan button never shows a key code above, the DataWedge path is '
              'the one in use.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}
