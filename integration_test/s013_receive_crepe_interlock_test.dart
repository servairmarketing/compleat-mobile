// S013: Crepe interlock pairs Material Type and Basis Weight.
//
// Selecting 'Crepe' in either dropdown auto-sets the other to 'Crepe'.
// See lib/screens/receive_screen.dart:271-300 for the interlock logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'S013: Crepe interlock pairs Material Type and Basis Weight',
    ($) async {
      await loginAsJoseph($);
      await openReceive($);

      // Forward direction: Material Type = Crepe should auto-set Basis
      // Weight to Crepe.
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
      // Type to Crepe.
      await $(#basisWeightDropdown).tap();
      await $(find.text('Crepe')).scrollTo().tap();

      expect($(#materialTypeDropdown).$('Crepe'), findsOneWidget,
          reason: 'BasisWeight=Crepe must auto-set Material=Crepe');

      // (c) state: still no error banner after the interlock fires.
      expect($(#messageBannerError), findsNothing);
    },
  );
}
