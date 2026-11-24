import 'dart:convert';

/// Extrae el `sub` del access token JWT, o un equivalente si no está.
/// No registra ni devuelve el token.
String? subjectFromAccessToken(String? token) {
  if (token == null || token.isEmpty) return null;
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    var payload = parts[1];
    final pad = payload.length % 4;
    if (pad > 0) {
      payload += '=' * (4 - pad);
    }
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded);
    if (json is! Map) return null;
    for (final key in const ['sub', 'oid', 'preferred_username']) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Nombre de archivo seguro para la caché por usuario.
String cacheKeyForUser(String userId) {
  final safe = userId.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty) return '_unknown';
  return safe.length > 120 ? safe.substring(0, 120) : safe;
}
