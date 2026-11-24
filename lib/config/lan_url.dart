import 'app_flavor.dart';

/// Validación de URLs según el flavor: https siempre; http solo en demo y en la LAN.
class UrlValidation {
  const UrlValidation._(this.ok, this.message);

  const UrlValidation.ok() : this._(true, null);

  const UrlValidation.error(String message) : this._(false, message);

  final bool ok;
  final String? message;
}

UrlValidation validateServerUrl(
  String raw, {
  String label = 'esta dirección',
  String? flavor,
}) {
  final allowsLanHttp = AppFlavor.allowsLanHttp(flavor);
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return UrlValidation.error('Indica la $label.');
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return UrlValidation.error(
      allowsLanHttp
          ? 'La $label no es válida. Debe empezar por https:// o, en la red local, por http://.'
          : 'La $label no es válida. Debe empezar por https://.',
    );
  }
  if (uri.scheme == 'https') {
    return const UrlValidation.ok();
  }
  if (uri.scheme == 'http') {
    if (!allowsLanHttp) {
      return UrlValidation.error(
        'La $label debe usar https. Esta versión no permite http, ni siquiera en la red local.',
      );
    }
    if (isLanHost(uri.host)) {
      return const UrlValidation.ok();
    }
    return UrlValidation.error(
      'La $label solo puede usar http en la red local (por ejemplo 192.168.x.x). En internet usa https.',
    );
  }
  return UrlValidation.error(
    allowsLanHttp
        ? 'La $label debe usar https:// o, en la red local, http://.'
        : 'La $label debe usar https://.',
  );
}

/// true si [raw] es http hacia un host de LAN y el flavor lo permite (solo demo).
bool isInsecureLanUrl(String raw, {String? flavor}) {
  if (!AppFlavor.allowsLanHttp(flavor)) return false;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) {
    return false;
  }
  return isLanHost(uri.host);
}

/// Hosts de LAN: 10/8, 172.16/12, 192.168/16, 127/8, localhost y *.local.
bool isLanHost(String host) {
  var name = host.trim().toLowerCase();
  if (name.startsWith('[') && name.endsWith(']')) {
    name = name.substring(1, name.length - 1);
  }
  if (name == 'localhost' || name == '::1' || name == '0:0:0:0:0:0:0:1') {
    return true;
  }
  if (name.endsWith('.local')) {
    return true;
  }
  final parts = name.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    octets.add(value);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10) return true;
  if (a == 127) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

String trimTrailingSlash(String value) {
  var result = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
