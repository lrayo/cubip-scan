import 'dart:convert';

import 'location.dart';

/// Extrae el código (o identificador) de ubicación desde un payload QR escaneado.
///
/// Soporta:
/// - Código directo (`A-03-02`, `A01-01-01`).
/// - Payload jerárquico emitido por Cubip Web (`WH01:Z1:A01:R01:L01:A-03-02`).
/// - URI `cubip://loc/A-03-02` (decodificando URI).
/// - JSON `{"location_code":"A-03-02"}` o `{"code":"A-03-02"}`.
String? extractLocationCodeFromQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        for (final key in const ['location_code', 'locationCode', 'code']) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  if (trimmed.contains('://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != 'cubip') {
      return null;
    }
    if (uri.host.toLowerCase() != 'loc') {
      return null;
    }
    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
    for (final key in const ['location_code', 'locationCode', 'code']) {
      final queryValue = uri.queryParameters[key]?.trim();
      if (queryValue != null && queryValue.isNotEmpty) {
        return queryValue;
      }
    }
    return null;
  }

  if (trimmed.contains(':')) {
    final segments = trimmed
        .split(':')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }

  return trimmed;
}

/// Busca una ubicación en [locations] con coincidencia exacta (sin distinguir
/// mayúsculas) por `code`, `id` o `labelEpc`.
Location? findLocationByQr(String raw, List<Location> locations) {
  if (locations.isEmpty) return null;
  final extracted = extractLocationCodeFromQr(raw);
  if (extracted == null || extracted.isEmpty) return null;
  final needle = extracted.trim().toLowerCase();
  if (needle.isEmpty) return null;

  for (final location in locations) {
    if (location.code.trim().toLowerCase() == needle) {
      return location;
    }
  }
  for (final location in locations) {
    if (location.id.trim().toLowerCase() == needle) {
      return location;
    }
  }
  for (final location in locations) {
    final epc = location.labelEpc?.trim().toLowerCase();
    if (epc != null && epc.isNotEmpty && epc == needle) {
      return location;
    }
  }
  return null;
}
