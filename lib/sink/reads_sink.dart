import 'package:flutter/foundation.dart';

import '../models/tag_read.dart';

/// Contrato para publicar lecturas (WMS u otro destino).
abstract class ReadsSink {
  Future<void> publish(TagRead read);
}

class NoOpReadsSink implements TrackingReadsSink {
  const NoOpReadsSink();

  @override
  Future<void> publish(TagRead read) async {}

  @override
  int get pendingCount => 0;

  @override
  int get sentCount => 0;

  @override
  Listenable get listenable => _noop;

  @override
  String? get lastError => null;

  static final _noop = ChangeNotifier();
}

/// Sink que reporta pendientes y enviadas para la UI.
abstract class TrackingReadsSink implements ReadsSink {
  int get pendingCount;
  int get sentCount;
  Listenable get listenable;
  String? get lastError;
}
