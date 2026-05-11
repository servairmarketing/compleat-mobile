// S010: receive a fresh parent roll, success banner shown.
//
// Backend assumption: TESTVEND1 vendor seeded; Material Type 'Virgin',
// Basis Weight '24', Width '69' all present in the test API.

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S010: receive a fresh parent roll, success banner shown',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      // Unique per run -- avoids cross-run collisions if a previous run
      // submitted the same id.
      final rollId =
          'RCV-TEST-${DateTime.now().millisecondsSinceEpoch}';

      await $(#rollIdField).enterText(rollId);

      await $(#vendorDropdown).tap();
      await $('TESTVEND1').scrollTo().tap();

      await $(#poNumberField).enterText('PO-RCV-TEST');

      await $(#materialTypeDropdown).tap();
      await $(find.text('Virgin')).scrollTo().tap();

      await $(#basisWeightDropdown).tap();
      await $(find.text('24')).scrollTo().tap();

      await $(#widthDropdown).tap();
      await $(find.text('69')).scrollTo().tap();

      await $(#lengthField).enterText('50000');
      await $(#weightField).enterText('3000');

      await $(#submitButton).tap();

      // (a) UI: success banner appears within ~8s of the API round-trip.
      await $(#messageBannerSuccess).waitUntilVisible(
        timeout: const Duration(seconds: 8),
      );

      // (b) negative: no error banner present.
      expect($(#messageBannerError), findsNothing);

      // (c) state: form was cleared by _clearForm() -- the unique Roll ID
      // we typed should no longer appear anywhere on screen.
      expect(find.text(rollId), findsNothing,
          reason: 'Form should be cleared after successful submit');
    },
  );
}
