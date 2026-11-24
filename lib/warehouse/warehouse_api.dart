import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../auth/token_subject.dart';
import '../config/app_config.dart';
import '../sink/api_problem.dart';
import '../sink/reads_api.dart';
import 'warehouse.dart';

/// Contrato de `GET /api/v1/warehouse/warehouses`
/// (`contracts/rfid-reads.openapi.yaml` 0.3.1-draft).
class WarehouseListApi {
  /// Única constante de la ruta.
  static const String path = '/api/v1/warehouse/warehouses';
  static const int defaultLimit = 200;
  static const int maxLimit = 500;
  static const int maxPages = 50;

  static Uri pageUri({
    required String apiBase,
    int limit = defaultLimit,
    String? cursor,
  }) {
    final safeLimit = limit.clamp(1, maxLimit);
    return Uri.parse('${_trim(apiBase)}$path').replace(
      queryParameters: {
        'limit': '$safeLimit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
  }

  static String _trim(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

class WarehouseListPage {
  const WarehouseListPage({required this.data, this.nextCursor});

  final List<Warehouse> data;
  final String? nextCursor;

  factory WarehouseListPage.fromJson(Object? raw) {
    if (raw is! Map) {
      return const WarehouseListPage(data: []);
    }
    final data = raw['data'];
    final cursor = raw['next_cursor'];
    return WarehouseListPage(
      data: [
        if (data is List)
          for (final item in data)
            if (item is Map) Warehouse.fromJson(item),
      ],
      nextCursor: cursor == null || '$cursor' == 'null' || '$cursor'.isEmpty
          ? null
          : '$cursor',
    );
  }
}

class CachedWarehouseList {
  const CachedWarehouseList({
    required this.userId,
    required this.fetchedAt,
    required this.warehouses,
  });

  final String userId;
  final DateTime fetchedAt;
  final List<Warehouse> warehouses;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'warehouses': [for (final item in warehouses) item.toJson()],
      };

  factory CachedWarehouseList.fromJson(Map<Object?, Object?> json) {
    final userId = '${json['user_id']}';
    final raw = json['warehouses'];
    return CachedWarehouseList(
      userId: userId,
      fetchedAt: DateTime.tryParse('${json['fetched_at']}') ?? DateTime.now().toUtc(),
      warehouses: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) Warehouse.fromJson(item),
      ],
    );
  }
}

abstract class WarehouseListCache {
  Future<CachedWarehouseList?> read(String userId);
  Future<void> write(CachedWarehouseList list);
}

class MemoryWarehouseListCache implements WarehouseListCache {
  final Map<String, CachedWarehouseList> _store = {};

  @override
  Future<CachedWarehouseList?> read(String userId) async =>
      _store[cacheKeyForUser(userId)];

  @override
  Future<void> write(CachedWarehouseList list) async {
    _store[cacheKeyForUser(list.userId)] = list;
  }
}

class FileWarehouseListCache implements WarehouseListCache {
  FileWarehouseListCache(this.directory);

  final Directory directory;

  File _file(String userId) => File('${directory.path}/${cacheKeyForUser(userId)}.json');

  @override
  Future<CachedWarehouseList?> read(String userId) async {
    final file = _file(userId);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final cached = CachedWarehouseList.fromJson(raw);
      if (cacheKeyForUser(cached.userId) != cacheKeyForUser(userId)) {
        return null;
      }
      return cached;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(CachedWarehouseList cached) async {
    await directory.create(recursive: true);
    await _file(cached.userId).writeAsString(jsonEncode(cached.toJson()));
  }
}

typedef TokenProvider = Future<String?> Function();
typedef TokenRefresher = Future<String?> Function();
typedef UserIdProvider = Future<String?> Function();
typedef Clock = DateTime Function();

class HttpWarehouseRepository implements WarehouseRepository {
  HttpWarehouseRepository({
    required AppConfig config,
    required TokenProvider tokenProvider,
    required WarehouseListCache cache,
    TokenRefresher? tokenRefresher,
    UserIdProvider? userIdProvider,
    http.Client? client,
    int pageLimit = WarehouseListApi.defaultLimit,
    int maxPages = WarehouseListApi.maxPages,
    Clock clock = DateTime.now,
  }) : this._(
          config,
          tokenProvider,
          tokenRefresher,
          userIdProvider,
          cache,
          client ?? http.Client(),
          pageLimit,
          maxPages,
          clock,
        );

  HttpWarehouseRepository._(
    this._config,
    this._tokenProvider,
    this._tokenRefresher,
    this._userIdProvider,
    this._cache,
    this._client,
    this.pageLimit,
    this.maxPages,
    this._clock,
  );

  final AppConfig _config;
  final TokenProvider _tokenProvider;
  final TokenRefresher? _tokenRefresher;
  final UserIdProvider? _userIdProvider;
  final WarehouseListCache _cache;
  final http.Client _client;
  final int pageLimit;
  final int maxPages;
  final Clock _clock;

