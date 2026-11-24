import 'dart:async';

import 'package:cubip_scan/models/reader_device.dart';
import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/rfid/rfid_client.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeClient implements RfidClient {
  final devicesCtrl = StreamController<ReaderDevice>.broadcast();
  final readsCtrl = StreamController<TagRead>.broadcast();
  final connectionCtrl = StreamController<ReaderConnectionState>.broadcast();
  final errorsCtrl = StreamController<String>.broadcast();
  bool started = false;
  bool inventory = false;
  int? power;

  @override
  bool get isDemo => true;
  @override
  Stream<ReaderDevice> get devices => devicesCtrl.stream;
  @override
  Stream<TagRead> get reads => readsCtrl.stream;
  @override
  Stream<ReaderConnectionState> get connection => connectionCtrl.stream;
  @override
  Stream<String> get errors => errorsCtrl.stream;
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> startScan() async => started = true;
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String deviceId) async {
    connectionCtrl.add(ReaderConnectionState.connected);
  }
  @override
  Future<void> disconnect() async {
    connectionCtrl.add(ReaderConnectionState.disconnected);
  }
  @override
  Future<void> startInventory() async => inventory = true;
  @override
  Future<void> stopInventory() async => inventory = false;
  @override
  Future<void> setPower(int dBm) async => power = dBm;
  @override
  Future<int?> getPower() async => power ?? 26;
  @override
  Future<void> applyColombiaBand() async {}
  @override
  void dispose() {
    devicesCtrl.close();
    readsCtrl.close();
    connectionCtrl.close();
    errorsCtrl.close();
  }
}

void main() {
  testWidgets('el controlador acumula lecturas y cambia de estado', (tester) async {
    final client = FakeClient();
    final controller = AppController(platformClient: client, demoClient: client);
    addTearDown(controller.dispose);

    await controller.startScan();
    expect(client.started, isTrue);

    const device = ReaderDevice(id: 'aa', name: 'GEE-UR-A7', rssi: -40);
    client.devicesCtrl.add(device);
    await tester.pump();
    expect(controller.devices.single.name, 'GEE-UR-A7');

    await controller.connect(device);
    await tester.pump();
    expect(controller.connection, ReaderConnectionState.connected);

    await controller.startInventory();
    expect(controller.inventoryRunning, isTrue);
    client.readsCtrl.add(TagRead(
      epc: 'E280AA',
      rssi: -33,
      antenna: 1,
      timestamp: DateTime.utc(2026, 11, 19, 21),
    ));
    await tester.pump();
    expect(controller.store.uniqueCount, 1);
    expect(controller.store.totalReads, 1);

    await controller.setPower(20);
    expect(controller.powerDbm, 20);
    expect(client.power, 20);
  });
}
