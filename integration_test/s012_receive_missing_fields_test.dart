// S012: submit with empty required fields shows validation banner.
//
// Roll ID is OPTIONAL on this screen (auto-generated server-side when
// blank). The validation gate is on Vendor / Material Type / Basis Weight.

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S012: submit with empty required fields shows validation banner',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      // No fields filled -- Roll ID is optional, but Vendor / Material /
      // Basis Weight are not. Submit should be blocked at the client
      // gate in _submit() before any API call is made.
      await $(#submitButton).tap();

      // (a) UI: error banner with the required-fields message. Match by
      // substring rather than exact text so a copy tweak won't break this.
      await $(#messageBannerError).waitUntilVisible(
        timeout: const Duration(seconds: 3),
      );
      expect(find.textContaining('are required'), findsOneWidget,
          reason: 'Banner should describe which fields are required');

      // (b) negative: no success banner, still on Receive screen.
      expect($(#messageBannerSuccess), findsNothing);
      expect($(#rollIdField), findsOneWidget,
          reason: 'Receive screen should still be on top after blocked submit');

      // (c) state: nothing typed in -- Roll ID field stays empty. Implicit
      // since we never entered any text.
    },
  );
}
