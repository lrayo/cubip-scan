import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/rfid/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t1 = DateTime.utc(2026, 11, 19, 21, 0, 0);
  final t2 = DateTime.utc(2026, 11, 19, 21, 0, 2);

  TagRead read(String epc, {String? tid, int rssi = -40, DateTime? at}) {
    return TagRead(
      epc: epc,
      tid: tid,
      rssi: rssi,
      antenna: 1,
      timestamp: at ?? t1,
    );
  }

  test('deduplica por EPC y acumula el conteo', () {
    final store = InventoryStore();
    store.add(read('E280117000000001', rssi: -40, at: t1));
    store.add(read('E280117000000001', rssi: -36, at: t2, tid: 'E2801100ABCD'));
    store.add(read('E280117000000002', rssi: -50));
    expect(store.uniqueCount, 2);
    expect(store.totalReads, 3);
    final first = store['E280117000000001']!;
    expect(first.count, 2);
    expect(first.rssi, -36);
    expect(first.tid, 'E2801100ABCD');
    expect(first.lastSeen, t2);
    expect(store.entries.first.epc, 'E280117000000001');
  });

  test('clear vacía el inventario', () {
    final store = InventoryStore();
    store.add(read('AA'));
    store.clear();
    expect(store.uniqueCount, 0);
    expect(store.totalReads, 0);
  });

  test('rechaza un EPC vacío', () {
    final store = InventoryStore();
    expect(
      () => store.add(read('')),
      throwsA(isA<FormatException>()),
    );
  });
}
