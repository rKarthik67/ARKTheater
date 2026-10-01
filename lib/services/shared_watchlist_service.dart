import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../models/media_item.dart';

/// Client for the account-free, SQLite-backed shared watchlist API. The
/// long-lived library credential is a bearer secret, so it lives in secure
/// platform storage rather than SharedPreferences.
class SharedWatchlistService {
  static const _secretKey = 'ark_theater.shared_watchlist_secret.v1';

  SharedWatchlistService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  http.Client? _eventClient;
  StreamSubscription<String>? _eventSubscription;
  bool _eventsStopped = true;

  Dio get _dio => Dio(BaseOptions(
        // Libraries live on the Oracle VM's SQLite file. The optional Vercel
        // stream resolver is stateless and therefore cannot host them.
        baseUrl: AppConfig.sharedWatchlistBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        // Pairing failures (such as an expired/claimed code) are expected
        // client responses. Let _responseData surface the API's concise error
        // instead of Dio replacing it with a generic 404 exception.
        validateStatus: (_) => true,
      ));

  Future<String?> readSecret() => _secureStorage.read(key: _secretKey);

  Future<void> disconnect() async {
    stopEvents();
    await _secureStorage.delete(key: _secretKey);
  }

  Future<SharedWatchlistSnapshot> create(List<MediaItem> items) async {
    final response = await _dio.post('/api/v2/watchlist/libraries', data: {
      'items': items.map(_itemJson).toList(),
    });
    final data = _responseData(response);
    final secret = data['librarySecret'] as String?;
    if (secret == null || secret.isEmpty) throw const SharedWatchlistException('The server did not create a library credential.');
    await _secureStorage.write(key: _secretKey, value: secret);
    return _snapshot(data);
  }

  Future<SharedWatchlistSnapshot> join(String code, List<MediaItem> items) async {
    final response = await _dio.post('/api/v2/watchlist/pairings/join', data: {
      'code': code,
      'items': items.map(_itemJson).toList(),
    });
    final data = _responseData(response);
    final secret = data['librarySecret'] as String?;
    if (secret == null || secret.isEmpty) throw const SharedWatchlistException('The server did not return the shared-watchlist credential.');
    await _secureStorage.write(key: _secretKey, value: secret);
    return _snapshot(data);
  }

  Future<SharedWatchlistSnapshot> sync(List<MediaItem> items) async {
    final secret = await readSecret();
    if (secret == null || secret.isEmpty) throw const SharedWatchlistException('This device is not connected to a shared watchlist.');
    final response = await _dio.post(
      '/api/v2/watchlist/sync',
      data: {'items': items.map(_itemJson).toList()},
      options: Options(headers: {'Authorization': 'Bearer $secret'}),
    );
    return _snapshot(_responseData(response));
  }

  Future<SharedWatchlistSnapshot> addItem(MediaItem item) async {
    final secret = await _requiredSecret();
    final response = await _dio.post(
      '/api/v2/watchlist/items',
      data: {'item': _itemJson(item)},
      options: Options(headers: {'Authorization': 'Bearer $secret'}),
    );
    return _snapshot(_responseData(response));
  }

  Future<SharedWatchlistSnapshot> removeItem(MediaItem item) async {
    final secret = await _requiredSecret();
    final response = await _dio.delete(
      '/api/v2/watchlist/items/${item.type.name}/${item.id}',
      options: Options(headers: {'Authorization': 'Bearer $secret'}),
    );
    return _snapshot(_responseData(response));
  }

  Future<PairingCode> createPairingCode() async {
    final secret = await readSecret();
    if (secret == null || secret.isEmpty) throw const SharedWatchlistException('Create or join a shared watchlist first.');
    final response = await _dio.post(
      '/api/v2/watchlist/pairings',
      options: Options(headers: {'Authorization': 'Bearer $secret'}),
    );
    final data = _responseData(response);
    final code = data['code'] as String?;
    final expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
    if (code == null || expiresAt == null) throw const SharedWatchlistException('The server did not create a pairing code.');
    return PairingCode(code: code, expiresAt: expiresAt.toLocal());
  }

  Future<String> _requiredSecret() async {
    final secret = await readSecret();
    if (secret == null || secret.isEmpty) {
      throw const SharedWatchlistException(
        'This device is not connected to a shared watchlist.',
      );
    }
    return secret;
  }

