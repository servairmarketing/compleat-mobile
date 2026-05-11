// Shared constants and helpers for the Patrol E2E suite.
//
// This file is NOT a test file (no `_test.dart` suffix) so patrol_cli
// will not try to build it as an instrumentation entry point. Per-scenario
// test files import the symbols they need from here -- they never call
// each other's main().
//
// Why the per-scenario file split: PatrolJUnitRunner is designed for
// Android Test Orchestrator (one test per process). Without ATO, only
// the first runDartTest per process succeeds; every subsequent RPC
// returns 500. Each scenario therefore gets its own --target build,
// its own APK pair, its own install/run cycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:compleat_mobile/main.dart';

const username = 'joseph';
const password = 'Test@1234';

const adminMenuCardKeys = <String>[
  'menuCard_receive',
  'menuCard_production',
  'menuCard_sales',
  'menuCard_conversion',
  'menuCard_stocktake',
  'menuCard_history',
  'menuCard_printerSettings',
];

Future<void> loginAsJoseph(PatrolIntegrationTester $) async {
  await $.pumpWidgetAndSettle(const CompleatApp(isLoggedIn: false));
  await $(#usernameField).enterText(username);
  await $(#passwordField).enterText(password);
  await $(#signInButton).tap();
  await $(#menuCard_receive).waitUntilVisible(
    timeout: const Duration(seconds: 5),
  );
}

Future<void> openReceive(PatrolIntegrationTester $) async {
  await $(#menuCard_receive).tap();
  // Master data (vendors, widths, etc.) loads from the test API on first
  // build of this screen. 10s covers a cold backend.
  await $(#rollIdField).waitUntilVisible(
    timeout: const Duration(seconds: 10),
  );
}
