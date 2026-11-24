import 'package:flutter/services.dart';

/// Canal del plugin nativo (Kotlin + reader.jar / Swift + GReader.framework).
class CubipRfid {
  CubipRfid({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel('cubip_rfid'),
        _events = eventChannel ?? const EventChannel('cubip_rfid/events');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{'type': 'error', 'message': 'Evento inválido'};
    });
  }

  Future<dynamic> invoke(String method, [Map<String, dynamic>? args]) {
    return _methods.invokeMethod(method, args);
  }
}
