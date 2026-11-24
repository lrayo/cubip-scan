import 'dart:async';

import 'package:cubip_rfid/cubip_rfid.dart';
import 'package:flutter/services.dart';

import '../models/reader_device.dart';
import '../models/tag_read.dart';
import 'rfid_client.dart';

class PlatformRfidClient implements RfidClient {
  PlatformRfidClient({CubipRfid? plugin, DateTime Function()? clock})
      : _plugin = plugin ?? CubipRfid(),
        _clock = clock ?? DateTime.now {
    _eventSub = _plugin.events().listen(_onEvent, onError: (Object e) {
      _errors.add(e.toString());
    });
  }

  final CubipRfid _plugin;
  final DateTime Function() _clock;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  final _devices = StreamController<ReaderDevice>.broadcast();
  final _reads = StreamController<TagRead>.broadcast();
  final _connection = StreamController<ReaderConnectionState>.broadcast();
  final _errors = StreamController<String>.broadcast();

  @override
  bool get isDemo => false;

  @override
  Stream<ReaderDevice> get devices => _devices.stream;

  @override
  Stream<TagRead> get reads => _reads.stream;

  @override
  Stream<ReaderConnectionState> get connection => _connection.stream;

  @override
  Stream<String> get errors => _errors.stream;

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'device':
        _devices.add(ReaderDevice.fromMap(event));
      case 'connection':
        final state = event['state'] as String? ?? 'disconnected';
        _connection.add(switch (state) {
          'connected' => ReaderConnectionState.connected,
          'connecting' => ReaderConnectionState.connecting,
          _ => ReaderConnectionState.disconnected,
        });
        final message = event['message'] as String?;
        if (message != null && message.isNotEmpty && state != 'connected') {
          _errors.add(message);
        }
      case 'read':
        try {
          _reads.add(TagRead.fromMap(event, now: _clock()));
        } on FormatException catch (e) {
          _errors.add(e.message);
        }
      case 'error':
        final message = event['message'] as String? ?? 'Error del lector';
        _errors.add(message);
    }
  }

  @override
  Future<void> requestPermissions() => _invoke('requestPermissions');

  @override
  Future<void> startScan() => _invoke('startScan');

  @override
  Future<void> stopScan() => _invoke('stopScan');

  @override
  Future<void> connect(String deviceId) async {
    _connection.add(ReaderConnectionState.connecting);
    await _invoke('connect', {'deviceId': deviceId});
  }

  @override
  Future<void> disconnect() => _invoke('disconnect');

  @override
  Future<void> startInventory() => _invoke('startInventory');

  @override
  Future<void> stopInventory() => _invoke('stopInventory');

  @override
  Future<void> setPower(int dBm) => _invoke('setPower', {'power': dBm});

  @override
  Future<int?> getPower() async {
    try {
      final value = await _plugin.invoke('getPower');
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    } on PlatformException catch (e) {
      _errors.add(e.message ?? e.code);
      return null;
    }
  }

  @override
  Future<void> applyColombiaBand() => _invoke('applyColombiaBand');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _plugin.invoke(method, args);
    } on PlatformException catch (e) {
      _errors.add(e.message ?? e.code);
      rethrow;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _devices.close();
    _reads.close();
    _connection.close();
    _errors.close();
  }
}
