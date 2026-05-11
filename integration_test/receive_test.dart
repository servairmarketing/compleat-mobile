// Patrol E2E scenarios S010-S013 for the Receive Parent Roll screen.
//
// Backend assumptions (test env, the Cloud Run API in build.yml):
//   - User joseph / Test@1234 exists with role=admin
//   - Vendor TESTVEND1 is seeded
//   - Material Type values include 'Virgin' and 'Crepe'
//   - Basis Weight values include '24' and 'Crepe'
//   - Width values include '69'
//   - Parent roll TEST-PARENT-001 already exists in Firestore (S011 uses
//     it for duplicate-rejection)
//
// Build with --dart-define=APP_ENV=test plus the test API_BASE; the
// Patrol androidTest runner uses clearPackageData=true so each test
// starts logged out.
//
// Notes on screen behavior verified against lib/screens/receive_screen.dart
// before writing these tests:
//   - Roll ID is OPTIONAL (auto-generated on the server when blank) -- so
//     the validation gate exists on Vendor / Material / Basis Weight, NOT
//     on Roll ID. S012 reflects that.
//   - Banner-style messages (no inline field errors). The banner uses the
//     Key 'messageBannerSuccess' or 'messageBannerError' depending on
//     outcome -- added in this same change so we can negative-assert
//     without text matching.
//   - Success branch clears the form and re-focuses Roll ID; error branch
//     leaves the form untouched. We don't assert focus on the error path
//     because the screen doesn't restore it there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:compleat_mobile/main.dart';

const _username = 'joseph';
const _password = 'Test@1234';

Future<void> _loginAsJoseph(PatrolIntegrationTester $) async {
  await $.pumpWidgetAndSettle(const CompleatApp(isLoggedIn: false));
  await $(#usernameField).enterText(_username);
  await $(#passwordField).enterText(_password);
  await $(#signInButton).tap();
  await $(#menuCard_receive).waitUntilVisible(
    timeout: const Duration(seconds: 5),
  );
}

Future<void> _openReceive(PatrolIntegrationTester $) async {
  await $(#menuCard_receive).tap();
  // Master data (vendors, widths, etc.) loads from the test API on first
  // build of this screen. 10s covers a cold backend.
  await $(#rollIdField).waitUntilVisible(
    timeout: const Duration(seconds: 10),
  );
}

void main() {
  patrolTest(
    'S010: receive a fresh parent roll, success banner shown',
    ($) async {
      await _loginAsJoseph($);
      await _openReceive($);

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

  patrolTest(
    'S011: duplicate Roll ID rejected, form preserved',
    ($) async {
      await _loginAsJoseph($);
      await _openReceive($);

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

  patrolTest(
    'S012: submit with empty required fields shows validation banner',
    ($) async {
      await _loginAsJoseph($);
      await _openReceive($);

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
      // since we never entered any text; explicit assertion would require
      // controller introspection that Patrol doesn't expose cleanly.
    },
  );

  patrolTest(
    'S013: Crepe interlock pairs Material Type and Basis Weight',
    ($) async {
      await _loginAsJoseph($);
      await _openReceive($);

      // Forward direction: Material Type = Crepe should auto-set Basis
      // Weight to Crepe (lib/screens/receive_screen.dart:271-278).
      await $(#materialTypeDropdown).tap();
      await $(find.text('Crepe')).scrollTo().tap();

      // (a) UI: Basis Weight dropdown now displays 'Crepe' as its value.
      expect($(#basisWeightDropdown).$('Crepe'), findsOneWidget,
          reason: 'Material=Crepe must auto-set BasisWeight=Crepe');

      // (b) negative: no error banner -- benign UX, not an error.
      expect($(#messageBannerError), findsNothing);

      // Reset the form. Clear button has no Key, but its label is unique
      // on this screen.
      await $('Clear').tap();
      await $.pumpAndSettle();

      // Reverse direction: Basis Weight = Crepe should auto-set Material
      // Type to Crepe (lib/screens/receive_screen.dart:293-300).
      await $(#basisWeightDropdown).tap();
      await $(find.text('Crepe')).scrollTo().tap();

      expect($(#materialTypeDropdown).$('Crepe'), findsOneWidget,
          reason: 'BasisWeight=Crepe must auto-set Material=Crepe');

      // (c) state: still no error banner after the interlock fires.
      expect($(#messageBannerError), findsNothing);
    },
  );
}
