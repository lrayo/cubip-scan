import 'package:flutter/services.dart';

/// Flavor de la build (`demo` o `cliente`).
///
/// Se lee de `--dart-define=APP_FLAVOR=...` o, si no viene, de [appFlavor]
/// (Flutter lo define con `--flavor`). No hace falta un `main` por flavor.
class AppFlavor {
  static const String demo = 'demo';
  static const String cliente = 'cliente';

  static const String _fromDefine = String.fromEnvironment('APP_FLAVOR');

  /// Flavor efectivo. En tests se puede pasar uno explícito al validador.
  static String current() {
    if (_fromDefine.isNotEmpty) return _fromDefine;
    final fromFlutter = appFlavor;
    if (fromFlutter != null && fromFlutter.isNotEmpty) return fromFlutter;
    return demo;
  }

  static bool allowsLanHttp([String? flavor]) {
    final name = (flavor ?? current()).toLowerCase();
    return name != cliente;
  }
}
