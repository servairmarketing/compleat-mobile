// S010: receive a shipment — two rolls collected locally, ONE Submit, success banner.
//
// Receive rev 2 (Joe's rulings 2026-09-25): rolls are added to an on-screen list
// (no server call per roll) and a single Submit posts /rolls/receive/batch.
//
// Backend assumption: TESTVEND1 vendor seeded; Material Type 'Virgin',
// Basis Weight '24', Width '69' all present in the test API.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S010: collect two rolls locally, one Submit, success banner shown',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      // Shipment Details first (Vendor → PO → Material → Basis → Width).
      await $(#vendorDropdown).tap();
      await $('TESTVEND1').scrollTo().tap();
      await $(#poNumberField).enterText('PO-RCV-TEST');
      await $(#materialTypeDropdown).tap();
      await $(find.text('Virgin')).scrollTo().tap();
      await $(#basisWeightDropdown).tap();
      await $(find.text('24')).scrollTo().tap();
      await $(#widthDropdown).tap();
      await $(find.text('69')).scrollTo().tap();

      // Unique per run -- avoids cross-run collisions if a previous run
      // submitted the same ids.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final rollA = 'RCV-TEST-$stamp-A';
      final rollB = 'RCV-TEST-$stamp-B';

      // Roll A with length + weight: Roll ID → Length → Weight → Enter ADDS locally.
      await $(#rollIdField).enterText(rollA);
      await $(#lengthField).enterText('50000');
      await $(#weightField).enterText('3000');
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pumpAndSettle();

      // (a) the counter reads 1 and nothing was submitted yet (Submit still enabled, no result).
      expect($(#rollCount).$('1'), findsOneWidget, reason: 'first roll should be in the list');

      // Roll B with no length/weight: scan → Enter → Enter → Enter.
      await $(#rollIdField).enterText(rollB);
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pumpAndSettle();
      await $(#lengthField).tap();
      await $.tester.testTextInput.receiveAction(TextInputAction.next);
      await $.pumpAndSettle();
      await $(#weightField).tap();
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pumpAndSettle();
      expect($(#rollCount).$('2'), findsOneWidget, reason: 'second roll should be in the list');

      // The list expands inline and shows both ids.
      await $(#rollCounter).tap();
      await $.pumpAndSettle();
      expect($(Key('rollRow-$rollA')), findsOneWidget);
      expect($(Key('rollRow-$rollB')), findsOneWidget);
      await $(#collapseListButton).tap();
      await $.pumpAndSettle();

      // ONE Submit.
      await $(#submitButton).scrollTo().tap();

      // (b) UI: success banner within ~8s of the API round-trip.
      await $(#messageBannerSuccess).waitUntilVisible(
        timeout: const Duration(seconds: 8),
      );
      expect(find.textContaining('2 rolls received'), findsWidgets);

      // (c) negative: no error banner; the list is empty again.
      expect($(#messageBannerError), findsNothing);
      expect($(#rollCount).$('0'), findsOneWidget,
          reason: 'Submit clears the shipment');
      // The result lists both rolls with Undo.
      expect($(Key('undo-$rollA')), findsOneWidget);
      expect($(Key('undo-$rollB')), findsOneWidget);
    },
  );
}
