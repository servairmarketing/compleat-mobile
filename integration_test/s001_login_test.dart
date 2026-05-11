// S001: Successful login as admin -- the only scenario that consistently
// passed under the previous bundled-tests setup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:compleat_mobile/main.dart';
import 'common.dart';

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

      await $(#usernameField).enterText(username);
      await $(#passwordField).enterText(password);
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
      for (final cardKey in adminMenuCardKeys) {
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
}
