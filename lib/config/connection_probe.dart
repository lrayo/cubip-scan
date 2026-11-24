import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'lan_url.dart';

class ConnectionCheckResult {
  const ConnectionCheckResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Descubre el issuer (/.well-known/openid-configuration) y comprueba la API.
class ConnectionProbe {
  ConnectionProbe({http.Client? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client();

  /// Única constante de la ruta de salud de la API.
  static const String healthzPath = '/api/v1/health';

  final http.Client _client;
  final Duration timeout;

  static Uri healthzUri(String apiBase) =>
      Uri.parse('${trimTrailingSlash(apiBase)}$healthzPath');

  Future<ConnectionCheckResult> check(AppConfig config) async {
    final apiCheck = validateServerUrl(config.trimmedApiBase, label: 'URL de la API');
    if (!apiCheck.ok) {
      return ConnectionCheckResult(ok: false, message: apiCheck.message!);
    }
    final issuer = config.trimmedIssuer;
    final issuerCheck = validateServerUrl(issuer, label: 'URL de Keycloak / issuer');
    if (!issuerCheck.ok) {
      return ConnectionCheckResult(ok: false, message: issuerCheck.message!);
    }

    final discovery = await _getJson(config.authorizationDiscovery);
    if (discovery == null) {
      return const ConnectionCheckResult(
        ok: false,
        message: 'No se pudo consultar la configuración de ingreso. Revisa la URL de Keycloak, el realm y que el celular esté en la misma red.',
      );
    }
    final discovered = discovery['issuer'];
    if (discovered is! String || discovered.trim().isEmpty) {
      return const ConnectionCheckResult(
        ok: false,
        message: 'El servidor de ingreso no devolvió un issuer en su configuración.',
      );
    }
    if (trimTrailingSlash(discovered) != trimTrailingSlash(issuer)) {
      return ConnectionCheckResult(
        ok: false,
        message:
            'El issuer que devolvió el servidor no coincide con el configurado.\nEsperado: ${trimTrailingSlash(issuer)}\nRecibido: ${trimTrailingSlash(discovered)}',
      );
    }

    return _checkHealthz(config.trimmedApiBase);
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ConnectionCheckResult> _checkHealthz(String apiBase) async {
    final uri = healthzUri(apiBase);
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return ConnectionCheckResult(
          ok: false,
          message:
              'La API respondió ${response.statusCode} al comprobar $healthzPath. Se esperaba 200.',
        );
      }
      try {
        final decoded = jsonDecode(response.body);
        final status = decoded is Map ? decoded['status'] : null;
        if (status != 'UP') {
          return ConnectionCheckResult(
            ok: false,
            message: status == null
                ? 'La API respondió 200 pero no confirmó el estado UP.'
                : 'La API respondió 200 con estado $status. Se esperaba UP.',
          );
        }
      } catch (_) {
        return const ConnectionCheckResult(
          ok: false,
          message: 'La API respondió 200 pero no devolvió un estado UP válido.',
        );
      }
      return const ConnectionCheckResult(
        ok: true,
        message: 'Conexión lista. El servidor de ingreso coincide y la API está en estado UP.',
      );
    } catch (_) {
      return ConnectionCheckResult(
        ok: false,
        message: 'No se pudo alcanzar la API en $uri. Revisa la URL y el puerto.',
      );
    }
  }
}
