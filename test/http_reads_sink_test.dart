import 'dart:io';

import 'package:cubip_scan/location/location.dart';
import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/sink/api_problem.dart';
import 'package:cubip_scan/sink/http_reads_sink.dart';
import 'package:cubip_scan/sink/offline_queue.dart';
import 'package:cubip_scan/sink/queued_read.dart';
import 'package:cubip_scan/sink/reads_api.dart';
import 'package:cubip_scan/sink/rfid_reads_dto.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';

const warehouseId = FakeWarehouseRepository.bogotaId;
const readerId = 'NA72512130766';

class FakeReadsApi implements ReadsApi {
  final List<List<String>> batches = [];
  final List<Map<String, dynamic>> bodies = [];
  final List<String?> idempotencyKeys = [];
  final List<String> tokens = [];
  int attempts = 0;
  int failuresRemaining = 0;
  bool offline = false;
  HttpReadsException? nextError;

  @override
  Future<void> postBatch(
    List<QueuedRead> batch,
    String accessToken, {
    required String warehouseId,
    required String readerId,
    String? locationId,
    String? idempotencyKey,
    String? correlationId,
  }) async {
    attempts += 1;
    idempotencyKeys.add(idempotencyKey);
    tokens.add(accessToken);
    if (offline) {
      throw const HttpReadsException(0, network: true);
    }
    if (nextError != null) {
      final error = nextError!;
      nextError = null;
      throw error;
    }
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const HttpReadsException(500);
    }
    batches.add([for (final item in batch) item.clientReadId]);
    bodies.add(
      RfidReadsDto.batchToJson(
        warehouseId: warehouseId,
        readerId: readerId,
        locationId: locationId,
        reads: batch,
      ),
    );
  }
}

