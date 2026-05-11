// Patrol test bundle entry point.
//
// patrol_cli's `--target` accepts only one Dart file, so we aggregate
// every *_test.dart's main() here. Each main() registers its
// patrolTest() definitions into the IntegrationTestWidgetsFlutterBinding;
// running them sequentially from this entry point bundles all scenarios
// into the single androidTest APK that CI uploads.
//
// To add a new test file: import it with an `as` alias and call its
// main() below.

import 'login_test.dart' as login;
import 'receive_test.dart' as receive;

void main() {
  login.main();
  receive.main();
}
