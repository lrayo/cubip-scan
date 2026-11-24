// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

/// Sesión OIDC. Las implementaciones reales nunca deben registrar tokens.
abstract class AuthSession extends ChangeNotifier {
  bool get isLoggedIn;
  bool get isDemoSession;
  Future<void> restore();
  Future<void> login();
  Future<void> loginDemo();
  Future<void> logout();
  Future<String?> accessToken();

  /// Fuerza un refresh del access token. Devuelve el nuevo token o null.
  Future<String?> refreshAccessToken();

  /// `sub` del token (o equivalente) para la caché por usuario.
  String? get userId;
}

/// Sesión en memoria para tests y para el modo demo (sin Keycloak).
class MemoryAuthSession extends AuthSession {
  MemoryAuthSession({
    bool loggedIn = false,
    bool demo = false,
    String? token,
    String? userId,
    this.onRefresh,
  })  : _loggedIn = loggedIn,
        _demo = demo,
        _token = token ?? 'demo-token',
        _userId = userId ?? (demo ? 'demo-user' : (loggedIn ? 'test-user' : null));

  bool _loggedIn;
  bool _demo;
  String? _token;
  String? _userId;
  Future<String?> Function()? onRefresh;

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  bool get isDemoSession => _demo;

  @override
  String? get userId => _loggedIn ? _userId : null;

  @override
  Future<void> restore() async {}

  @override
  Future<void> login() async {
    _loggedIn = true;
    _demo = false;
    _token = 'test-access-token';
    _userId ??= 'test-user';
    notifyListeners();
  }

  @override
  Future<void> loginDemo() async {
    _loggedIn = true;
    _demo = true;
    _token = 'demo-token';
    _userId = _userId ?? 'demo-user';
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    _loggedIn = false;
    _demo = false;
    _token = null;
    _userId = null;
    notifyListeners();
  }

  @override
  Future<String?> accessToken() async => _loggedIn ? _token : null;

  @override
  Future<String?> refreshAccessToken() async {
    if (onRefresh != null) {
      final token = await onRefresh!();
      if (token != null && token.isNotEmpty) {
        _token = token;
        _loggedIn = true;
      }
      return token;
    }
    return _loggedIn ? _token : null;
  }

  void setToken(String? token) {
    _token = token;
    _loggedIn = token != null && token.isNotEmpty;
  }

  void setUserId(String? userId) {
    _userId = userId;
  }
}
