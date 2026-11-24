import 'package:flutter/foundation.dart';

import 'lan_url.dart';

/// Configuración editable del servidor de ingreso y de la API.
class AppConfig extends ChangeNotifier {
  AppConfig({
    this.issuer = '',
    String? apiBaseUrl,
    String? keycloakUrl,
    this.realm = defaultRealm,
  })  : apiBaseUrl = (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty)
            ? apiBaseUrl.trim()
            : defaultApiBaseUrl,
        keycloakUrl = (keycloakUrl != null && keycloakUrl.trim().isNotEmpty)
            ? keycloakUrl.trim()
            : defaultKeycloakUrl;

  static const String clientId = 'wms-mobile';
  static const String redirectUrl = 'com.megadeep.cubipscan:/oauth';
  static const List<String> scopes = ['openid', 'profile'];
  static const String defaultRealm = 'wms-realm';
  static const String defaultKeycloakUrl = 'https://auth.cubip.app';
  static const String defaultApiBaseUrl = 'https://api.cubip.app';

  /// Issuer completo si se sobrescribe; vacío = se arma con Keycloak + realm.
  String issuer;
  String apiBaseUrl;
  String keycloakUrl;
  String realm;

  /// `{keycloak}/realms/{realm}`, o vacío si falta alguno.
  String get builtIssuer {
    final effectiveKeycloak =
        keycloakUrl.trim().isNotEmpty ? keycloakUrl : defaultKeycloakUrl;
    final base = trimTrailingSlash(effectiveKeycloak);
    final realmName = realm.trim().isNotEmpty ? realm.trim() : defaultRealm;
    if (base.isEmpty || realmName.isEmpty) return '';
    return '$base/realms/$realmName';
  }

  String get trimmedIssuer {
    final override = trimTrailingSlash(issuer);
    return override.isNotEmpty ? override : builtIssuer;
  }

  String get trimmedApiBase {
    final effective =
        apiBaseUrl.trim().isNotEmpty ? apiBaseUrl : defaultApiBaseUrl;
    return trimTrailingSlash(effective);
  }

  bool get hasIssuerOverride => trimTrailingSlash(issuer).isNotEmpty;

  bool get allowInsecureConnections => isInsecureLanUrl(trimmedIssuer);

  Uri get authorizationDiscovery {
    final base = trimmedIssuer;
    if (base.isEmpty) {
      return Uri();
    }
    return Uri.parse('$base/.well-known/openid-configuration');
  }

  void setApiBaseUrl(String value) {
    apiBaseUrl = value.trim();
    notifyListeners();
  }

  void setKeycloakUrl(String value) {
    keycloakUrl = value.trim();
    notifyListeners();
  }

  void setRealm(String value) {
    realm = value.trim();
    notifyListeners();
  }

  /// Sobrescribe el issuer. Si coincide con el armado, se limpia la sobrescritura.
  void setIssuer(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimTrailingSlash(trimmed) == builtIssuer) {
      issuer = '';
    } else {
      issuer = trimmed;
    }
    notifyListeners();
  }
}
