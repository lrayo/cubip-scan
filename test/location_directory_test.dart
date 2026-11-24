import 'dart:convert';
import 'dart:io';

import 'package:cubip_scan/config/app_config.dart';
import 'package:cubip_scan/location/location.dart';
import 'package:cubip_scan/location/location_directory_api.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const warehouseId = FakeWarehouseRepository.bogotaId;
  const apiBase = 'https://api.cubip.example';

  AppConfig config() => AppConfig(apiBaseUrl: apiBase);

  Map<String, dynamic> entry({
    required String id,
    required String code,
    String name = 'Nombre',
    String? labelEpc,
  }) =>
      {
        'id': id,
        'code': code,
        'name': name,
        'label_epc': labelEpc,
      };

  test('la ruta del directorio es una constante única', () {
    expect(
      LocationDirectoryApi.pathTemplate,
      '/api/v1/warehouse/warehouses/{id}/location-directory',
    );
    final uri = LocationDirectoryApi.pageUri(
      apiBase: apiBase,
      warehouseId: warehouseId,
      codePrefix: 'A01-01',
      limit: 200,
      cursor: 'abc',
    );
    expect(uri.path, '/api/v1/warehouse/warehouses/$warehouseId/location-directory');
    expect(uri.queryParameters['code'], 'A01-01');
    expect(uri.queryParameters['limit'], '200');
    expect(uri.queryParameters['cursor'], 'abc');
  });

  test('pagina con cursor hasta completar el directorio', () async {
    final cursors = <String?>[];
    final client = MockClient((request) async {
      expect(request.url.path, LocationDirectoryApi.pathFor(warehouseId));
      expect(request.headers['Authorization'], 'Bearer token-1');
      cursors.add(request.url.queryParameters['cursor']);
      if (!request.url.queryParameters.containsKey('cursor')) {
        return http.Response(
          jsonEncode({
            'data': [
              entry(id: '11111111-1111-4111-8111-111111111111', code: 'A01-01-01', labelEpc: 'E28068940000501EC0B1D2E3'),
              entry(id: '22222222-2222-4222-8222-222222222222', code: 'A01-01-02', labelEpc: null),
            ],
            'next_cursor': 'eyJjb2RlIjoiQTAxLTAxLTAyIn0',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(request.url.queryParameters['cursor'], 'eyJjb2RlIjoiQTAxLTAxLTAyIn0');
      return http.Response(
        jsonEncode({
          'data': [
            entry(id: '33333333-3333-4333-8333-333333333333', code: 'A01-01-03', labelEpc: 'E28068940000501EC0B1D2E4'),
          ],
          'next_cursor': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final repo = HttpLocationRepository(
      config: config(),
      tokenProvider: () async => 'token-1',
      cache: MemoryLocationDirectoryCache(),
      client: client,
      pageLimit: 2,
    );
    final result = await repo.listByWarehouse(warehouseId);
    expect(result.fromCache, isFalse);
    expect(result.locations, hasLength(3));
    expect(result.locations.map((item) => item.code), ['A01-01-01', 'A01-01-02', 'A01-01-03']);
    expect(result.locations[1].labelEpc, isNull);
    expect(cursors, [null, 'eyJjb2RlIjoiQTAxLTAxLTAyIn0']);
  });

  test('usa la caché persistente si no hay red', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'data': [
              entry(id: FakeLocationRepository.binA12Id, code: 'A01-01-01', labelEpc: FakeLocationRepository.binA12Epc),
            ],
            'next_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      throw Exception('offline');
    });
    final cache = MemoryLocationDirectoryCache();
    final repo = HttpLocationRepository(
      config: config(),
      tokenProvider: () async => 'token-1',
      cache: cache,
      client: client,
    );

    final first = await repo.listByWarehouse(warehouseId);
    expect(first.fromCache, isFalse);
    expect(first.locations.single.code, 'A01-01-01');
    expect((await cache.read(warehouseId))?.locations.single.id, FakeLocationRepository.binA12Id);

    final second = await repo.listByWarehouse(warehouseId, forceRefresh: true);
    expect(second.fromCache, isTrue);
    expect(second.locations.single.code, 'A01-01-01');
    expect(calls, 2);
  });

  test('la caché en archivo sobrevive a una nueva instancia', () async {
    final dir = Directory.systemTemp.createTempSync('cubip-loc-cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final written = FileLocationDirectoryCache(dir);
    await written.write(CachedLocationDirectory(
      warehouseId: warehouseId,
      fetchedAt: DateTime.utc(2026, 11, 19, 22),
      locations: [
        Location(
          id: FakeLocationRepository.binA12Id,
          warehouseId: warehouseId,
          code: 'A01-01-01',
          name: 'Zona A',
          labelEpc: FakeLocationRepository.binA12Epc,
        ),
      ],
    ));
    final read = await FileLocationDirectoryCache(dir).read(warehouseId);
    expect(read, isNotNull);
    expect(read!.locations.single.code, 'A01-01-01');
    expect(read.locations.single.labelEpc, FakeLocationRepository.binA12Epc);
  });

  test('falla sin caché cuando la API responde un problema RFC 9457', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'type': 'https://errors.wms-enterprise.com/warehouse/warehouse-not-found',
          'title': 'Not Found',
          'status': 404,
          'code': 'WAREHOUSE_NOT_FOUND',
        }),
        404,
        headers: {'content-type': 'application/problem+json'},
      );
    });
    final repo = HttpLocationRepository(
      config: config(),
      tokenProvider: () async => 'token-1',
      cache: MemoryLocationDirectoryCache(),
      client: client,
    );
    expect(() => repo.listByWarehouse(warehouseId), throwsA(isA<Exception>()));
  });
}
