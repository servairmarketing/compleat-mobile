// S012: adding a roll without the shipment header shows the validation dialog (rev 2).
//
// Roll ID is REQUIRED; Vendor / Material Type / Basis Weight / Width are
// required too. Enter on Weight with an empty header must be blocked at the
// client gate in _addRoll() before anything is added or sent.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S012: Enter on Weight with empty header shows the validation dialog',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      // Only a Roll ID, no header — then Enter on Weight (the add gesture).
      await $(#rollIdField).enterText('RCV-MISSING-${DateTime.now().millisecondsSinceEpoch}');
      await $(#weightField).tap();
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pumpAndSettle();

      // (a) UI: the shared validation dialog lists the missing header fields.
      expect(find.textContaining('Vendor is required'), findsOneWidget,
          reason: 'Dialog should name the missing header fields');

      // (b) negative: nothing added, Submit disabled, still on Receive.
      expect($(#rollCount).$('0'), findsOneWidget);
      expect($(#messageBannerSuccess), findsNothing);
      expect($(#rollIdField), findsOneWidget,
          reason: 'Receive screen should still be on top after a blocked add');
    },
  );
}
