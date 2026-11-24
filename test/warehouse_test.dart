import 'package:cubip_scan/auth/auth_session.dart';
import 'package:cubip_scan/rfid/demo_rfid_client.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el repositorio falso devuelve las bodegas de demostración', () async {
    const repo = FakeWarehouseRepository();
    final list = (await repo.list()).warehouses;
    expect(list, hasLength(3));
    expect(list.first.id, FakeWarehouseRepository.bogotaId);
    expect(list.first.code, 'BOG-01');
    expect(list.map((w) => w.name), contains('Bodega Cali'));
  });

  test('el controlador selecciona y limpia la bodega', () async {
    final controller = AppController(
      auth: MemoryAuthSession(loggedIn: true, demo: true),
      demoClient: DemoRfidClient(),
      platformClient: DemoRfidClient(),
    );
    addTearDown(controller.dispose);
    await controller.enterDemo();
    await controller.loadWarehouses();
    expect(controller.warehouses, isNotEmpty);
    controller.selectWarehouse(controller.warehouses.first);
    expect(controller.selectedWarehouse?.id, FakeWarehouseRepository.bogotaId);
    controller.clearWarehouse();
    expect(controller.selectedWarehouse, isNull);
  });
}
