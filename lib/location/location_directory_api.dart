import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../sink/reads_api.dart';
import 'location.dart';

/// Contrato de `GET /api/v1/warehouse/warehouses/{id}/location-directory`
/// (`contracts/rfid-reads.openapi.yaml` 0.3.0-draft).
class LocationDirectoryApi {
  /// Única constante de la ruta. `{id}` es el warehouse_id.
  static const String pathTemplate =
      '/api/v1/warehouse/warehouses/{id}/location-directory';
  static const int defaultLimit = 200;
  static const int maxLimit = 500;
  static const int maxPages = 50;

  static String pathFor(String warehouseId) =>
      pathTemplate.replaceAll('{id}', warehouseId);

  static Uri pageUri({
    required String apiBase,
    required String warehouseId,
    String? codePrefix,
    int limit = defaultLimit,
    String? cursor,
  }) {
    final safeLimit = limit.clamp(1, maxLimit);
    return Uri.parse('${_trim(apiBase)}${pathFor(warehouseId)}').replace(
      queryParameters: {
        'limit': '$safeLimit',
        if (codePrefix != null && codePrefix.trim().isNotEmpty) 'code': codePrefix.trim(),
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

class LocationDirectoryPage {
  const LocationDirectoryPage({required this.data, this.nextCursor});

  final List<Location> data;
  final String? nextCursor;

  factory LocationDirectoryPage.fromJson(
    Map<Object?, Object?> json, {
    required String warehouseId,
  }) {
    final raw = json['data'];
    final cursor = json['next_cursor'];
    return LocationDirectoryPage(
      data: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) Location.fromJson(item, warehouseId: warehouseId),
      ],
      nextCursor: cursor == null || '$cursor' == 'null' || '$cursor'.isEmpty
          ? null
          : '$cursor',
    );
  }
}

class CachedLocationDirectory {
  const CachedLocationDirectory({
    required this.warehouseId,
    required this.fetchedAt,
    required this.locations,
  });

  final String warehouseId;
  final DateTime fetchedAt;
  final List<Location> locations;

  Map<String, dynamic> toJson() => {
        'warehouse_id': warehouseId,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'locations': [for (final item in locations) item.toJson()],
      };

  factory CachedLocationDirectory.fromJson(Map<Object?, Object?> json) {
    final warehouseId = '${json['warehouse_id']}';
    final raw = json['locations'];
    return CachedLocationDirectory(
      warehouseId: warehouseId,
      fetchedAt: DateTime.tryParse('${json['fetched_at']}') ?? DateTime.now().toUtc(),
      locations: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) Location.fromJson(item, warehouseId: warehouseId),
      ],
    );
  }
}

abstract class LocationDirectoryCache {
  Future<CachedLocationDirectory?> read(String warehouseId);
  Future<void> write(CachedLocationDirectory directory);
}

class MemoryLocationDirectoryCache implements LocationDirectoryCache {
  final Map<String, CachedLocationDirectory> _store = {};

  @override
  Future<CachedLocationDirectory?> read(String warehouseId) async => _store[warehouseId];

  @override
  Future<void> write(CachedLocationDirectory directory) async {
    _store[directory.warehouseId] = directory;
  }
}

class FileLocationDirectoryCache implements LocationDirectoryCache {
  FileLocationDirectoryCache(this.directory);

  final Directory directory;

  File _file(String warehouseId) => File('${directory.path}/$warehouseId.json');

  @override
  Future<CachedLocationDirectory?> read(String warehouseId) async {
    final file = _file(warehouseId);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      return CachedLocationDirectory.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(CachedLocationDirectory cached) async {
    await directory.create(recursive: true);
    await _file(cached.warehouseId).writeAsString(jsonEncode(cached.toJson()));
  }
}

typedef TokenProvider = Future<String?> Function();
typedef TokenRefresher = Future<String?> Function();
typedef Clock = DateTime Function();

/// Repositorio HTTP del directorio, con caché persistente por bodega.
class HttpLocationRepository implements LocationRepository {
  HttpLocationRepository({
    required AppConfig config,
    required TokenProvider tokenProvider,
    required LocationDirectoryCache cache,
    TokenRefresher? tokenRefresher,
    http.Client? client,
    int pageLimit = LocationDirectoryApi.defaultLimit,
    int maxPages = LocationDirectoryApi.maxPages,
    Clock clock = DateTime.now,
  }) : this._(
          config,
          tokenProvider,
          tokenRefresher,
          cache,
          client ?? http.Client(),
          pageLimit,
          maxPages,
          clock,
        );

  HttpLocationRepository._(
    this._config,
    this._tokenProvider,
    this._tokenRefresher,
    this._cache,
    this._client,
    this.pageLimit,
    this.maxPages,
    this._clock,
  );

  final AppConfig _config;
  final TokenProvider _tokenProvider;
  final TokenRefresher? _tokenRefresher;
  final LocationDirectoryCache _cache;
  final http.Client _client;
  final int pageLimit;
  final int maxPages;
  final Clock _clock;

  @override
  Future<LocationDirectoryResult> listByWarehouse(
    String warehouseId, {
    bool forceRefresh = false,
  }) async {
    try {
      final locations = await _fetchAll(warehouseId);
      final cached = CachedLocationDirectory(
        warehouseId: warehouseId,
        fetchedAt: _clock().toUtc(),
        locations: locations,
      );
      await _cache.write(cached);
      return LocationDirectoryResult(
        locations: locations,
        fromCache: false,
        fetchedAt: cached.fetchedAt,
      );
    } catch (error) {
      final cached = await _cache.read(warehouseId);
      if (cached != null) {
        return LocationDirectoryResult(
          locations: cached.locations,
          fromCache: true,
          fetchedAt: cached.fetchedAt,
        );
      }
      if (forceRefresh) rethrow;
      rethrow;
    }
  }

  Future<List<Location>> _fetchAll(String warehouseId) async {
    if (_config.trimmedApiBase.isEmpty) {
      throw StateError('Configura la URL de la API en Ajustes.');
    }
    final items = <Location>[];
    String? cursor;
    final initialToken = await _tokenProvider();
    if (initialToken == null || initialToken.isEmpty) {
      throw const HttpReadsException(401);
    }
    var token = initialToken;
    var retriedAuth = false;
    for (var page = 0; page < maxPages; page++) {
      final uri = LocationDirectoryApi.pageUri(
        apiBase: _config.trimmedApiBase,
        warehouseId: warehouseId,
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
      }
      if (response.statusCode != 200) {
        throw HttpReadsException.fromResponse(response);
      }
      final parsed = LocationDirectoryPage.fromJson(
        jsonDecode(response.body) as Map<Object?, Object?>,
        warehouseId: warehouseId,
      );
      items.addAll(parsed.data);
      final next = parsed.nextCursor;
      if (next == null || next.isEmpty) {
        return items;
      }
      cursor = next;
    }
    return items;
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
}
