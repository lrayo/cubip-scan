import 'inventory_store.dart';

String inventoryToCsv(List<InventoryEntry> entries) {
  final buffer = StringBuffer('epc,tid,conteo,rssi,antena,ultima_lectura\n');
  for (final entry in entries) {
    buffer.writeln(
      [
        _csv(entry.epc),
        _csv(entry.tid ?? ''),
        entry.count,
        entry.rssi,
        entry.antenna,
        _csv(entry.lastSeen.toIso8601String()),
      ].join(','),
    );
  }
  return buffer.toString();
}

String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
