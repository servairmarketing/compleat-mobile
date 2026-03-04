import 'dart:io';
import 'dart:typed_data';

class PrinterService {
  static Future<bool> printLabel({
    required String printerIp,
    required String productId,
    required String productName,
    required String parentRollId,
    int quantity = 1,
  }) async {
    try {
      for (int i = 0; i < quantity; i++) {
        final socket = await Socket.connect(printerIp, 9100,
            timeout: const Duration(seconds: 5));
        final data = _buildLabel(productId, productName, parentRollId);
        socket.add(data);
        await socket.flush();
        await socket.close();
        if (quantity > 1) await Future.delayed(const Duration(milliseconds: 500));
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static Uint8List _buildLabel(String productId, String productName, String parentRollId) {
    // ESC/P commands for Brother QL-1110NWBc
    // Using raster mode for label printing
    final List<int> commands = [];

    // Initialize
    commands.addAll([0x1B, 0x40]); // ESC @ - Initialize

    // Set to raster mode
    commands.addAll([0x1B, 0x69, 0x61, 0x01]); // Switch to raster mode

    // Print information command
    commands.addAll([0x1B, 0x69, 0x7A,
      0x84, 0x00, 0x3E, 0x00, // media type, width 62mm
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]);

    // Text content as plain ESC/P
    final textData = '\x1B\x40'; // Init
    commands.addAll(textData.codeUnits);

    // Product name line
    final line1 = '$productName\n';
    commands.addAll(line1.codeUnits);

    // Product ID line  
    final line2 = 'ID: $productId\n';
    commands.addAll(line2.codeUnits);

    // Parent roll line
    final line3 = 'Parent: $parentRollId\n';
    commands.addAll(line3.codeUnits);

    // Form feed / print
    commands.add(0x0C);

    return Uint8List.fromList(commands);
  }
}
