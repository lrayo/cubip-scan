import '../models/tag_read.dart';

/// Entrada consolidada: un EPC único, con conteo y último RSSI.
class InventoryEntry {
  InventoryEntry({
    required this.epc,
    this.tid,
    required this.count,
    required this.rssi,
    required this.antenna,
    required this.lastSeen,
  });

  final String epc;
  String? tid;
  int count;
  int rssi;
  int antenna;
  DateTime lastSeen;

  InventoryEntry copy() => InventoryEntry(
        epc: epc,
        tid: tid,
        count: count,
        rssi: rssi,
        antenna: antenna,
        lastSeen: lastSeen,
      );
}

class InventoryStore {
  final Map<String, InventoryEntry> _byEpc = {};

  int get uniqueCount => _byEpc.length;

  int get totalReads =>
      _byEpc.values.fold<int>(0, (sum, entry) => sum + entry.count);

  List<InventoryEntry> get entries {
    final list = _byEpc.values.map((e) => e.copy()).toList();
    list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  InventoryEntry? operator [](String epc) => _byEpc[epc]?.copy();

  InventoryEntry add(TagRead read) {
    final key = read.epc;
    if (key.isEmpty) {
      throw const FormatException('No se puede registrar un EPC vacío');
    }
    final existing = _byEpc[key];
    if (existing == null) {
      final created = InventoryEntry(
        epc: key,
        tid: read.hasTid ? read.tid : null,
        count: 1,
        rssi: read.rssi,
        antenna: read.antenna,
        lastSeen: read.timestamp,
      );
      _byEpc[key] = created;
      return created.copy();
    }
    existing.count += 1;
    existing.rssi = read.rssi;
    existing.antenna = read.antenna;
    existing.lastSeen = read.timestamp;
    if (read.hasTid) {
      existing.tid = read.tid;
    }
    return existing.copy();
  }

  void clear() => _byEpc.clear();
}
