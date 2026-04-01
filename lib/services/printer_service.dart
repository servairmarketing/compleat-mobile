import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterService {
  static const _channel = MethodChannel('com.compleat/printer');

  static Future<String> getPrinterIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_ip') ?? '192.168.2.181';
  }

  static Future<bool> testConnection({required String printerIp}) async {
    try {
      final result = await _channel.invokeMethod<bool>('testConnection', {
        'printerIp': printerIp,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> getPrinterStatus({required String printerIp}) async {
    try {
      final result = await _channel.invokeMethod<String>('getPrinterStatus', {
        'printerIp': printerIp,
      });
      return result ?? 'OFFLINE';
    } on PlatformException {
      return 'OFFLINE';
    }
  }

  static Future<String> printLabel({
    required String productId,
    required String productName,
    required String parentRollId1,
    String? parentRollId2,
    int quantity = 1,
    String? printerIp,
  }) async {
    try {
      final ip = printerIp ?? await getPrinterIp();
      if (ip.isEmpty) return 'ERROR: No printer IP configured';
      final result = await _channel.invokeMethod<String>('printLabel', {
        'productId': productId,
        'productName': productName,
        'parentRollId1': parentRollId1,
        'parentRollId2': parentRollId2 ?? '',
        'quantity': quantity,
        'printerIp': ip,
      });
      return result ?? 'ERROR: No response from printer plugin';
    } on PlatformException catch (e) {
      return 'ERROR: ${e.message}';
    }
  }

  static Future<String> sendBlankTest({required String printerIp}) async {
    try {
      final result = await _channel.invokeMethod<String>('sendBlankTest', {
        'printerIp': printerIp,
      });
      return result ?? 'ERROR: No response from printer plugin';
    } on PlatformException catch (e) {
      return 'ERROR: ${e.message}';
    }
  }

  static Future<List<String>> discoverPrinters() async {
    try {
      final result = await _channel.invokeListMethod<String>('discoverPrinters');
      return result ?? [];
    } on PlatformException {
      return [];
    }
  }
}
