import 'package:cubip_scan/rfid/demo_rfid_client.dart';
import 'package:cubip_scan/screens/connect_screen.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:cubip_scan/theme/cubip_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la pantalla Conectar muestra el modo demo', (tester) async {
    final controller = AppController(
      demoClient: DemoRfidClient(),
      platformClient: DemoRfidClient(),
    );
    addTearDown(controller.dispose);
    await controller.setDemoMode(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: CubipTheme.dark,
        home: ConnectScreen(controller: controller),
      ),
    );
    await tester.pump();
    expect(find.text('Cubip Scan'), findsOneWidget);
    expect(find.text('Modo demo'), findsOneWidget);
    expect(find.text('GEE-UR-A7 (demo)'), findsOneWidget);
  });
}
