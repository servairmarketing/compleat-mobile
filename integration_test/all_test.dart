// Consolidated Patrol E2E suite for compleat-mobile.
//
// Why one file: patrol_cli accepts a single --target, and Patrol itself
// is built around one-test-session-per-process. patrolTest() registers
// via testWidgets() and depends on singletons in PatrolBinding /
// global_state. An earlier "bundle" pattern (all_test.dart importing
// login_test.dart and receive_test.dart and calling each file's main()
// in turn) caused every test past the first to 500 from the
// PatrolAppService -- the singleton routing latched onto the first
// main()'s registrations and the second main()'s tests were unreachable.
// Patrol's own e2e_app uses one *_test.dart per file with no aggregator,
// so we mirror that here: one file, one main(), all patrolTest() calls
// inline.
//
// Build with --dart-define=APP_ENV=test --dart-define=API_BASE=<test>.
// The androidTest runner does NOT use clearPackageData (would kill the
// app between tests without Android Test Orchestrator); each patrolTest
// resets isolation via pumpWidgetAndSettle(CompleatApp(isLoggedIn: false)).
//
// Backend assumptions (test env Cloud Run API in build.yml):
//   - User joseph / Test@1234 with role=admin
//   - Vendor TESTVEND1 seeded
//   - Material Type values include 'Virgin' and 'Crepe'
//   - Basis Weight values include '24' and 'Crepe'
//   - Width values include '69'
//   - Parent roll TEST-PARENT-001 already exists (used for S011 dup test)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:compleat_mobile/main.dart';

const _username = 'joseph';
const _password = 'Test@1234';

const _adminMenuCardKeys = <String>[
  'menuCard_receive',
  'menuCard_production',
  'menuCard_sales',
  'menuCard_conversion',
  'menuCard_stocktake',
  'menuCard_history',
  'menuCard_printerSettings',
];

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
    'S001: admin login routes to home with all menu cards and env banner',
    ($) async {
      await $.pumpWidgetAndSettle(
        const CompleatApp(isLoggedIn: false),
      );

      // Login screen rendered with the three known keys.
      expect($(#usernameField), findsOneWidget);
      expect($(#passwordField), findsOneWidget);
      expect($(#signInButton), findsOneWidget);

      await $(#usernameField).enterText(_username);
      await $(#passwordField).enterText(_password);
      await $(#signInButton).tap();

      // Layer (b): home screen reached within 5s. Any one menu card
      // appearing proves Navigator.pushReplacement -> HomeScreen() ran.
      await $(#menuCard_receive).waitUntilVisible(
        timeout: const Duration(seconds: 5),
      );

      // Layer (a): login screen widgets are gone.
      expect($(#usernameField), findsNothing);
      expect($(#passwordField), findsNothing);
      expect($(#signInButton), findsNothing);

      // Layer (c): every admin menu card is visible.
      for (final cardKey in _adminMenuCardKeys) {
        expect(
          $(Key(cardKey)),
          findsOneWidget,
          reason: 'admin should see $cardKey on home screen',
        );
      }

      // Layer (d): negative assertion. The error Text on login has no
      // stable key (only red styling), so we negative-assert on the
      // default error string and on login fields being gone (above).
      expect(find.text('Login failed'), findsNothing);

      // Layer (e): ENVIRONMENT banner present (proves APP_ENV != 'prod').
      expect($(#environmentBanner), findsOneWidget);
    },
  );

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
