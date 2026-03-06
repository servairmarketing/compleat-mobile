import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _ipController = TextEditingController();
  bool _testing = false;
  String? _message;
  bool _messageSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('printer_ip') ?? '192.168.1.100';
  }

  Future<void> _saveIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', _ipController.text.trim());
    setState(() { _message = 'Printer IP saved!'; _messageSuccess = true; });
  }

  Future<void> _testPrint() async {
    setState(() { _testing = true; _message = null; });
    final ip = _ipController.text.trim();
    final success = await PrinterService.printLabel(
      productId: 'TEST-001',
      productName: 'Test Label',
      parentRollId1: 'TEST-ROLL',
      quantity: 1,
      printerIp: ip,
    );
    setState(() {
      _testing = false;
      _message = success ? 'Test print sent successfully!' : 'Print failed. Check IP and printer connection.';
      _messageSuccess = success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Brother QL-1110NWBc',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the IP address of your Brother printer on the WiFi network.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'Printer IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print, size: 28),
                contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              ),
            ),
            const SizedBox(height: 24),
            if (_message != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _messageSuccess ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _messageSuccess ? Colors.green : Colors.red),
                ),
                child: Text(_message!,
                  style: TextStyle(
                    color: _messageSuccess ? Colors.green[800] : Colors.red[800],
                    fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _saveIp,
                      icon: const Icon(Icons.save, size: 24),
                      label: const Text('Save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1a73e8),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testPrint,
                      icon: _testing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print, size: 24),
                      label: Text(_testing ? 'Testing...' : 'Test Print',
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
                    Text('1. Print a network config page from the printer', style: TextStyle(fontSize: 15)),
                    Text('2. Or check your router\'s connected devices', style: TextStyle(fontSize: 15)),
                    Text('3. Or use the Brother iPrint&Label app to find it', style: TextStyle(fontSize: 15)),
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
