import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/tag_read.dart';
import 'offline_queue.dart';
import 'queued_read.dart';
import 'reads_sink.dart';
import '../warehouse/warehouse.dart';

/// Sink falso del modo demo: no llama al WMS, pero mantiene pendientes y enviadas.
class FakeReadsSink extends ChangeNotifier implements TrackingReadsSink {
  FakeReadsSink({
    OfflineQueue? queue,
    this.autoFlush = true,
    String Function()? idGenerator,
  })  : _queue = queue ?? MemoryOfflineQueue(),
        _idGenerator = idGenerator ?? const Uuid().v4;

  final OfflineQueue _queue;
  final String Function() _idGenerator;
  final bool autoFlush;
  int _sentCount = 0;

  @override
  Listenable get listenable => this;

  @override
  int get pendingCount => _queue.length;

  @override
  int get sentCount => _sentCount;

  @override
  String? get lastError => null;

  /// Permite armar una captura con un estado de envío conocido.
  void seed({int pending = 0, int sent = 0}) {
    _sentCount = sent;
    for (var i = 0; i < pending; i++) {
      _queue.enqueue(
        QueuedRead(
          clientReadId: 'seed-$i',
          epc: 'DEMO$i',
          rssi: -40,
          antenna: 1,
          readAt: DateTime(2026, 11, 19, 22),
          warehouseId: FakeWarehouseRepository.bogotaId,
        ),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> publish(TagRead read) async {
    final id = read.clientReadId ?? _idGenerator();
    await _queue.enqueue(
      QueuedRead.fromTag(
        read: read,
        warehouseId: 'demo',
        clientReadId: id,
      ),
    );
    notifyListeners();
    if (autoFlush) {
      await flush();
    }
  }

  Future<void> flush() async {
    final pending = await _queue.pending();
    if (pending.isEmpty) return;
    await _queue.remove(pending.map((item) => item.clientReadId));
    _sentCount += pending.length;
    notifyListeners();
  }
}
