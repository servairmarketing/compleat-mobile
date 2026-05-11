// S011: duplicate Roll ID rejected, form preserved.
//
// Backend assumption: parent roll TEST-PARENT-001 already exists in the
// test Firestore so the receive endpoint returns a duplicate-key error.

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S011: duplicate Roll ID rejected, form preserved',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      const dupId = 'TEST-PARENT-001';
      await $(#rollIdField).enterText(dupId);

      await $(#vendorDropdown).tap();
      await $('TESTVEND1').scrollTo().tap();

      await $(#poNumberField).enterText('PO-RCV-DUP');

      await $(#materialTypeDropdown).tap();
      await $(find.text('Virgin')).scrollTo().tap();

      await $(#basisWeightDropdown).tap();
      await $(find.text('24')).scrollTo().tap();

      await $(#widthDropdown).tap();
      await $(find.text('69')).scrollTo().tap();

      await $(#lengthField).enterText('50000');
      await $(#weightField).enterText('3000');

      await $(#submitButton).tap();

      // (a) UI: error banner appears.
      await $(#messageBannerError).waitUntilVisible(
        timeout: const Duration(seconds: 8),
      );

      // (b) negative: no success banner.
      expect($(#messageBannerSuccess), findsNothing);

      // (c) state: form NOT cleared -- typed Roll ID still on screen.
      expect(find.text(dupId), findsOneWidget,
          reason: 'Failed submit must preserve user input');
    },
  );
}
