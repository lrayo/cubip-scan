import 'dart:convert';
import 'dart:io';

import 'package:cubip_scan/auth/token_subject.dart';
import 'package:cubip_scan/config/app_config.dart';
import 'package:cubip_scan/sink/api_problem.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:cubip_scan/warehouse/warehouse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fakeJwt(String sub) {
  String b64(Map<String, Object> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${b64({'alg': 'none'})}.${b64({'sub': sub})}.sig';
}

void main() {
  const apiBase = 'https://api.cubip.example';
  const bogota = {
    'id': FakeWarehouseRepository.bogotaId,
    'code': 'BOG-01',
    'name': 'Centro de distribución Bogotá',
    'status': 'ACTIVE',
    'tenant_id': '11111111-2222-4333-8444-555555555555',
    'width': 120,
  };
  const medellin = {
    'id': FakeWarehouseRepository.medellinId,
    'code': 'MDE-01',
    'name': 'Bodega Medellín',
    'status': 'INACTIVE',
  };
  const cali = {
    'id': FakeWarehouseRepository.caliId,
    'code': 'CLO-01',
    'name': 'Bodega Cali',
  };

  AppConfig config() => AppConfig(apiBaseUrl: apiBase);

  HttpWarehouseRepository repo({
    required http.Client client,
    WarehouseListCache? cache,
    TokenRefresher? refresher,
    String userId = 'user-a',
    String? token,
    int pageLimit = 200,
    int maxPages = 50,
  }) {
    return HttpWarehouseRepository(
      config: config(),
      tokenProvider: () async => token ?? fakeJwt(userId),
      tokenRefresher: refresher,
      userIdProvider: () async => userId,
      cache: cache ?? MemoryWarehouseListCache(),
      client: client,
      pageLimit: pageLimit,
      maxPages: maxPages,
    );
  }

  test('la ruta de bodegas es una constante única', () {
    expect(WarehouseListApi.path, '/api/v1/warehouse/warehouses');
    final uri = WarehouseListApi.pageUri(apiBase: apiBase, limit: 200, cursor: 'abc');
    expect(uri.path, WarehouseListApi.path);
    expect(uri.queryParameters['limit'], '200');
    expect(uri.queryParameters['cursor'], 'abc');
  });

  test('extrae el sub del access token y arma una clave de caché segura', () {
    expect(subjectFromAccessToken(fakeJwt('user-a')), 'user-a');
    expect(subjectFromAccessToken('no-es-un-jwt'), isNull);
    expect(cacheKeyForUser('user/a b'), 'user_a_b');
  });

  test('pagina con cursor hasta completar el listado', () async {
    final cursors = <String?>[];
    final client = MockClient((request) async {
      expect(request.url.path, WarehouseListApi.path);
      cursors.add(request.url.queryParameters['cursor']);
      if (!request.url.queryParameters.containsKey('cursor')) {
        return http.Response(
          jsonEncode({
            'data': [bogota, medellin],
            'next_cursor': 'eyJjb2RlIjoiTURFLTAxIn0',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(request.url.queryParameters['cursor'], 'eyJjb2RlIjoiTURFLTAxIn0');
      return http.Response(
        jsonEncode({
          'data': [cali],
          'next_cursor': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await repo(client: client, pageLimit: 2).list();
    expect(result.fromCache, isFalse);
    expect(result.warehouses.map((item) => item.code), ['BOG-01', 'MDE-01', 'CLO-01']);
    expect(result.warehouses.first.id, FakeWarehouseRepository.bogotaId);
    expect(cursors, [null, 'eyJjb2RlIjoiTURFLTAxIn0']);
  });

  test('respeta el tope de páginas y deja de pedir al alcanzarlo', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': '00000000-0000-4000-8000-00000000000$calls',
              'code': 'W-$calls',
              'name': 'Bodega $calls',
            },
          ],
          'next_cursor': 'cursor-$calls',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await repo(client: client, pageLimit: 1, maxPages: 2).list();
    expect(calls, 2);
    expect(result.warehouses, hasLength(2));
    expect(result.warehouses.map((item) => item.code), ['W-1', 'W-2']);
  });

  test('la caché no mezcla bodegas entre usuarios y sirve sin red', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final auth = request.headers['Authorization'] ?? '';
      if (auth.contains('token-a')) {
        return http.Response(jsonEncode({'data': [bogota], 'next_cursor': null}), 200);
      }
      if (auth.contains('token-b')) {
        return http.Response(jsonEncode({'data': [medellin], 'next_cursor': null}), 200);
      }
      throw Exception('offline');
    });
    final cache = MemoryWarehouseListCache();

    final forA = repo(client: client, cache: cache, userId: 'user-a', token: 'token-a');
    final firstA = await forA.list();
    expect(firstA.fromCache, isFalse);
    expect(firstA.warehouses.single.code, 'BOG-01');

    final forB = repo(client: client, cache: cache, userId: 'user-b', token: 'token-b');
    final firstB = await forB.list();
    expect(firstB.warehouses.single.code, 'MDE-01');

    final offline = MockClient((request) async => throw Exception('offline'));
    final cachedA = await repo(
      client: offline,
      cache: cache,
      userId: 'user-a',
      token: 'token-a',
    ).list();
    expect(cachedA.fromCache, isTrue);
    expect(cachedA.warehouses.single.code, 'BOG-01');

    final cachedB = await repo(
      client: offline,
      cache: cache,
      userId: 'user-b',
      token: 'token-b',
    ).list();
    expect(cachedB.fromCache, isTrue);
    expect(cachedB.warehouses.single.code, 'MDE-01');
    expect(calls, 2);
  });

  test('un 403 no se reintenta y muestra el mensaje de acceso', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'type': 'https://errors.wms-enterprise.com/forbidden',
          'title': 'Forbidden',
          'status': 403,
          'detail': 'Forbidden: Insufficient privileges for this operation',
        }),
        403,
        headers: {'content-type': 'application/problem+json'},
      );
    });
    final cache = MemoryWarehouseListCache();
    await cache.write(CachedWarehouseList(
      userId: 'user-a',
      fetchedAt: DateTime.utc(2026, 11, 20),
      warehouses: [Warehouse.fromJson(bogota)],
    ));

    await expectLater(
      repo(client: client, cache: cache, userId: 'user-a').list(),
      throwsA(
        isA<WarehouseListException>()
            .having((e) => e.isForbidden, 'isForbidden', isTrue)
            .having((e) => e.canRetry, 'canRetry', isFalse)
            .having((e) => e.message, 'message', warehouseForbiddenMessage),
      ),
    );
    expect(calls, 1);
  });

  test('un 401 refresca el token y reintenta una vez', () async {
    var calls = 0;
    var refreshes = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.headers['Authorization'] == 'Bearer expired') {
        return http.Response('unauthorized', 401);
      }
      expect(request.headers['Authorization'], 'Bearer fresh');
      return http.Response(jsonEncode({'data': [bogota], 'next_cursor': null}), 200);
    });

    final result = await repo(
      client: client,
      token: 'expired',
      userId: 'user-a',
      refresher: () async {
        refreshes++;
        return 'fresh';
      },
    ).list();
    expect(result.warehouses.single.code, 'BOG-01');
    expect(calls, 2);
    expect(refreshes, 1);
  });

  test('si el refresh ante un 401 falla, la sesión expiró', () async {
    final client = MockClient((request) async => http.Response('unauthorized', 401));
    await expectLater(
      repo(
        client: client,
        token: 'expired',
        refresher: () async => null,
      ).list(),
      throwsA(
        isA<WarehouseListException>()
            .having((e) => e.isSessionExpired, 'isSessionExpired', isTrue)
            .having((e) => e.message, 'message', sessionExpiredMessage),
      ),
    );
  });

  test('una lista vacía (data vacía o null) no es un error', () async {
    for (final body in [
      {'data': [], 'next_cursor': null},
      {'data': null},
      {},
    ]) {
      final client = MockClient((request) async {
        return http.Response(jsonEncode(body), 200);
      });
      final result = await repo(client: client).list();
      expect(result.warehouses, isEmpty, reason: 'body=$body');
      expect(result.fromCache, isFalse);
      expect(result.error, isNull);
    }
  });

  test('ignora campos extra del objeto Warehouse y tolera la ausencia de next_cursor', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'data': [bogota]}), 200);
    });
    final result = await repo(client: client).list();
    expect(result.warehouses.single.code, 'BOG-01');
    expect(result.warehouses.single.name, 'Centro de distribución Bogotá');
  });

  test('la caché en archivo queda aislada por usuario', () async {
    final dir = Directory.systemTemp.createTempSync('cubip-wh-cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = FileWarehouseListCache(dir);
    await cache.write(CachedWarehouseList(
      userId: 'user-a',
      fetchedAt: DateTime.utc(2026, 11, 20),
      warehouses: [Warehouse.fromJson(bogota)],
    ));
    await cache.write(CachedWarehouseList(
      userId: 'user-b',
      fetchedAt: DateTime.utc(2026, 11, 20),
      warehouses: [Warehouse.fromJson(medellin)],
    ));
    expect((await FileWarehouseListCache(dir).read('user-a'))!.warehouses.single.code, 'BOG-01');
    expect((await FileWarehouseListCache(dir).read('user-b'))!.warehouses.single.code, 'MDE-01');
  });
}
