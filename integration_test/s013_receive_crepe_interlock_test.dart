// S013: Crepe interlock pairs Material Type and Basis Weight (rev 2 screen).
//
// Selecting 'Crepe' in either dropdown auto-sets the other to 'Crepe'.
// See lib/screens/receive_screen.dart (Shipment Details dropdowns).

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

      // Reset the screen: "New shipment" (no rolls in the list → no confirm).
      await $(#newShipmentButton).tap();
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
