import 'dart:async';
import 'dart:math';

import '../models/reader_device.dart';
import '../models/tag_read.dart';
import 'rfid_client.dart';

/// Cliente simulado para presentar la app sin el lector físico.
class DemoRfidClient implements RfidClient {
  DemoRfidClient({Random? random, DateTime Function()? clock})
      : _random = random ?? Random(7),
        _clock = clock ?? DateTime.now;

  static const demoDevice = ReaderDevice(
    id: 'demo-gee-ur-a7',
    name: 'GEE-UR-A7 (demo)',
    rssi: -42,
  );

  static const _sampleEpcs = [
    'E2801170000002143A5B6C7D',
    'E2801170000002143A5B6C8A',
    'E2801170000002143A5B6C9B',
    '300833B2DDD9014000000001',
    '300833B2DDD9014000000002',
    '3034257BF468D48000000001',
  ];

  final Random _random;
  final DateTime Function() _clock;

  final _devices = StreamController<ReaderDevice>.broadcast();
  final _reads = StreamController<TagRead>.broadcast();
  final _connection = StreamController<ReaderConnectionState>.broadcast();
  final _errors = StreamController<String>.broadcast();

  ReaderConnectionState _state = ReaderConnectionState.disconnected;
  Timer? _inventoryTimer;
  int _power = 26;

  @override
  bool get isDemo => true;

  @override
  Stream<ReaderDevice> get devices => _devices.stream;

  @override
  Stream<TagRead> get reads => _reads.stream;

  @override
  Stream<ReaderConnectionState> get connection => _connection.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {
    _devices.add(demoDevice);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    _state = ReaderConnectionState.connecting;
    _connection.add(_state);
    _state = ReaderConnectionState.connected;
    _connection.add(_state);
  }

  @override
  Future<void> disconnect() async {
    await stopInventory();
    _state = ReaderConnectionState.disconnected;
    _connection.add(_state);
  }

  @override
  Future<void> startInventory() async {
    if (_state != ReaderConnectionState.connected) {
      _errors.add('Conecta un lector o activa el modo demo.');
      return;
    }
    _inventoryTimer?.cancel();
    _inventoryTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      final epc = _sampleEpcs[_random.nextInt(_sampleEpcs.length)];
      final includeTid = _random.nextBool();
      _reads.add(
        TagRead(
          epc: epc,
          tid: includeTid ? 'E2801100${epc.substring(epc.length - 8)}' : null,
          rssi: -38 - _random.nextInt(28),
          antenna: 1,
          timestamp: _clock(),
        ),
      );
    });
  }

  @override
  Future<void> stopInventory() async {
    _inventoryTimer?.cancel();
    _inventoryTimer = null;
  }

  @override
  Future<void> setPower(int dBm) async {
    _power = dBm.clamp(5, 33);
  }

  @override
  Future<int?> getPower() async => _power;

  @override
  Future<void> applyColombiaBand() async {}

  @override
  void dispose() {
    _inventoryTimer?.cancel();
    _devices.close();
    _reads.close();
    _connection.close();
    _errors.close();
  }
}