  Future<String?> _resolveUserId(String? token) async {
    final provided = await _userIdProvider?.call();
    if (provided != null && provided.isNotEmpty) return provided;
    return subjectFromAccessToken(token);
  }

  @override
  Future<WarehouseListResult> list({bool forceRefresh = false}) async {
    try {
      final fetched = await _fetchAll();
      final userId = fetched.userId;
      if (userId != null && userId.isNotEmpty) {
        await _cache.write(CachedWarehouseList(
          userId: userId,
          fetchedAt: _clock().toUtc(),
          warehouses: fetched.warehouses,
        ));
      }
      return WarehouseListResult(
        warehouses: fetched.warehouses,
        fromCache: false,
        fetchedAt: _clock().toUtc(),
      );
    } on WarehouseListException catch (error) {
      if (error.isForbidden || error.isSessionExpired) {
        rethrow;
      }
      return _fallbackToCache(error);
    } on HttpReadsException catch (error) {
      return _fallbackToCache(_fromHttp(error));
    } catch (error) {
      return _fallbackToCache(
        WarehouseListException(message: warehouseUnavailableMessage, canRetry: true),
      );
    }
  }

  Future<WarehouseListResult> _fallbackToCache(WarehouseListException error) async {
    final token = await _tokenProvider();
    final userId = await _resolveUserId(token);
    if (userId != null && userId.isNotEmpty) {
      final cached = await _cache.read(userId);
      if (cached != null) {
        return WarehouseListResult(
          warehouses: cached.warehouses,
          fromCache: true,
          fetchedAt: cached.fetchedAt,
          warning: 'Sin conexión: se muestran las bodegas guardadas.',
          error: error,
        );
      }
    }
    throw error;
  }

  Future<({List<Warehouse> warehouses, String? userId})> _fetchAll() async {
    if (_config.trimmedApiBase.isEmpty) {
      throw const WarehouseListException(
        message: warehouseUnavailableMessage,
        canRetry: true,
      );
    }
    final initialToken = await _tokenProvider();
    if (initialToken == null || initialToken.isEmpty) {
      throw const WarehouseListException(
        message: sessionExpiredMessage,
        statusCode: 401,
        canRetry: false,
        isSessionExpired: true,
      );
    }
    var token = initialToken;
    final userId = await _resolveUserId(token);
    final items = <Warehouse>[];
    String? cursor;
    var retriedAuth = false;
    for (var page = 0; page < maxPages; page++) {
      final uri = WarehouseListApi.pageUri(
        apiBase: _config.trimmedApiBase,
        limit: pageLimit,
        cursor: cursor,
      );
      final response = await _get(uri, token);
      if (response.statusCode == 401 && !retriedAuth) {
        retriedAuth = true;
        final refreshed = await _tokenRefresher?.call();
        if (refreshed != null && refreshed.isNotEmpty) {
          token = refreshed;
          page--;
          continue;
        }
        throw const WarehouseListException(
          message: sessionExpiredMessage,
          statusCode: 401,
          canRetry: false,
          isSessionExpired: true,
        );
      }
      if (response.statusCode != 200) {
        throw _fromResponse(response);
      }
      final parsed = WarehouseListPage.fromJson(jsonDecode(response.body));
      items.addAll(parsed.data);
      final next = parsed.nextCursor;
      if (next == null || next.isEmpty) {
        return (warehouses: items, userId: userId);
      }
      cursor = next;
    }
    return (warehouses: items, userId: userId);
  }

  Future<http.Response> _get(Uri uri, String token) {
    return _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/problem+json, application/json',
        'X-Correlation-ID': const Uuid().v4(),
      },
    );
  }

  WarehouseListException _fromResponse(http.Response response) {
    final problem = ApiProblem.tryParse(response.body, response.statusCode);
    return _fromHttp(HttpReadsException(
      response.statusCode,
      problem: problem,
    ));
  }

  WarehouseListException _fromHttp(HttpReadsException error) {
    if (error.statusCode == 403) {
      return const WarehouseListException(
        message: warehouseForbiddenMessage,
        statusCode: 403,
        canRetry: false,
        isForbidden: true,
      );
    }
    if (error.statusCode == 401) {
      return const WarehouseListException(
        message: sessionExpiredMessage,
        statusCode: 401,
        canRetry: false,
        isSessionExpired: true,
      );
    }
    if (error.statusCode == 400) {
      return const WarehouseListException(
        message: warehouseBadRequestMessage,
        statusCode: 400,
        canRetry: true,
      );
    }
    return WarehouseListException(
      message: warehouseUnavailableMessage,
      statusCode: error.statusCode,
      canRetry: true,
    );
  }
}
