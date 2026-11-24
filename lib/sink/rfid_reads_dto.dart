import 'package:uuid/uuid.dart';

import 'queued_read.dart';

/// Cuerpo de la ingesta RFID según `contracts/rfid-reads.openapi.yaml`
/// (borrador 0.3.0-draft).
class RfidReadsDto {
  /// Única constante de la ruta POST. Hoy coincide con el YAML 0.3.0-draft.
  static const String postPath = '/api/v1/rfid/read-batches';

  static const int maxBatchSize = 500;
  static const String appName = 'cubip-scan';
  static const String appVersion = '1.0.0+1';

  static Map<String, dynamic> batchToJson({
    required String warehouseId,
    required String readerId,
    required List<QueuedRead> reads,
    String? locationId,
    String? platform,
  }) {
    return {
      'warehouse_id': warehouseId,
      'reader_id': normalizeReaderId(readerId),
      if (locationId != null && locationId.isNotEmpty) 'location_id': locationId,
      'app': {
        'name': appName,
        'version': appVersion,
        if (platform == 'android' || platform == 'ios') 'platform': platform,
      },
      'reads': [for (final read in reads) itemToJson(read)],
    };
  }

  static Map<String, dynamic> itemToJson(QueuedRead read) {
    final item = <String, dynamic>{
      'client_read_id': read.clientReadId,
      'epc': read.epc,
      'rssi_dbm': read.rssi,
      'antenna': read.antenna,
      'read_at': read.readAt.toUtc().toIso8601String(),
    };
    final tid = read.tid;
    if (tid != null && tid.isNotEmpty) {
      item['tid'] = tid;
    }
    return item;
  }

  /// Serial del lector en mayúsculas, solo A-Z/0-9, 6–50 caracteres.
  static String normalizeReaderId(String raw) {
    final sanitized = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (sanitized.length >= 6) {
      return sanitized.length > 50 ? sanitized.substring(0, 50) : sanitized;
    }
    const fallback = 'READER';
    final padded = (fallback + sanitized).padRight(6, '0');
    return padded.length > 50 ? padded.substring(0, 50) : padded;
  }

  /// Misma clave para reintentos del mismo lote (cabecera Idempotency-Key).
  static String idempotencyKeyFor(List<QueuedRead> batch) {
    final joined = (batch.map((e) => e.clientReadId).toList()..sort()).join(',');
    return const Uuid().v5(Namespace.oid.value, joined);
  }
}
