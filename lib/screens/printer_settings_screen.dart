import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/printer_service.dart';

enum PrinterStatus { checking, offline, ready, coverOpen, noPaper, paperJam, error }

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _ipController = TextEditingController();
  PrinterStatus _status = PrinterStatus.checking;
  bool _printing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('printer_ip') ?? '192.168.2.181';
    _startPolling();
  }

  void _startPolling() {
    _checkStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    setState(() => _status = PrinterStatus.checking);
    final ip = _ipController.text.trim();
    if (ip.isEmpty) { setState(() => _status = PrinterStatus.offline); return; }
    final statusStr = await PrinterService.getPrinterStatus(printerIp: ip);
    if (!mounted) return;
    setState(() {
      switch (statusStr) {
        case 'READY': _status = PrinterStatus.ready; break;
        case 'COVER_OPEN': _status = PrinterStatus.coverOpen; break;
        case 'NO_PAPER': _status = PrinterStatus.noPaper; break;
        case 'PAPER_JAM': _status = PrinterStatus.paperJam; break;
        case 'ERROR': _status = PrinterStatus.error; break;
        default: _status = PrinterStatus.offline;
      }
    });
  }

  Future<void> _saveIp() async {
    _pollTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', _ipController.text.trim());
    _startPolling();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Printer IP saved!'), backgroundColor: Colors.green));
  }

  Future<void> _testPrint() async {
    setState(() => _printing = true);
    final ip = _ipController.text.trim();
    final detail = await PrinterService.printLabel(
      productId: 'TEST-001', productName: 'Test Label',
      parentRollId1: 'TEST-ROLL', quantity: 1, printerIp: ip,
    );
    setState(() => _printing = false);
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(detail.startsWith('OK:') ? 'Print Sent' : 'Print Result'),
          content: SelectableText(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    switch (_status) {
      case PrinterStatus.ready: return Colors.green;
      case PrinterStatus.checking: return Colors.orange;
      case PrinterStatus.offline: return Colors.red;
      default: return Colors.orange;
    }
  }

  String get _statusText {
    switch (_status) {
      case PrinterStatus.ready: return 'Ready';
      case PrinterStatus.checking: return 'Checking...';
      case PrinterStatus.offline: return 'Offline';
      case PrinterStatus.coverOpen: return 'Cover Open';
      case PrinterStatus.noPaper: return 'No Paper';
      case PrinterStatus.paperJam: return 'Paper Jam';
      case PrinterStatus.error: return 'Printer Error';
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case PrinterStatus.ready: return Icons.check_circle;
      case PrinterStatus.checking: return Icons.sync;
      case PrinterStatus.offline: return Icons.cancel;
      default: return Icons.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Printer Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Brother QL-1110NWBc',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _statusColor, width: 2),
              ),
              child: Row(
                children: [
                  _status == PrinterStatus.checking
                    ? SizedBox(width: 28, height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3, color: _statusColor))
                    : Icon(_statusIcon, color: _statusColor, size: 28),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_statusText,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _statusColor)),
                      Text(_ipController.text.isEmpty ? 'No IP configured' : _ipController.text,
                        style: TextStyle(fontSize: 14, color: _statusColor.withOpacity(0.8))),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: _statusColor,
                    iconSize: 28,
                    onPressed: _checkStatus,
                    tooltip: 'Refresh status',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'Printer IP Address',
                hintText: '192.168.2.181',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print, size: 28),
                contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _saveIp,
                      icon: const Icon(Icons.save, size: 24),
                      label: const Text('Save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1a73e8), foregroundColor: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(height: 56,
                    child: OutlinedButton.icon(
                      onPressed: (_printing || _status != PrinterStatus.ready) ? null : _testPrint,
                      icon: _printing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print, size: 24),
                      label: Text(_printing ? 'Printing...' : 'Test Print',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How to find your printer IP:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Hold the feed button 3-4 seconds to print config page', style: TextStyle(fontSize: 15)),
                    Text('The IP address is printed on the config page', style: TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
