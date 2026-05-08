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