  /// Opens an SSE connection while the app is running. Events are hints only:
  /// the callback always performs a normal union sync, so reconnects and missed
  /// events cannot lose titles.
  Future<void> startEvents(Future<void> Function() onChanged) async {
    stopEvents();
    final secret = await readSecret();
    if (secret == null || secret.isEmpty) return;
    _eventsStopped = false;
    unawaited(_openEventStream(secret, onChanged));
  }

  void stopEvents() {
    _eventsStopped = true;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _eventClient?.close();
    _eventClient = null;
  }

  Future<void> _openEventStream(String secret, Future<void> Function() onChanged) async {
    if (_eventsStopped) return;
    final client = http.Client();
    _eventClient = client;
    var event = '';
    try {
      final request = http.Request(
        'GET',
        Uri.parse('${AppConfig.sharedWatchlistBaseUrl}/api/v2/watchlist/events'),
      )..headers['Authorization'] = 'Bearer $secret';
      final response = await client.send(request);
      if (response.statusCode != 200) return;
      _eventSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('event:')) {
          event = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:') && event == 'watchlist_changed') {
          unawaited(onChanged());
          event = '';
        }
      });
      await _eventSubscription!.asFuture<void>();
    } catch (_) {
      // A later reconnect or manual Sync now will recover the authoritative
      // SQLite state; network errors are deliberately not user-facing here.
    } finally {
      client.close();
      if (identical(_eventClient, client)) _eventClient = null;
    }
    if (!_eventsStopped) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!_eventsStopped) unawaited(_openEventStream(secret, onChanged));
    }
  }

  Map<String, dynamic> _itemJson(MediaItem item) => {
        'id': item.id,
        'type': item.type.name,
        'title': item.title,
        'posterPath': item.posterPath,
        'voteAverage': item.voteAverage,
        'releaseDate': item.releaseDate,
      };

  Map<String, dynamic> _responseData(Response<dynamic> response) {
    final data = response.data;
    if (data is! Map) throw const SharedWatchlistException('Unexpected response from the shared-watchlist server.');
    final map = Map<String, dynamic>.from(data);
    if (map['success'] != true) throw SharedWatchlistException(map['error'] as String? ?? 'Shared watchlist request failed.');
    return map;
  }

  SharedWatchlistSnapshot _snapshot(Map<String, dynamic> data) {
    final rawItems = data['items'];
    if (rawItems is! List) throw const SharedWatchlistException('Shared watchlist data was invalid.');
    final items = <MediaItem>[];
    for (final entry in rawItems) {
      if (entry is! Map) continue;
      final json = Map<String, dynamic>.from(entry);
      final id = json['id'];
      final type = json['type'];
      if (id is! int || (type != 'movie' && type != 'tv')) continue;
      items.add(MediaItem(
        id: id,
        type: type == 'movie' ? MediaType.movie : MediaType.tv,
        title: json['title'] as String? ?? 'Untitled',
        posterPath: json['posterPath'] as String?,
        voteAverage: (json['voteAverage'] as num?)?.toDouble() ?? 0,
        releaseDate: json['releaseDate'] as String?,
      ));
    }
    final deleted = <SharedWatchlistItemKey>[];
    final rawDeleted = data['deleted'];
    if (rawDeleted is List) {
      for (final entry in rawDeleted) {
        if (entry is! Map) continue;
        final json = Map<String, dynamic>.from(entry);
        final id = json['id'];
        final type = json['type'];
        if (id is int && (type == 'movie' || type == 'tv')) {
          deleted.add(SharedWatchlistItemKey(
            id: id,
            type: type == 'movie' ? MediaType.movie : MediaType.tv,
          ));
        }
      }
    }
    return SharedWatchlistSnapshot(
      items: items,
      deleted: deleted,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

class SharedWatchlistSnapshot {
  const SharedWatchlistSnapshot({
    required this.items,
    required this.deleted,
    required this.revision,
  });

  final List<MediaItem> items;
  final List<SharedWatchlistItemKey> deleted;
  final int revision;
}

class SharedWatchlistItemKey {
  const SharedWatchlistItemKey({required this.id, required this.type});

  final int id;
  final MediaType type;
}

class PairingCode {
  const PairingCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

class SharedWatchlistException implements Exception {
  const SharedWatchlistException(this.message);

  final String message;

  @override
  String toString() => message;
}
