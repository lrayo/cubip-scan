import 'dart:io';

import 'package:cubip_scan/models/tag_read.dart';
import 'package:cubip_scan/rfid/demo_rfid_client.dart';
import 'package:cubip_scan/rfid/rfid_client.dart';
import 'package:cubip_scan/auth/auth_session.dart';
import 'package:cubip_scan/screens/login_screen.dart';
import 'package:cubip_scan/screens/warehouse_screen.dart';
import 'package:cubip_scan/sink/fake_reads_sink.dart';
import 'package:cubip_scan/location/location.dart';
import 'package:cubip_scan/screens/location_screen.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:cubip_scan/screens/home_shell.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:cubip_scan/theme/cubip_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';

Future<void> loadFonts() async {
  Future<void> load(String family, String asset, [int? weight]) async {
    final loader = FontLoader(family);
    final data = rootBundle.load(asset);
    loader.addFont(data);
    await loader.load();
  }

  await load('Sora', 'assets/fonts/Sora-Variable.ttf');
  await load('IBMPlexSans', 'assets/fonts/IBMPlexSans-Regular.ttf', 400);
  final iconFile = File('/home/box/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await loader.load();
  }
}

AppController demoController({int pending = 0, int sent = 0}) {
  final demoSink = FakeReadsSink(autoFlush: false);
  demoSink.seed(pending: pending, sent: sent);
  final controller = AppController(
    auth: MemoryAuthSession(loggedIn: true, demo: true),
    demoClient: DemoRfidClient(),
    platformClient: DemoRfidClient(),
    demoSink: demoSink,
  );
  controller.demoMode = true;
  controller.devices
    ..clear()
    ..add(DemoRfidClient.demoDevice);
  controller.selected = DemoRfidClient.demoDevice;
  controller.connection = ReaderConnectionState.connected;
  controller.selectedWarehouse = FakeWarehouseRepository.defaultWarehouses.first;
  controller.warehouses = FakeWarehouseRepository.defaultWarehouses;
  controller.locations = FakeLocationRepository.forWarehouse(
    FakeWarehouseRepository.bogotaId,
  );
  return controller;
}

Widget wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: CubipTheme.dark,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadFonts();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(wrap(child));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/logo/cubip-isotipo-256.png'), tester.element(find.byType(MaterialApp)));
      await precacheImage(const AssetImage('assets/logo/cubip-logo-apilado-oscuro-512.png'), tester.element(find.byType(MaterialApp)));
    });
    await tester.pumpAndSettle();
  }

  Future<void> saveCopy(String name) async {
    final golden = File('test/goldens/$name.png');
    final destDir = Directory('screenshots');
    destDir.createSync(recursive: true);
    if (golden.existsSync()) {
      golden.copySync('screenshots/$name.png');
    }
  }

  testWidgets('pantalla Conectar en modo demo', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, HomeShell(controller: controller));
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/conectar.png'),
    );
    await saveCopy('conectar');
  });

  testWidgets('pantalla Lectura en modo demo con EPC', (tester) async {
    final controller = demoController(pending: 3, sent: 12);
    addTearDown(controller.dispose);
    controller.store.add(
      TagRead(
        epc: 'E2801170000002143A5B6C7D',
        tid: 'E28011003A5B6C7D',
        rssi: -41,
        antenna: 1,
        timestamp: DateTime(2026, 11, 19, 21, 15, 8),
      ),
    );
    controller.store.add(
      TagRead(
        epc: 'E2801170000002143A5B6C7D',
        rssi: -38,
        antenna: 1,
        timestamp: DateTime(2026, 11, 19, 21, 15, 10),
      ),
    );
    controller.store.add(
      TagRead(
        epc: '300833B2DDD9014000000001',
        rssi: -52,
        antenna: 1,
        timestamp: DateTime(2026, 11, 19, 21, 15, 9),
      ),
    );
    controller.selectedLocation = controller.locations.first;
    await pumpScreen(tester, HomeShell(controller: controller, initialIndex: 1));
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/lectura.png'),
    );
    await saveCopy('lectura');
  });

  testWidgets('pantalla Ajustes en modo demo', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    controller.powerDbm = 26;
    await pumpScreen(tester, HomeShell(controller: controller, initialIndex: 2));
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/ajustes.png'),
    );
    await saveCopy('ajustes');
  });

  testWidgets('pantalla Acerca de en modo demo', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, HomeShell(controller: controller, initialIndex: 3));
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/acerca_de.png'),
    );
    await saveCopy('acerca_de');
  });

  testWidgets('pantalla Login', (tester) async {
    final controller = AppController(
      auth: MemoryAuthSession(),
      demoClient: DemoRfidClient(),
      platformClient: DemoRfidClient(),
    );
    addTearDown(controller.dispose);
    await pumpScreen(tester, LoginScreen(controller: controller));
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login.png'),
    );
    await saveCopy('login');
  });

  testWidgets('pantalla Bodega', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    controller.selectedWarehouse = null;
    await pumpScreen(tester, WarehouseScreen(controller: controller));
    await expectLater(
      find.byType(WarehouseScreen),
      matchesGoldenFile('goldens/bodega.png'),
    );
    await saveCopy('bodega');
  });

  testWidgets('pantalla Bodega vacía', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    controller.selectedWarehouse = null;
    controller.warehouses = const [];
    controller.warehousesLoaded = true;
    await pumpScreen(tester, WarehouseScreen(controller: controller));
    await expectLater(
      find.byType(WarehouseScreen),
      matchesGoldenFile('goldens/bodega_vacia.png'),
    );
    await saveCopy('bodega_vacia');
  });

  testWidgets('selector de ubicación', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, LocationScreen(controller: controller));
    await expectLater(
      find.byType(LocationScreen),
      matchesGoldenFile('goldens/ubicacion.png'),
    );
    await saveCopy('ubicacion');
  });

  testWidgets('cáscara con navegación en modo demo', (tester) async {
    final controller = demoController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, HomeShell(controller: controller));
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/conectar_shell.png'),
    );
    await saveCopy('conectar_shell');
  });
}
