import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:android_intent_plus/android_intent_plus.dart';

class UpdateService {
  static const String _repoOwner = 'servairmarketing';
  static const String _repoName = 'compleat-mobile';
  static const String _githubApiBase = 'https://api.github.com';

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '$_githubApiBase/repos/$_repoOwner/$_repoName/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );
      if (response.statusCode != 200) return null;
      final data = response.data;
      final latestVersion = (data['tag_name'] as String).replaceAll('v', '');
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      if (_isNewer(latestVersion, currentVersion)) {
        final assets = data['assets'] as List;
        if (assets.isEmpty) return null;
        final apkUrl = assets.first['browser_download_url'] as String;
        return {'version': latestVersion, 'url': apkUrl};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map(int.parse).toList();
    final c = current.split('.').map(int.parse).toList();
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
    Function() onComplete,
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
      onComplete();
      await Future.delayed(const Duration(milliseconds: 500));
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'file://$filePath',
        type: 'application/vnd.android.package-archive',
        flags: [0x10000000],
      );
      await intent.launch();
    } catch (e) {
      onError(e.toString());
    }
  }
}
