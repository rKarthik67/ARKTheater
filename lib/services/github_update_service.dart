import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Android-only updater backed by ARK Theater's public GitHub Releases.
///
/// Android always owns the final install confirmation. This service downloads
/// a signed APK to the app cache and opens the platform package installer; it
/// never attempts a silent update.
class GitHubUpdateService {
  static const _repo = 'rKarthik67/ARKTheater';
  static const _channel = MethodChannel('ark_theater/update');
  final Dio _dio;

  GitHubUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  Future<GitHubReleaseUpdate?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;
    final installed = await PackageInfo.fromPlatform();
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$_repo/releases/latest',
      options: Options(headers: const {'Accept': 'application/vnd.github+json'}),
    );
    final release = response.data;
    if (release == null || release['draft'] == true || release['prerelease'] == true) {
      return null;
    }
    final tag = release['tag_name']?.toString() ?? '';
    final version = _normaliseVersion(tag);
    if (version == null || !_isNewer(version, installed.version)) return null;

    final assets = release['assets'];
    if (assets is! List) return null;
    Map<String, dynamic>? apk;
    for (final item in assets) {
      if (item is! Map) continue;
      final asset = item.cast<String, dynamic>();
      if ((asset['name']?.toString().toLowerCase() ?? '').endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    final downloadUrl = apk?['browser_download_url']?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) return null;

    return GitHubReleaseUpdate(
      version: version,
      downloadUrl: downloadUrl,
      notes: release['body']?.toString() ?? '',
    );
  }

  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<void> requestInstallPermission() =>
      _channel.invokeMethod<void>('requestInstallPermission');

  Future<void> downloadAndInstall(
    GitHubReleaseUpdate update, {
    ProgressCallback? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final destination = '${directory.path}/ark-theater-${update.version}.apk';
    await _dio.download(update.downloadUrl, destination, onReceiveProgress: onProgress);
    await _channel.invokeMethod<void>('installApk', {'path': destination});
  }

  static String? _normaliseVersion(String value) {
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)$').firstMatch(value.trim());
    return match?.group(1);
  }

  static bool _isNewer(String candidate, String installed) {
    final candidateParts = candidate.split('.').map(int.parse).toList();
    final installedParts = installed.split('+').first.split('.').map(int.tryParse).toList();
    for (var index = 0; index < candidateParts.length; index++) {
      final current = index < installedParts.length ? installedParts[index] ?? 0 : 0;
      if (candidateParts[index] != current) return candidateParts[index] > current;
    }
    return false;
  }
}

class GitHubReleaseUpdate {
  const GitHubReleaseUpdate({
    required this.version,
    required this.downloadUrl,
    required this.notes,
  });

  final String version;
  final String downloadUrl;
  final String notes;
}
