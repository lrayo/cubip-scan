import 'package:flutter_test/flutter_test.dart';
import 'package:cubip_rfid/cubip_rfid.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invoke envía el método por el canal', () async {
    const channel = MethodChannel('cubip_rfid');
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return 26;
    });
    final plugin = CubipRfid(methodChannel: channel);
    expect(await plugin.invoke('getPower'), 26);
    expect(log.single.method, 'getPower');
  });
}
