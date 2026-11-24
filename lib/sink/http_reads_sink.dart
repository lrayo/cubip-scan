// ignore_for_file: prefer_initializing_formals
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/tag_read.dart';
import 'api_problem.dart';
import 'offline_queue.dart';
import 'queued_read.dart';
import 'reads_api.dart';
import 'reads_sink.dart';
import 'rfid_reads_dto.dart';

typedef TokenProvider = Future<String?> Function();
typedef TokenRefresher = Future<String?> Function();
typedef WarehouseIdProvider = String? Function();
typedef ReaderIdProvider = String? Function();
typedef LocationIdProvider = String? Function();
typedef Clock = DateTime Function();
typedef IdGenerator = String Function();

enum _AuthRetry { sent, paused, handled }

/// Publica lecturas en lotes de hasta 500, con cola persistente y backoff.
class HttpReadsSink extends ChangeNotifier implements TrackingReadsSink {
  HttpReadsSink({
    required ReadsApi api,
    required OfflineQueue queue,
    required TokenProvider tokenProvider,
    required WarehouseIdProvider warehouseIdProvider,
    required ReaderIdProvider readerIdProvider,
    LocationIdProvider? locationIdProvider,
    TokenRefresher? tokenRefresher,
    Clock clock = DateTime.now,
    IdGenerator? idGenerator,
    this.maxBatchSize = RfidReadsDto.maxBatchSize,
  })  : _api = api,
        _queue = queue,
        _tokenProvider = tokenProvider,
        _warehouseIdProvider = warehouseIdProvider,
        _readerIdProvider = readerIdProvider,
        _locationIdProvider = locationIdProvider ?? (() => null),
        _tokenRefresher = tokenRefresher,
        _clock = clock,
        _idGenerator = idGenerator ?? const Uuid().v4;

  final ReadsApi _api;
  final OfflineQueue _queue;
  final TokenProvider _tokenProvider;
  final WarehouseIdProvider _warehouseIdProvider;
  final ReaderIdProvider _readerIdProvider;
  final LocationIdProvider _locationIdProvider;
  final TokenRefresher? _tokenRefresher;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final int maxBatchSize;

  int _sentCount = 0;
  bool _flushing = false;
  bool _paused = false;
  String? _lastError;

  @override
  Listenable get listenable => this;

  @override
  int get pendingCount => _queue.length;

  @override
  int get sentCount => _sentCount;

  @override
  String? get lastError => _lastError;

  bool get isFlushing => _flushing;

  bool get isPaused => _paused;

  static Duration backoffFor(int attempts) {
    final shift = (attempts - 1).clamp(0, 16);
    return Duration(seconds: min(300, 1 << shift));
  }

  @override
  Future<void> publish(TagRead read) async {
    final warehouseId = _warehouseIdProvider();
    if (warehouseId == null || warehouseId.isEmpty) {
      throw StateError('Selecciona una bodega antes de enviar lecturas.');
    }
    final id = (read.clientReadId != null && read.clientReadId!.isNotEmpty)
        ? read.clientReadId!
        : _idGenerator();
    await _queue.enqueue(
      QueuedRead.fromTag(
        read: read,
        warehouseId: warehouseId,
        clientReadId: id,
        locationId: _locationIdProvider(),
      ),
    );
    notifyListeners();
    await flush();
  }

