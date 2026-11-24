// ignore_for_file: prefer_initializing_formals
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../config/lan_url.dart';
import 'auth_session.dart';
import 'token_subject.dart';

/// Login OIDC con PKCE contra Keycloak, tokens en almacenamiento seguro y refresh.
class AppAuthSession extends AuthSession {
  AppAuthSession({
    required AppConfig config,
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? storage,
  })  : _config = config,
        _appAuth = appAuth ?? const FlutterAppAuth(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _kAccess = 'cubip.oidc.access';
  static const _kRefresh = 'cubip.oidc.refresh';
  static const _kExpiry = 'cubip.oidc.expiry';

  final AppConfig _config;
  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  bool _loggedIn = false;
  bool _demo = false;
  DateTime? _expiry;
  String? _userId;

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  bool get isDemoSession => _demo;

  @override
  String? get userId => _loggedIn ? _userId : null;

  @override
  Future<void> restore() async {
    final access = await _storage.read(key: _kAccess);
    final expiryRaw = await _storage.read(key: _kExpiry);
    if (access == null || access.isEmpty) {
      _loggedIn = false;
      notifyListeners();
      return;
    }
    if (expiryRaw != null) {
      _expiry = DateTime.tryParse(expiryRaw);
    }
    _loggedIn = true;
    _demo = false;
    _userId = subjectFromAccessToken(access);
    notifyListeners();
  }

  @override
  Future<void> login() async {
    if (_config.trimmedIssuer.isEmpty) {
      throw StateError('Configura la URL de Keycloak y el realm en Ajustes.');
    }
    final issuerCheck = validateServerUrl(_config.trimmedIssuer, label: 'URL de Keycloak / issuer');
    if (!issuerCheck.ok) {
      throw StateError(issuerCheck.message!);
    }
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        AppConfig.clientId,
        AppConfig.redirectUrl,
        issuer: _config.trimmedIssuer,
        scopes: AppConfig.scopes,
        promptValues: const ['login'],
        allowInsecureConnections: _config.allowInsecureConnections,
      ),
    );
    await _persist(result.accessToken, result.refreshToken, result.accessTokenExpirationDateTime);
    _demo = false;
    _loggedIn = true;
    _userId = subjectFromAccessToken(result.accessToken);
    notifyListeners();
  }

  @override
  Future<void> loginDemo() async {
    await logout();
    _demo = true;
    _loggedIn = true;
    _userId = 'demo-user';
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
    _expiry = null;
    _loggedIn = false;
    _demo = false;
    _userId = null;
    notifyListeners();
  }

  @override
  Future<String?> accessToken() async {
    if (_demo) return 'demo-token';
    if (!_loggedIn) return null;
    var token = await _storage.read(key: _kAccess);
    if (token == null || token.isEmpty) {
      _loggedIn = false;
      notifyListeners();
      return null;
    }
    if (_needsRefresh) {
      token = await _refresh() ?? token;
    }
    return token;
  }

  bool get _needsRefresh {
    final expiry = _expiry;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 60)));
  }

  @override
  Future<String?> refreshAccessToken() => _refresh();

  Future<String?> _refresh() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null || refresh.isEmpty || _config.trimmedIssuer.isEmpty) {
      return null;
    }
    final result = await _appAuth.token(
      TokenRequest(
        AppConfig.clientId,
        AppConfig.redirectUrl,
        issuer: _config.trimmedIssuer,
        scopes: AppConfig.scopes,
        refreshToken: refresh,
        allowInsecureConnections: _config.allowInsecureConnections,
      ),
    );
    await _persist(result.accessToken, result.refreshToken ?? refresh, result.accessTokenExpirationDateTime);
    return result.accessToken;
  }

  Future<void> _persist(String? access, String? refresh, DateTime? expiry) async {
    if (access != null) {
      await _storage.write(key: _kAccess, value: access);
      _userId = subjectFromAccessToken(access) ?? _userId;
    }
    if (refresh != null) {
      await _storage.write(key: _kRefresh, value: refresh);
    }
    _expiry = expiry;
    if (expiry != null) {
      await _storage.write(key: _kExpiry, value: expiry.toIso8601String());
    }
  }
}
