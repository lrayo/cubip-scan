import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/rfid/csv_export.dart';
import 'package:cubip_scan/rfid/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 19, 21, 15);

  test('parsea una lectura del canal nativo, con TID y rssidBm', () {
    final read = TagRead.fromMap({
      'epc': 'e280 1170 0000 0214',
      'tid': 'e2801100ffff',
      'rssi': 90,
      'rssidBm': -42,
      'antenna': 1,
      'timestamp': now.millisecondsSinceEpoch,
    }, now: now);
    expect(read.epc, 'E280117000000214');
    expect(read.tid, 'E2801100FFFF');
    expect(read.hasTid, isTrue);
    expect(read.rssi, -42);
    expect(read.antenna, 1);
    expect(read.timestamp.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  });

  test('tolera un TID ausente y usa rssi si no hay rssidBm', () {
    final read = TagRead.fromMap({
      'epc': '300833B2DDD9014000000001',
      'rssi': -47,
    }, now: now);
    expect(read.hasTid, isFalse);
    expect(read.rssi, -47);
    expect(read.timestamp.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  });

  test('falla si falta el EPC', () {
    expect(
      () => TagRead.fromMap({'rssi': -10}, now: now),
      throwsA(isA<FormatException>()),
    );
  });

  test('exporta CSV con encabezados y una fila por EPC', () {
    final store = InventoryStore();
    store.add(TagRead.fromMap({
      'epc': 'ABC',
      'rssi': -40,
      'antenna': 1,
      'timestamp': now.toIso8601String(),
    }, now: now));
    final csv = inventoryToCsv(store.entries);
    expect(csv.split('\n').first, 'epc,tid,conteo,rssi,antena,ultima_lectura');
    expect(csv, contains('ABC,,1,-40,1,'));
  });
}
