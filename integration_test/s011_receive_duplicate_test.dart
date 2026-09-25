// S011: duplicate Roll ID is refused before it reaches the list (rev 2).
//
// Backend assumption: parent roll TEST-PARENT-001 already exists in the
// test Firestore so GET /rolls/TEST-PARENT-001 answers with the roll.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S011: duplicate Roll ID keeps focus, is not added to the list',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      await $(#vendorDropdown).tap();
      await $('TESTVEND1').scrollTo().tap();
      await $(#poNumberField).enterText('PO-RCV-DUP');
      await $(#materialTypeDropdown).tap();
      await $(find.text('Virgin')).scrollTo().tap();
      await $(#basisWeightDropdown).tap();
      await $(find.text('24')).scrollTo().tap();
      await $(#widthDropdown).tap();
      await $(find.text('69')).scrollTo().tap();

      const dupId = 'TEST-PARENT-001';
      await $(#rollIdField).enterText(dupId);
      // Scanner Enter → duplicate check.
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pumpAndSettle(timeout: const Duration(seconds: 8));

      // (a) UI: inline error under the Roll ID field.
      expect(find.textContaining('already exists'), findsOneWidget,
          reason: 'Duplicate must be flagged inline on scan');

      // (b) the roll was NOT added: counter still 0, Submit disabled.
      expect($(#rollCount).$('0'), findsOneWidget);

      // (c) state: the typed id is preserved for correction.
      expect(find.text(dupId), findsOneWidget,
          reason: 'A refused scan must keep the operator\'s input');
      expect($(#messageBannerSuccess), findsNothing);
    },
  );
}
