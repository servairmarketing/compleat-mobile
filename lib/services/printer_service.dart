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

  static Future<String> printParentOnlyLabel({
    required String parentId,
    int quantity = 1,
    String? printerIp,
  }) async {
    try {
      final ip = printerIp ?? await getPrinterIp();
      if (ip.isEmpty) return 'ERROR: No printer IP configured';
      if (parentId.trim().isEmpty) return 'ERROR: Parent ID is required';
      final result = await _channel.invokeMethod<String>('printParentOnlyLabel', {
        'parentId': parentId,
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

  /// Translates a raw printer result string into a friendly, non-technical
  /// message suitable for an operator. Returns `null` when [result] indicates
  /// success (i.e. it has no `ERROR` prefix), so callers can branch on null.
  ///
  /// Shared by every screen that prints so a failed print never surfaces a
  /// raw socket error like `EHOSTUNREACH ... socketConnected=false`.
  static String? friendlyPrintError(String result) {
    if (!result.startsWith('ERROR')) return null;
    final lower = result.toLowerCase();
    if (lower.contains('no printer ip')) {
      return 'No printer is configured. Set the printer IP in Printer Settings.';
    }
    if (lower.contains('ehostunreach') ||
        lower.contains('unreachable') ||
        lower.contains('socket') ||
        lower.contains('econnrefused') ||
        lower.contains('connection refused') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('no route') ||
        lower.contains('network') ||
        lower.contains('connect') ||
        lower.contains('no response')) {
      return 'Printer not reachable — check you’re on the warehouse network. '
          'You can print later.';
    }
    if (lower.contains('iprint') || lower.contains('brother')) {
      return 'Could not reach the printer. Make sure the Brother iPrint&Label '
          'app is installed and you’re on the warehouse network.';
    }
    return 'Label could not be printed. Please try again, or print it later.';
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
