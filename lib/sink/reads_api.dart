// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'api_problem.dart';
import 'queued_read.dart';
import 'rfid_reads_dto.dart';

abstract class ReadsApi {
  Future<void> postBatch(
    List<QueuedRead> batch,
    String accessToken, {
    required String warehouseId,
    required String readerId,
    String? locationId,
    String? idempotencyKey,
    String? correlationId,
  });
}

class HttpReadsApi implements ReadsApi {
  HttpReadsApi({
    required AppConfig config,
    http.Client? client,
  })  : _config = config,
        _client = client ?? http.Client();

  final AppConfig _config;
  final http.Client _client;

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
    if (_config.trimmedApiBase.isEmpty) {
      throw StateError('Configura la URL base de la API en Ajustes.');
    }
    final uri = Uri.parse('${_config.trimmedApiBase}${RfidReadsDto.postPath}');
    final correlation = (correlationId != null && correlationId.isNotEmpty)
        ? correlationId
        : const Uuid().v4();
    final idempotency = (idempotencyKey != null && idempotencyKey.isNotEmpty)
        ? idempotencyKey
        : RfidReadsDto.idempotencyKeyFor(batch);
    final platform = !kIsWeb && Platform.isIOS
        ? 'ios'
        : !kIsWeb && Platform.isAndroid
            ? 'android'
            : null;
    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/problem+json, application/json',
          'X-Correlation-ID': correlation,
          'Idempotency-Key': idempotency,
        },
        body: jsonEncode(
          RfidReadsDto.batchToJson(
            warehouseId: warehouseId,
            readerId: readerId,
            locationId: locationId,
            reads: batch,
            platform: platform,
          ),
        ),
      );
    } on SocketException catch (error) {
      throw HttpReadsException.network(error);
    } on http.ClientException catch (error) {
      throw HttpReadsException.network(error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpReadsException.fromResponse(response);
    }
  }
}

class HttpReadsException implements Exception {
  const HttpReadsException(
    this.statusCode, {
    this.problem,
    this.retryAfterHeader,
    this.network = false,
  });

  factory HttpReadsException.network(Object error) {
    return HttpReadsException(0, network: true, problem: ApiProblem(status: 0, detail: '$error'));
  }

  factory HttpReadsException.fromResponse(http.Response response) {
    return HttpReadsException(
      response.statusCode,
      problem: ApiProblem.tryParse(response.body, response.statusCode),
      retryAfterHeader: response.headers['retry-after'] ?? response.headers['Retry-After'],
    );
  }

  final int statusCode;
  final ApiProblem? problem;
  final String? retryAfterHeader;
  final bool network;

  bool get isRetryable => network || statusCode == 0 || statusCode >= 500;
  bool get isRateLimited => statusCode == 429;
  bool get isClientError => statusCode >= 400 && statusCode < 500 && statusCode != 429;
  bool get isReaderNotRegistered =>
      statusCode == 422 && (problem?.isReaderNotRegistered ?? false);

  @override
  String toString() => problem?.detail ?? 'El envío de lecturas respondió $statusCode';
}
