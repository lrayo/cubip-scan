/// Lectura cruda de un tag, alineada con LogBaseEpcInfo del SDK.
class TagRead {
  const TagRead({
    required this.epc,
    required this.rssi,
    required this.antenna,
    required this.timestamp,
    this.tid,
    this.clientReadId,
  });

  final String epc;
  final String? tid;
  final int rssi;
  final int antenna;
  final DateTime timestamp;
  final String? clientReadId;

  bool get hasTid => tid != null && tid!.trim().isNotEmpty;

  factory TagRead.fromMap(Map<Object?, Object?> map, {DateTime? now}) {
    final epc = _cleanHex(map['epc']);
    if (epc.isEmpty) {
      throw const FormatException('La lectura no incluye un EPC válido');
    }
    final tid = _cleanHex(map['tid']);
    final rssiDbm = (map['rssidBm'] as num?)?.toInt();
    final rssiRaw = (map['rssi'] as num?)?.toInt() ?? 0;
    final rssi = (rssiDbm != null && rssiDbm != 0) ? rssiDbm : rssiRaw;
    final antenna = (map['antenna'] as num?)?.toInt() ?? 1;
    final rawTs = map['timestamp'];
    DateTime timestamp;
    if (rawTs is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String && rawTs.trim().isNotEmpty) {
      timestamp = DateTime.tryParse(rawTs) ?? (now ?? DateTime.now());
    } else {
      timestamp = now ?? DateTime.now();
    }
    return TagRead(
      epc: epc,
      tid: tid.isEmpty ? null : tid,
      rssi: rssi,
      antenna: antenna,
      timestamp: timestamp,
      clientReadId: map['client_read_id'] as String? ?? map['clientReadId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'epc': epc,
        if (hasTid) 'tid': tid,
        'rssi': rssi,
        'antenna': antenna,
        'timestamp': timestamp.toIso8601String(),
        if (clientReadId != null) 'client_read_id': clientReadId,
      };

  static String _cleanHex(Object? value) {
    if (value == null) return '';
    return value.toString().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }
}
