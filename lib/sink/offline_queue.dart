import 'dart:convert';
import 'dart:io';

import 'queued_read.dart';

abstract class OfflineQueue {
  Future<void> enqueue(QueuedRead read);
  Future<List<QueuedRead>> pending();
  Future<List<QueuedRead>> ready({required DateTime now, int limit = 500});
  Future<void> remove(Iterable<String> clientReadIds);
  Future<void> update(QueuedRead read);
  int get length;
}

class MemoryOfflineQueue implements OfflineQueue {
  MemoryOfflineQueue([List<QueuedRead>? seed]) {
    if (seed != null) {
      for (final item in seed) {
        _items[item.clientReadId] = item;
      }
    }
  }

  final Map<String, QueuedRead> _items = {};

  @override
  int get length => _items.length;

  @override
  Future<void> enqueue(QueuedRead read) async {
    _items.putIfAbsent(read.clientReadId, () => read);
  }

  @override
  Future<List<QueuedRead>> pending() async =>
      _items.values.toList(growable: false);

  @override
  Future<List<QueuedRead>> ready({required DateTime now, int limit = 500}) async {
    final items = _items.values.where((item) => item.isReady(now)).toList();
    if (items.isEmpty) return items;
    final keyed = items
        .where((item) => item.idempotencyKey != null && item.idempotencyKey!.isNotEmpty)
        .toList();
    if (keyed.isNotEmpty) {
      final key = keyed.first.idempotencyKey;
      final group = keyed.where((item) => item.idempotencyKey == key).toList();
      return group.length > limit ? group.sublist(0, limit) : group;
    }
    final locationId = items.first.locationId;
    final group = items.where((item) => item.locationId == locationId).toList();
    return group.length > limit ? group.sublist(0, limit) : group;
  }

  @override
  Future<void> remove(Iterable<String> clientReadIds) async {
    for (final id in clientReadIds) {
      _items.remove(id);
    }
  }

  @override
  Future<void> update(QueuedRead read) async {
    _items[read.clientReadId] = read;
  }
}

class FileOfflineQueue implements OfflineQueue {
  FileOfflineQueue(this.file, {MemoryOfflineQueue? memory})
      : _memory = memory ?? MemoryOfflineQueue();

  final File file;
  final MemoryOfflineQueue _memory;

  Future<void> load() async {
    if (!await file.exists()) return;
    final raw = jsonDecode(await file.readAsString());
    if (raw is! List) return;
    for (final item in raw) {
      if (item is Map) {
        await _memory.enqueue(QueuedRead.fromJson(item));
      }
    }
  }

  Future<void> _persist() async {
    await file.parent.create(recursive: true);
    final pending = await _memory.pending();
    await file.writeAsString(jsonEncode([for (final item in pending) item.toJson()]));
  }

  @override
  int get length => _memory.length;

  @override
  Future<void> enqueue(QueuedRead read) async {
    await _memory.enqueue(read);
    await _persist();
  }

  @override
  Future<List<QueuedRead>> pending() => _memory.pending();

  @override
  Future<List<QueuedRead>> ready({required DateTime now, int limit = 500}) =>
      _memory.ready(now: now, limit: limit);

  @override
  Future<void> remove(Iterable<String> clientReadIds) async {
    await _memory.remove(clientReadIds);
    await _persist();
  }

  @override
  Future<void> update(QueuedRead read) async {
    await _memory.update(read);
    await _persist();
  }
}
