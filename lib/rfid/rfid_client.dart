import '../models/reader_device.dart';
import '../models/tag_read.dart';

enum ReaderConnectionState { disconnected, connecting, connected }

abstract class RfidClient {
  Stream<ReaderDevice> get devices;
  Stream<TagRead> get reads;
  Stream<ReaderConnectionState> get connection;
  Stream<String> get errors;

  bool get isDemo;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> startInventory();
  Future<void> stopInventory();
  Future<void> setPower(int dBm);
  Future<int?> getPower();
  Future<void> applyColombiaBand();
  Future<void> requestPermissions();
  void dispose();
}