String uuidOf(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

TagRead tag(String epc, {String? id, DateTime? at, int rssi = -40}) {
  return TagRead(
    epc: epc,
    rssi: rssi,
    antenna: 1,
    timestamp: at ?? DateTime.utc(2026, 11, 19, 22),
    clientReadId: id,
  );
}

void main() {
  late FakeReadsApi api;
  late MemoryOfflineQueue queue;
  late DateTime now;
  late HttpReadsSink sink;
  var nextId = 0;
  String? locationId;

  setUp(() {
    api = FakeReadsApi();
    queue = MemoryOfflineQueue();
    now = DateTime.utc(2026, 11, 19, 22);
    nextId = 0;
    locationId = null;
    sink = HttpReadsSink(
      api: api,
      queue: queue,
      tokenProvider: () async => 'token',
      warehouseIdProvider: () => warehouseId,
      readerIdProvider: () => readerId,
      locationIdProvider: () => locationId,
      clock: () => now,
      idGenerator: () {
        nextId += 1;
        return uuidOf(nextId);
      },
    );
  });

  Future<void> enqueue(String id) {
    return queue.enqueue(QueuedRead.fromTag(
      read: tag('E28011700000020F1A2B3C4D', id: id),
      warehouseId: warehouseId,
      clientReadId: id,
    ));
  }

  test('parte un lote de más de 500 lecturas', () async {
    for (var i = 0; i < 501; i++) {
      await enqueue(uuidOf(i));
    }
    await sink.flush();
    expect(api.batches, hasLength(2));
    expect(api.batches[0], hasLength(RfidReadsDto.maxBatchSize));
    expect(api.batches[1], hasLength(1));
    expect(api.batches[0].first, uuidOf(0));
    expect(api.batches[1].single, uuidOf(500));
    expect(sink.sentCount, 501);
    expect(sink.pendingCount, 0);
  });

  test('reintenta con los mismos client_read_id y la misma Idempotency-Key', () async {
    api.failuresRemaining = 1;
    await enqueue(uuidOf(1));
    await enqueue(uuidOf(2));
    await sink.flush();
    expect(api.batches, isEmpty);
    expect(api.attempts, 1);
    final pendingAfterFail = await queue.pending();
    expect(pendingAfterFail.map((e) => e.clientReadId), [uuidOf(1), uuidOf(2)]);
    final sealedKey = pendingAfterFail.first.idempotencyKey;
    expect(sealedKey, isNotNull);
    expect(api.idempotencyKeys, [sealedKey]);
    expect(pendingAfterFail.first.nextRetryAt, now.add(HttpReadsSink.backoffFor(1)));

    now = now.add(HttpReadsSink.backoffFor(1));
    await sink.flush();
    expect(api.batches, hasLength(1));
    expect(api.batches.single, [uuidOf(1), uuidOf(2)]);
    expect(api.idempotencyKeys, [sealedKey, sealedKey]);
    expect(api.attempts, 2);
    expect(sink.sentCount, 2);
    expect(sink.pendingCount, 0);
  });

  test('la cola offline conserva lecturas sin señal y respeta el backoff', () async {
    api.offline = true;
    await sink.publish(tag('E28011700000020F1A2B3C4D', id: uuidOf(1)));
    expect(sink.pendingCount, 1);
    expect(sink.sentCount, 0);
    final firstRetry = (await queue.pending()).single.nextRetryAt!;

    await sink.flush();
    expect(sink.pendingCount, 1);
    expect((await queue.pending()).single.nextRetryAt, firstRetry);

    api.offline = false;
    await sink.flush();
    expect(sink.pendingCount, 1, reason: 'todavía no vence el backoff');
    expect(api.batches, isEmpty);

    now = firstRetry;
    await sink.flush();
    expect(api.batches.single, [uuidOf(1)]);
    expect(sink.pendingCount, 0);
    expect(sink.sentCount, 1);
  });

  test('el backoff crece de forma exponencial y se tope en 5 minutos', () {
    expect(HttpReadsSink.backoffFor(1), const Duration(seconds: 1));
    expect(HttpReadsSink.backoffFor(2), const Duration(seconds: 2));
    expect(HttpReadsSink.backoffFor(3), const Duration(seconds: 4));
    expect(HttpReadsSink.backoffFor(4), const Duration(seconds: 8));
    expect(HttpReadsSink.backoffFor(9), const Duration(seconds: 256));
    expect(HttpReadsSink.backoffFor(10), const Duration(seconds: 300));
    expect(HttpReadsSink.backoffFor(20), const Duration(seconds: 300));
  });

  test('el lote sigue el contrato OpenAPI de rfid-reads', () {
    final read = QueuedRead(
      clientReadId: uuidOf(9),
      epc: 'E28011700000020F1A2B3C4D',
      tid: 'E2801100ABCD1234',
      rssi: -41,
      antenna: 1,
      readAt: now,
      warehouseId: warehouseId,
    );
    final json = RfidReadsDto.batchToJson(
      warehouseId: warehouseId,
      readerId: 'NA72512130766',
      locationId: FakeLocationRepository.binA12Id,
      reads: [read],
      platform: 'android',
    );
    expect(json['warehouse_id'], warehouseId);
    expect(json['reader_id'], 'NA72512130766');
    expect(json['location_id'], FakeLocationRepository.binA12Id);
    expect(json['app'], {
      'name': 'cubip-scan',
      'version': '1.0.0+1',
      'platform': 'android',
    });
    final item = (json['reads'] as List).single as Map<String, dynamic>;
    expect(item['client_read_id'], uuidOf(9));
    expect(item['rssi_dbm'], -41);
    expect(item.containsKey('rssi'), isFalse);
    expect(RfidReadsDto.postPath, '/api/v1/rfid/read-batches');
  });

  test('incluye location_id cuando hay ubicación y lo omite si no hay', () async {
    locationId = FakeLocationRepository.binA12Id;
    await sink.publish(tag('E28011700000020F1A2B3C4D', id: uuidOf(1)));
    expect(api.bodies.single['location_id'], FakeLocationRepository.binA12Id);

    locationId = null;
    await sink.publish(tag('E28011700000020F1A2B3C4D', id: uuidOf(2)));
    expect(api.bodies.last.containsKey('location_id'), isFalse);
  });

  test('un 422 de lector no registrado no se reintenta y el lote queda marcado', () async {
    api.nextError = HttpReadsException(
      422,
      problem: const ApiProblem(
        status: 422,
        type: 'https://errors.wms-enterprise.com/rfid/reader-not-registered',
        title: 'Unprocessable Content',
        code: 'READER_NOT_REGISTERED',
        detail: 'Reader NA72512130766 is not registered in this tenant',
      ),
    );
    await enqueue(uuidOf(1));
    await enqueue(uuidOf(2));
    await sink.flush();
    expect(api.attempts, 1);
    expect(sink.lastError, readerNotRegisteredMessage);
    expect(sink.pendingCount, 2);
    expect(sink.sentCount, 0);
    final pending = await queue.pending();
    expect(pending.every((item) => item.blocked), isTrue);
    expect(pending.every((item) => item.blockReason == readerNotRegisteredMessage), isTrue);
    expect(pending.first.idempotencyKey, isNotNull);

    now = now.add(const Duration(minutes: 10));
    await sink.flush();
    expect(api.attempts, 1, reason: 'no debe reintentar el 422');
    expect(api.batches, isEmpty);
    expect(sink.pendingCount, 2);
    expect(pending.first.blocked, isTrue);
  });

  test('un 429 respeta Retry-After en segundos antes del backoff', () async {
    api.nextError = const HttpReadsException(429, retryAfterHeader: '45');
    await enqueue(uuidOf(1));
    await sink.flush();
    final retryAt = (await queue.pending()).single.nextRetryAt!;
    expect(retryAt, now.add(const Duration(seconds: 45)));
    expect(retryAt, isNot(now.add(HttpReadsSink.backoffFor(1))));
    expect(sink.pendingCount, 1);

    await sink.flush();
    expect(api.batches, isEmpty);

    now = retryAt;
    await sink.flush();
    expect(api.batches, hasLength(1));
    expect(sink.pendingCount, 0);
  });

  test('un 429 respeta Retry-After como fecha HTTP', () async {
    final when = DateTime.utc(2026, 11, 19, 22, 8);
    api.nextError = HttpReadsException(429, retryAfterHeader: HttpDate.format(when));
    await enqueue(uuidOf(1));
    await sink.flush();
    expect((await queue.pending()).single.nextRetryAt, when);

    now = when;
    await sink.flush();
    expect(api.batches, hasLength(1));
  });

  test('un 400 no se reintenta y un 503 sí', () async {
    api.nextError = HttpReadsException(
      400,
      problem: const ApiProblem(status: 400, code: 'INVALID_BATCH', title: 'Bad Request'),
    );
    await enqueue(uuidOf(1));
    await sink.flush();
    expect((await queue.pending()).single.blocked, isTrue);
    now = now.add(const Duration(minutes: 10));
    await sink.flush();
    expect(api.batches, isEmpty);

    final queue2 = MemoryOfflineQueue();
    final api2 = FakeReadsApi()
      ..nextError = const HttpReadsException(503, retryAfterHeader: '12');
    final sink2 = HttpReadsSink(
      api: api2,
      queue: queue2,
      tokenProvider: () async => 'token',
      warehouseIdProvider: () => warehouseId,
      readerIdProvider: () => readerId,
      clock: () => now,
    );
    await queue2.enqueue(QueuedRead.fromTag(
      read: tag('E28011700000020F1A2B3C4D', id: uuidOf(3)),
      warehouseId: warehouseId,
      clientReadId: uuidOf(3),
    ));
    await sink2.flush();
    expect((await queue2.pending()).single.blocked, isFalse);
    expect((await queue2.pending()).single.nextRetryAt, now.add(const Duration(seconds: 12)));
  });

  test('un 401 refresca el token y reintenta el lote una vez con la misma Idempotency-Key', () async {
    var token = 'expired-token';
    sink = HttpReadsSink(
      api: api,
      queue: queue,
      tokenProvider: () async => token,
      tokenRefresher: () async {
        token = 'fresh-token';
        return token;
      },
      warehouseIdProvider: () => warehouseId,
      readerIdProvider: () => readerId,
      locationIdProvider: () => locationId,
      clock: () => now,
      idGenerator: () {
        nextId += 1;
        return uuidOf(nextId);
      },
    );
    api.nextError = const HttpReadsException(401);
    await enqueue(uuidOf(1));
    await enqueue(uuidOf(2));
    await sink.flush();
    expect(api.attempts, 2);
    expect(api.tokens, ['expired-token', 'fresh-token']);
    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[0], api.idempotencyKeys[1]);
    expect(api.idempotencyKeys[0], isNotNull);
    expect(api.batches, hasLength(1));
    expect(api.batches.single, [uuidOf(1), uuidOf(2)]);
    expect(sink.pendingCount, 0);
    expect(sink.sentCount, 2);
    expect(sink.isPaused, isFalse);
    expect((await queue.pending()).every((item) => !item.blocked), isTrue);
  });

  test('si el refresh falla ante un 401, la cola se pausa y se reanuda después del login', () async {
    var token = 'expired-token';
    sink = HttpReadsSink(
      api: api,
      queue: queue,
      tokenProvider: () async => token,
      tokenRefresher: () async => null,
      warehouseIdProvider: () => warehouseId,
      readerIdProvider: () => readerId,
      locationIdProvider: () => locationId,
      clock: () => now,
      idGenerator: () {
        nextId += 1;
        return uuidOf(nextId);
      },
    );
    api.nextError = const HttpReadsException(401);
    await enqueue(uuidOf(1));
    await enqueue(uuidOf(2));
    await sink.flush();
    expect(api.attempts, 1);
    expect(sink.isPaused, isTrue);
    expect(sink.lastError, sessionExpiredMessage);
    expect(sink.pendingCount, 2);
    expect(sink.sentCount, 0);
    final pending = await queue.pending();
    expect(pending.every((item) => !item.blocked), isTrue);
    final sealedKey = pending.first.idempotencyKey;

    await sink.flush();
    expect(api.attempts, 1, reason: 'la cola pausada no debe reintentar');
    expect(sink.pendingCount, 2);

    token = 'new-login-token';
    await sink.resume();
    expect(sink.isPaused, isFalse);
    expect(sink.lastError, isNull);
    expect(api.attempts, 2);
    expect(api.tokens.last, 'new-login-token');
    expect(api.idempotencyKeys.last, sealedKey);
    expect(sink.pendingCount, 0);
    expect(sink.sentCount, 2);
  });
}

