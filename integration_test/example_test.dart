import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'Patrol harness boots',
    ($) async {
      expect(1 + 1, 2);
    },
  );
}
