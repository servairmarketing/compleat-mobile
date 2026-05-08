# compleat_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Build environments — prod vs test

The same source produces two APKs, selected at compile time via
`--dart-define`. There is no local-build path — GitHub Actions does the
building (see `.github/workflows/build.yml`).

| Variant | API_BASE flag | Backend hit | Workflow output |
|---|---|---|---|
| prod (default) | _none_ | https://compleat-inventory-api-793462624071.northamerica-northeast2.run.app | `app-release.apk` (published as a GitHub Release) |
| test | `--dart-define=API_BASE=<test_url> --dart-define=APP_ENV=test` | https://compleat-inventory-api-477414435007.northamerica-northeast2.run.app | `app-test-release.apk` (workflow artifact, not released) |

Both variants are built on every push to `main` and on manual
`workflow_dispatch`. Pull the test APK from the workflow run page under
**Artifacts → app-test-release.apk**.

### Identifying the test APK on a device

When the test APK is running, the home screen shows a thin amber
**`TEST ENVIRONMENT`** strip directly under the blue header. Prod builds
show no such strip. The two builds currently share `applicationId`
(`com.compleat.compleat_mobile`), so installing the test APK replaces the
prod APK and vice versa — fine for dedicated E2E hardware. Side-by-side
install would need an Android build flavor with `applicationIdSuffix`.

## End-to-end tests (Patrol)

Patrol 4.x drives the app end-to-end on Android — both emulators and
the Tera P60. Tests live in `integration_test/`.

### Prerequisites

- `patrol_cli` installed locally: `dart pub global activate patrol_cli`
- Java 17 + Android SDK on `PATH`
- Test backend deployed and reachable
- Test users seeded in the test Firestore + Auth — currently
  `joseph` / `Test@1234` (admin)
- A connected Android device or running emulator with a fresh app state
  (the instrumentation runner is configured with `clearPackageData=true`,
  so previous tokens are wiped between runs)

### Running a scenario locally

From the repo root:

```bash
patrol test \
  --target=integration_test/login_test.dart \
  --dart-define=APP_ENV=test \
  --dart-define=API_BASE=https://compleat-inventory-api-477414435007.northamerica-northeast2.run.app
```

Patrol will build a debug APK + an `androidTest` APK, install both, and
drive the device. Logs stream to stdout; on failure, screenshots land in
`build/patrol/`.

### Building the Patrol APK pair on CI

The `build-patrol-test-apk` job in `.github/workflows/build.yml` runs on
`workflow_dispatch` only (it doesn't fire on every push). Trigger it
from the Actions tab → "Build APK" → "Run workflow". Artifacts:

- `app-patrol-debug.apk` — the instrumented app
- `app-patrol-androidTest.apk` — the test runner APK that drives it

Pair them up and `adb install` both to a device, then run via
`adb shell am instrument -w -e ...` or use `patrol test --use-apks`.

### Current scenarios

| ID | File | What it asserts |
|---|---|---|
| S001 | `integration_test/login_test.dart` | Admin login (`joseph`/`Test@1234`) reaches home with all 7 menu cards and the `ENVIRONMENT` banner visible; login screen is gone; no error text. |
