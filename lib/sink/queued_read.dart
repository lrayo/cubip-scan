import '../models/tag_read.dart';

class QueuedRead {
  QueuedRead({
    required this.clientReadId,
    required this.epc,
    required this.rssi,
    required this.antenna,
    required this.readAt,
    required this.warehouseId,
    this.tid,
    this.attempts = 0,
    this.nextRetryAt,
    this.idempotencyKey,
    this.locationId,
    this.blocked = false,
    this.blockReason,
    this.blockCode,
  });

  final String clientReadId;
  final String epc;
  final String? tid;
  final int rssi;
  final int antenna;
  final DateTime readAt;
  final String warehouseId;
  int attempts;
  DateTime? nextRetryAt;
  String? idempotencyKey;
  String? locationId;
  bool blocked;
  String? blockReason;
  String? blockCode;

  bool isReady(DateTime now) {
    if (blocked) return false;
    final due = nextRetryAt;
    return due == null || !due.isAfter(now);
  }

  factory QueuedRead.fromTag({
    required TagRead read,
    required String warehouseId,
    required String clientReadId,
    String? locationId,
  }) {
    return QueuedRead(
      clientReadId: clientReadId,
      epc: read.epc,
      tid: read.tid,
      rssi: read.rssi,
      antenna: read.antenna,
      readAt: read.timestamp,
      warehouseId: warehouseId,
      locationId: locationId,
    );
  }

  Map<String, dynamic> toJson() => {
        'client_read_id': clientReadId,
        'epc': epc,
        if (tid != null) 'tid': tid,
        'rssi': rssi,
        'antenna': antenna,
        'read_at': readAt.toIso8601String(),
        'warehouse_id': warehouseId,
        'attempts': attempts,
        if (nextRetryAt != null) 'next_retry_at': nextRetryAt!.toIso8601String(),
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        if (locationId != null) 'location_id': locationId,
        'blocked': blocked,
        if (blockReason != null) 'block_reason': blockReason,
        if (blockCode != null) 'block_code': blockCode,
      };

  factory QueuedRead.fromJson(Map<Object?, Object?> json) {
    return QueuedRead(
      clientReadId: '${json['client_read_id']}',
      epc: '${json['epc']}',
      tid: json['tid'] as String?,
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      antenna: (json['antenna'] as num?)?.toInt() ?? 1,
      readAt: DateTime.tryParse('${json['read_at']}') ?? DateTime.now(),
      warehouseId: '${json['warehouse_id']}',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: json['next_retry_at'] == null
          ? null
          : DateTime.tryParse('${json['next_retry_at']}'),
      idempotencyKey: json['idempotency_key'] as String?,
      locationId: json['location_id'] as String?,
      blocked: json['blocked'] == true,
      blockReason: json['block_reason'] as String?,
      blockCode: json['block_code'] as String?,
    );
  }
}
