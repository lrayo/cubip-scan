import 'dart:convert';

import 'package:cubip_scan/config/app_config.dart';
import 'package:cubip_scan/config/app_flavor.dart';
import 'package:cubip_scan/config/connection_probe.dart';
import 'package:cubip_scan/config/lan_url.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('validador de URLs de LAN', () {
    test('acepta https en cualquier host', () {
      expect(validateServerUrl('https://api.cubip.example', label: 'URL de la API').ok, isTrue);
      expect(validateServerUrl('https://192.168.1.10:8081').ok, isTrue);
      expect(validateServerUrl('https://example.com/v1').ok, isTrue);
    });

    test('acepta http solo en hosts de LAN', () {
      const valid = [
        'http://192.168.1.20:8080',
        'http://192.168.0.1',
        'http://10.0.0.5',
        'http://10.255.255.254:443',
        'http://172.16.0.1',
        'http://172.31.255.1:8080',
        'http://127.0.0.1:8080',
        'http://127.1.2.3',
        'http://localhost:8080',
        'http://LOCALHOST',
        'http://keycloak.local',
        'http://api.midominio.local:8081',
      ];
      for (final url in valid) {
        final result = validateServerUrl(url, label: 'URL de Keycloak');
        expect(result.ok, isTrue, reason: url);
        expect(isInsecureLanUrl(url), isTrue, reason: url);
      }
    });

    test('rechaza http fuera de la LAN', () {
      const invalid = [
        'http://api.example.com',
        'http://8.8.8.8',
        'http://172.15.0.1',
        'http://172.32.0.1',
        'http://11.0.0.1',
        'http://192.167.1.1',
        'http://193.168.1.1',
        'http://keycloak.local.evil.com',
      ];
      for (final url in invalid) {
        final result = validateServerUrl(url, label: 'URL de la API');
        expect(result.ok, isFalse, reason: url);
        expect(result.message, contains('red local'), reason: url);
        expect(isInsecureLanUrl(url), isFalse, reason: url);
      }
    });

    test('rechaza esquemas o textos inválidos', () {
      expect(validateServerUrl('', label: 'URL de la API').message, contains('Indica'));
      expect(validateServerUrl('ftp://192.168.1.1').ok, isFalse);
      expect(validateServerUrl('not a url').ok, isFalse);
      expect(isInsecureLanUrl('https://192.168.1.1'), isFalse);
    });
  });

  group('validador según el flavor', () {
    const lanHttp = 'http://192.168.1.20:8080';
    const publicHttp = 'http://api.example.com';
    const httpsUrl = 'https://api.example.com';

    test('demo acepta https y http de LAN, y rechaza http público', () {
      expect(validateServerUrl(httpsUrl, flavor: AppFlavor.demo).ok, isTrue);
      expect(validateServerUrl(lanHttp, flavor: AppFlavor.demo).ok, isTrue);
      expect(validateServerUrl(publicHttp, flavor: AppFlavor.demo).ok, isFalse);
      expect(isInsecureLanUrl(lanHttp, flavor: AppFlavor.demo), isTrue);
    });

    test('cliente rechaza todo http, incluso en la LAN, y acepta https', () {
      expect(validateServerUrl(httpsUrl, flavor: AppFlavor.cliente).ok, isTrue);
      final lan = validateServerUrl(lanHttp, label: 'URL de la API', flavor: AppFlavor.cliente);
      expect(lan.ok, isFalse);
      expect(lan.message, contains('ni siquiera en la red local'));
      expect(validateServerUrl(publicHttp, flavor: AppFlavor.cliente).ok, isFalse);
      expect(isInsecureLanUrl(lanHttp, flavor: AppFlavor.cliente), isFalse);
    });
  });

  group('armado del issuer', () {
    test('arma {keycloak}/realms/{realm} y permite sobrescribirlo', () {
      final config = AppConfig(
        keycloakUrl: 'http://192.168.0.10:8080/',
        realm: 'wms-realm',
      );
      expect(config.builtIssuer, 'http://192.168.0.10:8080/realms/wms-realm');
      expect(config.trimmedIssuer, config.builtIssuer);
      expect(config.hasIssuerOverride, isFalse);
      expect(
        config.authorizationDiscovery.toString(),
        'http://192.168.0.10:8080/realms/wms-realm/.well-known/openid-configuration',
      );

      config.setIssuer('http://192.168.0.10:8080/realms/otro');
      expect(config.hasIssuerOverride, isTrue);
      expect(config.trimmedIssuer, 'http://192.168.0.10:8080/realms/otro');

      config.setIssuer('http://192.168.0.10:8080/realms/wms-realm');
      expect(config.hasIssuerOverride, isFalse);
      expect(config.trimmedIssuer, config.builtIssuer);

      config.setKeycloakUrl('http://10.0.0.8:8080');
      expect(config.builtIssuer, 'http://10.0.0.8:8080/realms/wms-realm');
      expect(config.allowInsecureConnections, isTrue);
    });
  });

  group('descubrimiento con servidor falso', () {
    const issuer = 'http://192.168.1.10:8080/realms/wms-realm';
    const api = 'http://192.168.1.10:8081';

    AppConfig config() => AppConfig(
          keycloakUrl: 'http://192.168.1.10:8080',
          realm: 'wms-realm',
          apiBaseUrl: api,
        );

    test('éxito cuando el issuer coincide y healthz responde 200', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(
            jsonEncode({'issuer': issuer, 'authorization_endpoint': '$issuer/protocol/openid-connect/auth'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == ConnectionProbe.healthzPath) {
          return http.Response(
            jsonEncode({'status': 'UP'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('missing', 404);
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isTrue);
      expect(result.message, contains('Conexión lista'));
    });

    test('falla si healthz no responde 200', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(jsonEncode({'issuer': issuer}), 200);
        }
        if (request.url.path == ConnectionProbe.healthzPath) {
          return http.Response('unauthorized', 401);
        }
        return http.Response('ok', 200);
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isFalse);
      expect(result.message, contains('401'));
      expect(result.message, contains(ConnectionProbe.healthzPath));
    });

    test('falla si healthz responde 200 sin status UP', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(jsonEncode({'issuer': issuer}), 200);
        }
        if (request.url.path == ConnectionProbe.healthzPath) {
          return http.Response(
            jsonEncode({'status': 'DOWN'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('ok', 200);
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isFalse);
      expect(result.message, contains('DOWN'));
      expect(result.message, contains('UP'));
    });

    test('falla si healthz responde 200 con cuerpo inválido', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(jsonEncode({'issuer': issuer}), 200);
        }
        if (request.url.path == ConnectionProbe.healthzPath) {
          return http.Response('ok', 200);
        }
        return http.Response('ok', 200);
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isFalse);
      expect(result.message, contains('UP'));
    });

    test('falla si el issuer descubierto no coincide', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(
            jsonEncode({'issuer': 'http://192.168.1.10:8080/realms/otro'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('ok', 200);
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isFalse);
      expect(result.message, contains('no coincide'));
      expect(result.message, contains('otro'));
    });

    test('falla si la API no responde', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/.well-known/openid-configuration')) {
          return http.Response(jsonEncode({'issuer': issuer}), 200);
        }
        throw http.ClientException('connection refused');
      });
      final result = await ConnectionProbe(client: client).check(config());
      expect(result.ok, isFalse);
      expect(result.message, contains('No se pudo alcanzar la API'));
    });

    test('no llama a la red si la URL http no es de LAN', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('ok', 200);
      });
      final result = await ConnectionProbe(client: client).check(
        AppConfig(
          keycloakUrl: 'http://idp.example.com',
          realm: 'wms-realm',
          apiBaseUrl: 'https://api.example.com',
        ),
      );
      expect(called, isFalse);
      expect(result.ok, isFalse);
      expect(result.message, contains('red local'));
    });
  });
}
