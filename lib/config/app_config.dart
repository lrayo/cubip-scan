import 'package:flutter/foundation.dart';

import 'lan_url.dart';

/// Configuración editable del servidor de ingreso y de la API.
class AppConfig extends ChangeNotifier {
  AppConfig({
    this.issuer = '',
    this.apiBaseUrl = '',
    this.keycloakUrl = '',
    this.realm = defaultRealm,
  });

  static const String clientId = 'wms-mobile';
  static const String redirectUrl = 'com.megadeep.cubipscan:/oauth';
  static const List<String> scopes = ['openid', 'profile'];
  static const String defaultRealm = 'wms-realm';

  /// Issuer completo si se sobrescribe; vacío = se arma con Keycloak + realm.
  String issuer;
  String apiBaseUrl;
  String keycloakUrl;
  String realm;

  /// `{keycloak}/realms/{realm}`, o vacío si falta alguno.
  String get builtIssuer {
    final base = trimTrailingSlash(keycloakUrl);
    final realmName = realm.trim();
    if (base.isEmpty || realmName.isEmpty) return '';
    return '$base/realms/$realmName';
  }

  String get trimmedIssuer {
    final override = trimTrailingSlash(issuer);
    return override.isNotEmpty ? override : builtIssuer;
  }

  String get trimmedApiBase => trimTrailingSlash(apiBaseUrl);

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
