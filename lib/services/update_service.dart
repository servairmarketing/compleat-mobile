import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart' show appEnvironment;

class UpdateService {
  static const String _repoOwner = 'servairmarketing';
  static const String _repoName = 'compleat-mobile';
  static const String _githubApiBase = 'https://api.github.com';

  // Release channels (two independent walls between them):
  // - prod (LIVE): GOOGLE PLAY internal testing (Joe's rulings 2026-10-01,
  //   docs/PLAY_INTERNAL_DISTRIBUTION_PLAN_2026-09-28.md D1/D4). The prod
  //   app NEVER contacts GitHub and NEVER downloads or installs an APK —
  //   Play's Device and Network Abuse policy forbids an app distributed via
  //   Google Play from updating itself by any other mechanism. "Check for
  //   Update" on prod opens the app's Play Store page (openPlayStore);
  //   the store shows "Update" when a newer version is on the track.
  // - test (APP_ENV=test, qa flavor): unchanged — newest release tagged
  //   test-vX.Y.Z from the GitHub release LIST (pre-releases included
  //   there), downloaded and installed in-app. The test app only ever
  //   matches the test- prefix, so it cannot see live releases.
  static const String _testTagPrefix = 'test-v';

  /// Play Store listing of the prod app (applicationId from
  /// android/app/build.gradle.kts; the qa flavor's `.test` suffix is NOT
  /// on Play). `market://` opens the Play Store app directly; the https
  /// form is the fallback for a device without the store app.
  static const String playPackageName = 'com.compleat.compleat_mobile';
  static final Uri playStoreMarketUri =
      Uri.parse('market://details?id=$playPackageName');
  static final Uri playStoreWebUri =
      Uri.parse('https://play.google.com/store/apps/details?id=$playPackageName');

  /// True when this build updates itself from the GitHub test channel
  /// (qa flavor). False = prod = Google Play.
  static bool get usesGitHubTestChannel => appEnvironment == 'test';

  /// Prod flavor: open the Play Store page. Returns false if neither the
  /// store app nor a browser could be opened.
  static Future<bool> openPlayStore() async {
    try {
      if (await launchUrl(playStoreMarketUri,
          mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (e) {
      print('DEBUG openPlayStore market:// failed: $e');
    }
    try {
      return await launchUrl(playStoreWebUri,
          mode: LaunchMode.externalApplication);
    } catch (e) {
      print('DEBUG openPlayStore https failed: $e');
      return false;
    }
  }

  /// TEST channel only. On the prod flavor this returns null WITHOUT any
  /// network call (Play owns prod updates — see the channel note above).
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    if (!usesGitHubTestChannel) return null;
    try {
      final dio = Dio();
      String? latestVersion;
      List? assets;

      final response = await dio.get(
        '$_githubApiBase/repos/$_repoOwner/$_repoName/releases?per_page=30',
        options:
            Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );
      print('DEBUG GitHub API status (test channel): ${response.statusCode}');
      if (response.statusCode != 200) return null;
      // The release list is NOT reliably newest-first (observed live:
      // v1.0.66 listed above test-v1.0.68), so scan every test-v tag and
      // keep the highest version instead of breaking on the first match.
      for (final rel in (response.data as List)) {
        final tag = rel['tag_name'] as String? ?? '';
        if (tag.startsWith(_testTagPrefix)) {
          final v = tag.substring(_testTagPrefix.length);
          if (latestVersion == null || _isNewer(v, latestVersion)) {
            latestVersion = v;
            assets = rel['assets'] as List;
          }
        }
      }
      if (latestVersion == null) return null;

      final info = await PackageInfo.fromPlatform();
      // qa flavor appends versionNameSuffix "-test" (e.g. "1.0.67-test");
      // strip any suffix so the numeric compare sees plain X.Y.Z.
      final currentVersion = info.version.split('-').first;
      print('DEBUG latestVersion: $latestVersion currentVersion: $currentVersion isNewer: ${_isNewer(latestVersion, currentVersion)}');
      if (_isNewer(latestVersion, currentVersion)) {
        if (assets == null || assets.isEmpty) return null;
        // Pick the APK by name rather than blindly taking the first asset.
        final apk = assets.firstWhere(
          (a) => (a['name'] as String? ?? '').endsWith('.apk'),
          orElse: () => assets!.first,
        );
        final apkUrl = apk['browser_download_url'] as String;
        return {'version': latestVersion, 'url': apkUrl};
      }
      return null;
    } catch (e) {
      print('DEBUG checkForUpdate exception: $e');
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    // tryParse guard: a malformed component must degrade to 0, never throw —
    // an exception here is swallowed by checkForUpdate's catch and shows the
    // user a false "you are on the latest version".
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static Future<void> downloadAndInstall(
    String url,
    String version,
    Function(double) onProgress,
    Function(String) onComplete,
    Function(String) onError,
  ) async {
    try {
      final dir = await getExternalStorageDirectory();
      final filePath = '${dir!.path}/compleat-update-$version.apk';
      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );
      onComplete(filePath);
    } catch (e) {
      onError(e.toString());
    }
  }

  static Future<void> installApk(String filePath) async {
    print('DEBUG installApk called with: $filePath');
    try {
      final result = await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
      print('DEBUG OpenFilex result: \${result.type} \${result.message}');
    } catch (e) {
      print('DEBUG installApk error: \$e');
    }
  }
}
