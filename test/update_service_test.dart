// Guards Joe's ruling D4 (2026-10-01, docs/PLAY_INTERNAL_DISTRIBUTION_PLAN_2026-09-28.md
// §2.5): the prod flavor is distributed through Google Play and must never
// contact GitHub or download an APK. `flutter test` runs with the committed
// default APP_ENV ('prod'), so these tests exercise exactly the prod build.
import 'package:flutter_test/flutter_test.dart';
import 'package:compleat_mobile/services/update_service.dart';

void main() {
  test('prod flavor does not use the GitHub test channel', () {
    expect(UpdateService.usesGitHubTestChannel, isFalse);
  });

  test('prod checkForUpdate returns null', () async {
    // The gate above is what proves "no GitHub call"; this is the
    // user-visible contract: the prod build never reports a GitHub update.
    final result = await UpdateService.checkForUpdate();
    expect(result, isNull);
  });

  test('Play Store URIs point at the prod applicationId', () {
    expect(UpdateService.playPackageName, 'com.compleat.compleat_mobile');
    expect(UpdateService.playStoreMarketUri.toString(),
        'market://details?id=com.compleat.compleat_mobile');
    expect(UpdateService.playStoreWebUri.toString(),
        'https://play.google.com/store/apps/details?id=com.compleat.compleat_mobile');
  });
}
