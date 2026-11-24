import 'package:cubip_scan/auth/auth_session.dart';
import 'package:cubip_scan/location/location.dart';
import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/rfid/demo_rfid_client.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubip_scan/sink/api_problem.dart';

void main() {
  final locations = FakeLocationRepository.forWarehouse(FakeWarehouseRepository.bogotaId);

  TagRead read(String epc, int rssi) => TagRead(
        epc: epc,
        rssi: rssi,
        antenna: 1,
        timestamp: DateTime.utc(2026, 11, 19, 22),
      );

  test('el repositorio falso lista ubicaciones por bodega', () async {
    const repo = FakeLocationRepository();
    final bogota = (await repo.listByWarehouse(FakeWarehouseRepository.bogotaId)).locations;
    expect(bogota, isNotEmpty);
    expect(bogota.first.id, FakeLocationRepository.binA12Id);
    expect(bogota.first.code, FakeLocationRepository.binA12Code);
    expect(bogota.every((item) => item.warehouseId == FakeWarehouseRepository.bogotaId), isTrue);
    expect(bogota.any((item) => item.labelEpc == null && item.code == 'A01-01-02'), isTrue);
    final cali = (await repo.listByWarehouse(FakeWarehouseRepository.caliId)).locations;
    expect(cali, hasLength(1));
  });

  test('resuelve la lectura con más señal contra la lista', () {
    final resolved = resolveLocationFromReads(
      reads: [
        read('E2801170000002143A5B6C7D', -20),
        read(FakeLocationRepository.binA12Epc, -35),
      ],
      locations: locations,
    );
    expect(resolved, isNull, reason: 'gana la etiqueta más cercana, que no es un bin');

    final hit = resolveLocationFromReads(
      reads: [
        read('E2801170000002143A5B6C7D', -48),
        read(FakeLocationRepository.binA12Epc, -22),
      ],
      locations: locations,
    );
    expect(hit?.id, FakeLocationRepository.binA12Id);
    expect(hit?.code, FakeLocationRepository.binA12Code);
  });

  test('el controlador elige, quita y fija una ubicación', () async {
    final controller = AppController(
      auth: MemoryAuthSession(loggedIn: true, demo: true),
      demoClient: DemoRfidClient(),
      platformClient: DemoRfidClient(),
      locations: const FakeLocationRepository(),
    );
    addTearDown(controller.dispose);
    await controller.enterDemo();
    await controller.loadWarehouses();
    controller.selectWarehouse(controller.warehouses.first);
    await controller.loadLocations();
    expect(controller.locations, isNotEmpty);

    controller.selectLocation(controller.locations.first);
    expect(controller.selectedLocation?.id, FakeLocationRepository.binA12Id);
    controller.clearLocation();
    expect(controller.selectedLocation, isNull);

    final pinned = controller.resolvePinnedLocation([
      read(FakeLocationRepository.binA12Epc, -18),
    ]);
    expect(pinned?.code, FakeLocationRepository.binA12Code);
  });

  test('normaliza el EPC leído a hex en mayúsculas sin espacios ni 0x', () {
    const raw = '  0xe280 6894-0000_501e:c0b1 d2e3  ';
    expect(normalizeLabelEpc(raw), 'E28068940000501EC0B1D2E3');
    expect(normalizeLabelEpc('E28068940000501EC0B1D2E3'), 'E28068940000501EC0B1D2E3');
  });

  test('una ubicación sin label_epc no coincide al fijar ubicación', () {
    const unlabeled = Location(
      id: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'A01-01-02',
      name: 'Sin etiqueta',
    );
    final resolved = resolveLocationFromReads(
      reads: [read('E28068940000501EC0B1D2E3', -10)],
      locations: [unlabeled, ...locations],
    );
    expect(resolved, isNull);
    expect(unlabeled.labelEpc, isNull);
  });

  test('resuelve un EPC con formato sucio contra label_epc', () {
    final hit = resolveLocationFromReads(
      reads: [read('  0x${FakeLocationRepository.binA12Epc.toLowerCase()}  ', -12)],
      locations: locations,
    );
    expect(hit?.id, FakeLocationRepository.binA12Id);
  });

  test('filtra el directorio por prefijo de código', () {
    final filtered = filterLocationsByCodePrefix(locations, 'a01-01');
    expect(filtered.map((item) => item.code), ['A01-01-01', 'A01-01-02']);
    expect(filterLocationsByCodePrefix(locations, 'MUELLE'), hasLength(1));
  });

  test('parsea un problema RFC 9457 y Retry-After', () {
    const body = '''
{"type":"https://errors.wms-enterprise.com/rfid/reader-not-registered","title":"Unprocessable Content","status":422,"code":"READER_NOT_REGISTERED","detail":"Reader missing","correlation_id":"abc"}
''';
    final problem = ApiProblem.tryParse(body, 422)!;
    expect(problem.isReaderNotRegistered, isTrue);
    expect(problem.status, 422);
    expect(problem.correlationId, 'abc');

    final now = DateTime.utc(2026, 11, 19, 22);
    expect(parseRetryAfter('30', now), now.add(const Duration(seconds: 30)));
    expect(parseRetryAfter('Thu, 19 Nov 2026 22:10:00 GMT', now), DateTime.utc(2026, 11, 19, 22, 10));
  });
}
