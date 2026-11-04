import 'package:dio/dio.dart';

import '../core/config.dart';

/// A one-use, four-minute code this app mints to unlock the scraper-backed
/// player on the private ArkPlay web apps (Movie-and-tv-show-2,
/// ark-theater-play-web) - see each site's netlify/functions/unlock.js.
/// Generation requires [AppConfig.streamUnlockAppSecret], which only this
/// app is given, so the web apps can claim a code but never mint one.
class StreamUnlockCode {
  const StreamUnlockCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

class StreamUnlockException implements Exception {
  const StreamUnlockException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StreamUnlockService {
  StreamUnlockService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.sharedWatchlistBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ));

  final Dio _dio;

  Future<StreamUnlockCode> createCode() async {
    final secret = AppConfig.streamUnlockAppSecret;
    if (secret.isEmpty) {
      throw const StreamUnlockException(
        'STREAM_UNLOCK_APP_SECRET is not configured in .env.',
      );
    }
    final response = await _dio.post(
      '/api/v2/stream-unlock/codes',
      options: Options(headers: {'Authorization': 'Bearer $secret'}),
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    if (response.statusCode != 201 || data['success'] != true) {
      throw StreamUnlockException(
        data['error']?.toString() ?? 'Could not create an unlock code.',
      );
    }
    final code = data['code'] as String?;
    final expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
    if (code == null || expiresAt == null) {
      throw const StreamUnlockException('The server did not return a code.');
    }
    return StreamUnlockCode(code: code, expiresAt: expiresAt.toLocal());
  }
}
