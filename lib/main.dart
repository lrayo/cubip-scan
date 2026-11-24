import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_auth_session.dart';
import 'config/app_config.dart';
import 'screens/app_gate.dart';
import 'sink/http_reads_sink.dart';
import 'sink/rfid_reads_dto.dart';
import 'sink/offline_queue.dart';
import 'sink/reads_api.dart';
import 'state/app_controller.dart';
import 'theme/cubip_theme.dart';
import 'location/location.dart';
import 'location/location_directory_api.dart';
import 'models/reader_device.dart';
import 'warehouse/warehouse.dart';
import 'warehouse/warehouse_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CubipScanApp(controller: await createProductionController()));
}

Future<AppController> createProductionController() async {
  final prefs = await SharedPreferences.getInstance();
  final config = AppConfig(
    issuer: prefs.getString('cubip.issuer') ?? '',
    apiBaseUrl: prefs.getString('cubip.apiBase') ?? '',
    keycloakUrl: prefs.getString('cubip.keycloak') ?? '',
    realm: prefs.getString('cubip.realm') ?? AppConfig.defaultRealm,
  );
  config.addListener(() {
    unawaited(prefs.setString('cubip.issuer', config.issuer));
    unawaited(prefs.setString('cubip.apiBase', config.apiBaseUrl));
    unawaited(prefs.setString('cubip.keycloak', config.keycloakUrl));
    unawaited(prefs.setString('cubip.realm', config.realm));
  });
  final auth = AppAuthSession(config: config);
  await auth.restore();
  final dir = await getApplicationSupportDirectory();
  final queue = FileOfflineQueue(File('${dir.path}/rfid_reads_queue.json'));
  await queue.load();
  Warehouse? currentWarehouse;
  ReaderDevice? currentReader;
  Location? currentLocation;
  final httpSink = HttpReadsSink(
    api: HttpReadsApi(config: config),
    queue: queue,
    tokenProvider: auth.accessToken,
    tokenRefresher: auth.refreshAccessToken,
    warehouseIdProvider: () => currentWarehouse?.id,
    locationIdProvider: () => currentLocation?.id,
    readerIdProvider: () {
      final device = currentReader;
      if (device == null) return null;
      final raw = device.name.isNotEmpty ? device.name : device.id;
      return RfidReadsDto.normalizeReaderId(raw);
    },
  );
  final controller = AppController(
    auth: auth,
    config: config,
    httpSink: httpSink,
    warehouses: HttpWarehouseRepository(
      config: config,
      tokenProvider: auth.accessToken,
      tokenRefresher: auth.refreshAccessToken,
      userIdProvider: () async => auth.userId,
      cache: FileWarehouseListCache(Directory('${dir.path}/warehouses')),
    ),
    demoWarehouses: const FakeWarehouseRepository(),
    locations: HttpLocationRepository(
      config: config,
      tokenProvider: auth.accessToken,
      tokenRefresher: auth.refreshAccessToken,
      cache: FileLocationDirectoryCache(Directory('${dir.path}/location-directory')),
    ),
    demoLocations: const FakeLocationRepository(),
  );
  controller.addListener(() {
    currentWarehouse = controller.selectedWarehouse;
    currentReader = controller.selected;
    currentLocation = controller.selectedLocation;
  });
  await controller.restore();
  currentWarehouse = controller.selectedWarehouse;
  currentReader = controller.selected;
  currentLocation = controller.selectedLocation;
  return controller;
}

class CubipScanApp extends StatelessWidget {
  const CubipScanApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cubip Scan',
      debugShowCheckedModeBanner: false,
      theme: CubipTheme.dark,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppGate(controller: controller),
    );
  }
}