  Future<void> flush() async {
    if (_flushing || _paused) return;
    _flushing = true;
    notifyListeners();
    try {
      while (!_paused) {
        final batch = await _queue.ready(now: _clock(), limit: maxBatchSize);
        if (batch.isEmpty) return;
        var token = await _tokenProvider();
        if (token == null || token.isEmpty) {
          await _scheduleRetry(batch, _clock());
          return;
        }
        final readerId = _readerIdProvider();
        if (readerId == null || readerId.isEmpty) {
          return;
        }
        final prepared = await _prepareBatch(batch);
        try {
          await _post(prepared, token, readerId);
          await _queue.remove(prepared.map((item) => item.clientReadId));
          _sentCount += prepared.length;
          _lastError = null;
          notifyListeners();
        } on HttpReadsException catch (error) {
          if (error.statusCode == 401) {
            final outcome = await _retryAfterRefresh(prepared, readerId);
            if (outcome == _AuthRetry.sent) {
              notifyListeners();
              continue;
            }
            if (outcome == _AuthRetry.paused) {
              await _pauseForExpiredSession();
            }
            notifyListeners();
            return;
          }
          await _handleFailure(prepared, error);
          notifyListeners();
          return;
        } catch (_) {
          await _scheduleRetry(prepared, _clock());
          notifyListeners();
          return;
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  Future<void> _post(List<QueuedRead> batch, String token, String readerId) {
    return _api.postBatch(
      batch,
      token,
      warehouseId: batch.first.warehouseId,
      readerId: readerId,
      locationId: batch.first.locationId,
      idempotencyKey: batch.first.idempotencyKey,
      correlationId: _idGenerator(),
    );
  }

  /// Reintenta el mismo lote una vez con un token nuevo y la misma Idempotency-Key.
  Future<_AuthRetry> _retryAfterRefresh(List<QueuedRead> batch, String readerId) async {
    final refresher = _tokenRefresher;
    if (refresher == null) return _AuthRetry.paused;
    final token = await refresher();
    if (token == null || token.isEmpty) return _AuthRetry.paused;
    try {
      await _post(batch, token, readerId);
      await _queue.remove(batch.map((item) => item.clientReadId));
      _sentCount += batch.length;
      _lastError = null;
      return _AuthRetry.sent;
    } on HttpReadsException catch (error) {
      if (error.statusCode == 401) return _AuthRetry.paused;
      await _handleFailure(batch, error);
      return _AuthRetry.handled;
    } catch (_) {
      await _scheduleRetry(batch, _clock());
      return _AuthRetry.handled;
    }
  }

  Future<void> _pauseForExpiredSession() async {
    _paused = true;
    _lastError = sessionExpiredMessage;
  }

  /// Reanuda la cola después de un nuevo inicio de sesión, sin perder pendientes.
  Future<void> resume() async {
    _paused = false;
    if (_lastError == sessionExpiredMessage) {
      _lastError = null;
    }
    notifyListeners();
    await flush();
  }

  Future<List<QueuedRead>> _prepareBatch(List<QueuedRead> batch) async {
    final existingKey = batch
        .map((item) => item.idempotencyKey)
        .firstWhere((key) => key != null && key.isNotEmpty, orElse: () => null);
    final key = existingKey ?? RfidReadsDto.idempotencyKeyFor(batch);
    for (final item in batch) {
      item.idempotencyKey = key;
      await _queue.update(item);
    }
    return batch;
  }

  Future<void> _handleFailure(List<QueuedRead> batch, HttpReadsException error) async {
    if (error.isReaderNotRegistered) {
      _lastError = readerNotRegisteredMessage;
      await _blockBatch(batch, readerNotRegisteredMessage, error.problem?.code);
      return;
    }
    if (error.isRateLimited) {
      _lastError = null;
      final retryAt = parseRetryAfter(error.retryAfterHeader, _clock());
      if (retryAt != null) {
        await _scheduleRetryAt(batch, retryAt);
      } else {
        await _scheduleRetry(batch, _clock());
      }
      return;
    }
    if (error.isRetryable) {
      _lastError = null;
      final retryAt = parseRetryAfter(error.retryAfterHeader, _clock());
      if (retryAt != null) {
        await _scheduleRetryAt(batch, retryAt);
      } else {
        await _scheduleRetry(batch, _clock());
      }
      return;
    }
    if (error.isClientError) {
      final message = _messageForClientError(error);
      _lastError = message;
      await _blockBatch(batch, message, error.problem?.code);
      return;
    }
    await _scheduleRetry(batch, _clock());
  }

  String _messageForClientError(HttpReadsException error) {
    final code = (error.problem?.code ?? '').toUpperCase();
    switch (code) {
      case 'READER_INACTIVE':
        return 'Este lector no está activo.';
      case 'READER_WAREHOUSE_MISMATCH':
        return 'Este lector está asignado a otra bodega.';
      case 'LOCATION_NOT_IN_WAREHOUSE':
        return 'La ubicación no pertenece a esta bodega.';
      case 'WAREHOUSE_NOT_FOUND':
      case 'WAREHOUSE_ACCESS_DENIED':
        return 'No se pudo enviar a esta bodega.';
      default:
        return 'No se pudieron enviar las lecturas.';
    }
  }

  Future<void> _blockBatch(List<QueuedRead> batch, String reason, String? code) async {
    for (final item in batch) {
      item.blocked = true;
      item.blockReason = reason;
      item.blockCode = code;
      await _queue.update(item);
    }
  }

  Future<void> _scheduleRetry(List<QueuedRead> batch, DateTime now) async {
    for (final item in batch) {
      item.attempts += 1;
      item.nextRetryAt = now.add(backoffFor(item.attempts));
      await _queue.update(item);
    }
  }

  Future<void> _scheduleRetryAt(List<QueuedRead> batch, DateTime retryAt) async {
    for (final item in batch) {
      item.attempts += 1;
      item.nextRetryAt = retryAt;
      await _queue.update(item);
    }
  }
}
