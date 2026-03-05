import 'package:url_launcher/url_launcher.dart';

class PrinterService {
  // Launch Brother iPrint&Label app via Android intent
  static Future<bool> printLabel({
    required String productId,
    required String productName,
    required String parentRollId1,
    String? parentRollId2,
    int quantity = 1,
  }) async {
    try {
      final parentText = parentRollId2 != null && parentRollId2.isNotEmpty
          ? '$parentRollId1 / $parentRollId2'
          : parentRollId1;

      // Brother iPrint&Label deep link
      // Format: brother-iprint-label://print?...
      final params = Uri.encodeComponent(
        'productId=$productId&productName=$productName&parent=$parentText&qty=$quantity'
      );
      final uri = Uri.parse('brother-iprint-label://print?$params');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }

      // Fallback: try generic Android intent for Brother app
      final intentUri = Uri.parse(
        'intent://print#Intent;scheme=brother-iprint-label;package=com.brother.ptouch.iprintandlabel;end'
      );
      if (await canLaunchUrl(intentUri)) {
        await launchUrl(intentUri, mode: LaunchMode.externalApplication);
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
