import 'dart:convert';
import 'dart:io';

/// Error RFC 9457 (`application/problem+json`) del contrato de ingesta RFID.
class ApiProblem {
  const ApiProblem({
    required this.status,
    this.type,
    this.title,
    this.detail,
    this.instance,
    this.code,
    this.correlationId,
    this.errors = const [],
  });

  final int status;
  final String? type;
  final String? title;
  final String? detail;
  final String? instance;
  final String? code;
  final String? correlationId;
  final List<ApiProblemError> errors;

  bool get isReaderNotRegistered {
    final normalized = (code ?? '').toUpperCase();
    if (normalized == 'READER_NOT_REGISTERED') return true;
    final typ = (type ?? '').toLowerCase();
    return typ.contains('reader-not-registered');
  }

  static ApiProblem? tryParse(String body, int statusCode) {
    if (body.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(body);
      if (raw is! Map) return null;
      final map = raw.cast<Object?, Object?>();
      final errorsRaw = map['errors'];
      return ApiProblem(
        status: (map['status'] as num?)?.toInt() ?? statusCode,
        type: map['type'] as String?,
        title: map['title'] as String?,
        detail: map['detail'] as String?,
        instance: map['instance'] as String?,
        code: map['code'] as String?,
        correlationId: map['correlation_id'] as String?,
        errors: [
          if (errorsRaw is List)
            for (final item in errorsRaw)
              if (item is Map)
                ApiProblemError(
                  pointer: '${item['pointer'] ?? ''}',
                  message: '${item['message'] ?? ''}',
                ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

class ApiProblemError {
  const ApiProblemError({required this.pointer, required this.message});

  final String pointer;
  final String message;
}

/// Interpreta `Retry-After` como segundos o como fecha HTTP (RFC 9110).
DateTime? parseRetryAfter(String? header, DateTime now) {
  if (header == null) return null;
  final trimmed = header.trim();
  if (trimmed.isEmpty) return null;
  final seconds = int.tryParse(trimmed);
  if (seconds != null) {
    final safe = seconds < 0 ? 0 : seconds;
    return now.add(Duration(seconds: safe));
  }
  try {
    final date = HttpDate.parse(trimmed).toUtc();
    return date.isBefore(now) ? now : date;
  } catch (_) {
    return null;
  }
}

const readerNotRegisteredMessage =
    'Este lector no está registrado en la bodega';

const sessionExpiredMessage =
    'Tu sesión expiró, vuelve a iniciar sesión';
