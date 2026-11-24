import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_session.dart';
import '../config/app_config.dart';
import '../config/connection_probe.dart';
import '../models/reader_device.dart';
import '../models/tag_read.dart';
import '../rfid/csv_export.dart';
import '../rfid/demo_rfid_client.dart';
import '../rfid/inventory_store.dart';
import '../rfid/platform_rfid_client.dart';
import '../rfid/rfid_client.dart';
import '../sink/fake_reads_sink.dart';
import '../sink/http_reads_sink.dart';
import '../sink/reads_sink.dart';
import '../location/location.dart';
import '../warehouse/warehouse.dart';

class AppController extends ChangeNotifier {
  AppController({
    RfidClient? platformClient,
    RfidClient? demoClient,
    AuthSession? auth,
    AppConfig? config,
    WarehouseRepository? warehouses,
    WarehouseRepository? demoWarehouses,
    LocationRepository? locations,
    LocationRepository? demoLocations,
    TrackingReadsSink? httpSink,
    TrackingReadsSink? demoSink,
    ConnectionProbe? connectionProbe,
  })  : _platformClient = platformClient ?? PlatformRfidClient(),
        _demoClient = demoClient ?? DemoRfidClient(),
        auth = auth ?? MemoryAuthSession(),
        config = config ?? AppConfig(),
        _prodWarehouses = warehouses ?? const FakeWarehouseRepository(),
        _demoWarehouses = demoWarehouses ?? const FakeWarehouseRepository(),
        _prodLocations = locations ?? const FakeLocationRepository(),
        _demoLocations = demoLocations ?? const FakeLocationRepository(),
        _httpSink = httpSink ?? FakeReadsSink(),
        _demoSink = demoSink ?? FakeReadsSink(),
        _connectionProbe = connectionProbe ?? ConnectionProbe() {
    _bind(_client);
    _activeSink.listenable.addListener(_onSinkChanged);
    _sinkSub = _onSinkChanged;
  }

  final RfidClient _platformClient;
  final RfidClient _demoClient;
  final AuthSession auth;
  final AppConfig config;
  final WarehouseRepository _prodWarehouses;
  final WarehouseRepository _demoWarehouses;
  final LocationRepository _prodLocations;
  final LocationRepository _demoLocations;
  final TrackingReadsSink _httpSink;
  final TrackingReadsSink _demoSink;
  final ConnectionProbe _connectionProbe;
  final InventoryStore store = InventoryStore();

  final List<ReaderDevice> devices = [];
  ReaderDevice? selected;
  ReaderConnectionState connection = ReaderConnectionState.disconnected;
  bool inventoryRunning = false;
  bool demoMode = false;
  int powerDbm = 26;
  String? statusMessage;
  Warehouse? selectedWarehouse;
  List<Warehouse> warehouses = const [];
  bool warehousesLoading = false;
  bool warehousesFromCache = false;
  String? warehousesError;
  bool warehousesCanRetry = false;
  bool warehousesForbidden = false;
  bool warehousesLoaded = false;
  bool connectionChecking = false;
  bool? connectionCheckOk;
  String? connectionCheckMessage;
  Location? selectedLocation;
  List<Location> locations = const [];
  bool locationsLoading = false;
  bool locationsFromCache = false;
  DateTime? locationsFetchedAt;
  String locationPrefix = '';
  bool pinningLocation = false;
  bool _startedInventoryForPin = false;
  final List<TagRead> _pinReads = [];

  final List<StreamSubscription<dynamic>> _subs = [];
  VoidCallback? _sinkSub;

  RfidClient get _client => demoMode ? _demoClient : _platformClient;

  TrackingReadsSink get _activeSink => demoMode ? _demoSink : _httpSink;

  LocationRepository get _locations => demoMode ? _demoLocations : _prodLocations;

  WarehouseRepository get _activeWarehouses =>
      demoMode ? _demoWarehouses : _prodWarehouses;

  List<Location> get visibleLocations =>
      filterLocationsByCodePrefix(locations, locationPrefix);

  bool get isLoggedIn => auth.isLoggedIn;

  int get pendingCount => _activeSink.pendingCount;

  int get sentCount => _activeSink.sentCount;

  String? get syncError => _activeSink.lastError;

  Future<void> restore() async {
    await auth.restore();
    if (auth.isDemoSession && !demoMode) {
      demoMode = true;
      _rebindSink();
    }
    notifyListeners();
  }

  Future<void> login() async {
    statusMessage = null;
    notifyListeners();
    try {
      await auth.login();
      await loadWarehouses();
      final sink = _httpSink;
      if (sink is HttpReadsSink) {
        await sink.resume();
      }
    } catch (e) {
      statusMessage = 'No se pudo iniciar sesión: $e';
    }
    notifyListeners();
  }

  Future<void> enterDemo() async {
    await auth.loginDemo();
    await setDemoMode(true);
    await loadWarehouses();
    notifyListeners();
  }

  Future<void> logout() async {
    await stopInventory();
    await _client.disconnect();
    selectedWarehouse = null;
    warehouses = const [];
    warehousesFromCache = false;
    warehousesError = null;
    warehousesCanRetry = false;
    warehousesForbidden = false;
    warehousesLoaded = false;
    selectedLocation = null;
    locations = const [];
    locationsFromCache = false;
    locationsFetchedAt = null;
    locationPrefix = '';
    pinningLocation = false;
    _pinReads.clear();
    await auth.logout();
    if (demoMode) {
      await setDemoMode(false);
    }
    notifyListeners();
  }

  Future<void> loadWarehouses({bool forceRefresh = false}) async {
    warehousesLoading = true;
    warehousesError = null;
    warehousesCanRetry = false;
    warehousesForbidden = false;
    notifyListeners();
    try {
      final result = await _activeWarehouses.list(forceRefresh: forceRefresh);
      warehouses = result.warehouses;
      warehousesFromCache = result.fromCache;
      if (result.fromCache) {
        warehousesCanRetry = true;
      }
      if (result.error != null && !result.fromCache) {
        warehousesError = result.error!.message;
        warehousesCanRetry = result.error!.canRetry;
        warehousesForbidden = result.error!.isForbidden;
      }
      final selected = selectedWarehouse;
      if (selected != null && warehouses.every((item) => item.id != selected.id)) {
        selectedWarehouse = null;
      }
    } on WarehouseListException catch (error) {
      warehousesFromCache = false;
      warehousesError = error.message;
      warehousesCanRetry = error.canRetry;
      warehousesForbidden = error.isForbidden;
      if (error.isForbidden || error.isSessionExpired) {
        warehouses = const [];
      }
      if (error.isSessionExpired) {
        statusMessage = error.message;
      }
    } catch (_) {
      warehousesFromCache = false;
      warehousesError = warehouseUnavailableMessage;
      warehousesCanRetry = true;
    } finally {
      warehousesLoading = false;
      warehousesLoaded = true;
      notifyListeners();
    }
  }

  Future<void> refreshWarehouses() => loadWarehouses(forceRefresh: true);

  void selectWarehouse(Warehouse warehouse) {
    selectedWarehouse = warehouse;
    selectedLocation = null;
    unawaited(loadLocations());
    notifyListeners();
  }

  void clearWarehouse() {
    selectedWarehouse = null;
    warehouses = const [];
    warehousesFromCache = false;
    warehousesError = null;
    warehousesCanRetry = false;
    warehousesForbidden = false;
    warehousesLoaded = false;
    selectedLocation = null;
    locations = const [];
    locationsFromCache = false;
    locationsFetchedAt = null;
    locationPrefix = '';
    notifyListeners();
  }

  Future<void> loadLocations({bool forceRefresh = false}) async {
    final warehouse = selectedWarehouse;
    if (warehouse == null) {
      locations = const [];
      locationsFromCache = false;
      locationsFetchedAt = null;
      notifyListeners();
      return;
    }
    locationsLoading = true;
    notifyListeners();
    try {
      final result = await _locations.listByWarehouse(
        warehouse.id,
        forceRefresh: forceRefresh,
      );
      locations = result.locations;
      locationsFromCache = result.fromCache;
      locationsFetchedAt = result.fetchedAt;
      if (result.fromCache) {
        statusMessage = 'Sin conexión: se muestran las ubicaciones guardadas.';
      }
    } catch (e) {
      statusMessage = 'No se pudieron cargar las ubicaciones.';
    } finally {
      locationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLocations() => loadLocations(forceRefresh: true);

  void setLocationPrefix(String value) {
    locationPrefix = value;
    notifyListeners();
  }

  void selectLocation(Location location) {
    if (selectedLocation?.id != location.id) {
      unawaited(_flushOpenBatch());
    }
    selectedLocation = location;
    pinningLocation = false;
    _pinReads.clear();
    statusMessage = null;
    notifyListeners();
  }

  void clearLocation() {
    if (selectedLocation != null) {
      unawaited(_flushOpenBatch());
    }
    selectedLocation = null;
    notifyListeners();
  }

  Future<void> _flushOpenBatch() async {
    final sink = _activeSink;
    if (sink is HttpReadsSink) {
      await sink.flush();
    }
  }

  Future<void> startPinLocation() async {
    _pinReads.clear();
    pinningLocation = true;
    statusMessage = 'Acerca la etiqueta del bin…';
    notifyListeners();
    if (!inventoryRunning) {
      _startedInventoryForPin = true;
      await startInventory();
    } else {
      _startedInventoryForPin = false;
    }
  }

  Future<void> cancelPinLocation() async {
    pinningLocation = false;
    _pinReads.clear();
    statusMessage = null;
    notifyListeners();
    if (_startedInventoryForPin) {
      _startedInventoryForPin = false;
      await stopInventory();
    }
  }

  /// Expone la resolución para tests: la lectura con más señal contra la lista.
  Location? resolvePinnedLocation(List<TagRead> reads) {
    return resolveLocationFromReads(reads: reads, locations: locations);
  }

  Future<void> setIssuer(String value) async {
    config.setIssuer(value);
    notifyListeners();
  }

  Future<void> setApiBaseUrl(String value) async {
    config.setApiBaseUrl(value);
    notifyListeners();
  }

  Future<void> setKeycloakUrl(String value) async {
    config.setKeycloakUrl(value);
    notifyListeners();
  }

  Future<void> setRealm(String value) async {
    config.setRealm(value);
    notifyListeners();
  }

  Future<void> testConnection() async {
    connectionChecking = true;
    connectionCheckOk = null;
    connectionCheckMessage = 'Comprobando…';
    notifyListeners();
    final result = await _connectionProbe.check(config);
    connectionCheckOk = result.ok;
    connectionCheckMessage = result.message;
    connectionChecking = false;
    notifyListeners();
  }

  Future<void> setDemoMode(bool enabled) async {
    if (demoMode == enabled) return;
    await stopInventory();
    await _client.disconnect();
    _unbind();
    devices.clear();
    selected = null;
    connection = ReaderConnectionState.disconnected;
    demoMode = enabled;
    _bind(_client);
    _rebindSink();
    notifyListeners();
    if (enabled) {
      await _client.startScan();
    }
  }

  Future<void> startScan() async {
    devices.clear();
    notifyListeners();
    try {
      await _client.requestPermissions();
      await _client.startScan();
    } catch (e) {
      statusMessage = 'No se pudo iniciar el escaneo: $e';
      notifyListeners();
    }
  }

  Future<void> stopScan() => _client.stopScan();

  Future<void> connect(ReaderDevice device) async {
    selected = device;
    notifyListeners();
    try {
      await _client.connect(device.id);
      final power = await _client.getPower();
      if (power != null) {
        powerDbm = power;
      }
      await _client.applyColombiaBand();
    } catch (e) {
      statusMessage = 'No se pudo conectar: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await stopInventory();
    await _client.disconnect();
  }

  Future<void> startInventory() async {
    inventoryRunning = true;
    notifyListeners();
    try {
      await _client.startInventory();
    } catch (e) {
      inventoryRunning = false;
      statusMessage = 'No se pudo iniciar la lectura: $e';
      notifyListeners();
    }
  }

  Future<void> stopInventory() async {
    final wasPinning = pinningLocation;
    inventoryRunning = false;
    if (wasPinning) {
      pinningLocation = false;
      _startedInventoryForPin = false;
      if (selectedLocation == null) {
        statusMessage = locationNotFoundMessage;
      }
      _pinReads.clear();
    }
    notifyListeners();
    await _client.stopInventory();
  }

  void _onPinRead(TagRead read) {
    _pinReads.add(read);
    final resolved = resolveLocationFromReads(reads: _pinReads, locations: locations);
    if (resolved != null) {
      selectedLocation = resolved;
      pinningLocation = false;
      _pinReads.clear();
      statusMessage = 'Ubicación fijada: ${resolved.name}';
      notifyListeners();
      if (_startedInventoryForPin) {
        _startedInventoryForPin = false;
        unawaited(stopInventory());
      }
      return;
    }
    notifyListeners();
  }

  void clearInventory() {
    store.clear();
    notifyListeners();
  }

  Future<void> setPower(int dBm) async {
    powerDbm = dBm.clamp(5, 33);
    notifyListeners();
    try {
      await _client.setPower(powerDbm);
    } catch (e) {
      statusMessage = 'No se pudo aplicar la potencia: $e';
      notifyListeners();
    }
  }

  Future<void> applyColombiaBand() async {
    try {
      await _client.applyColombiaBand();
      statusMessage = 'Banda Colombia aplicada (915–928 MHz).';
    } catch (e) {
      statusMessage = 'No se pudo aplicar la banda: $e';
    }
    notifyListeners();
  }

  Future<void> exportCsv() async {
    final csv = inventoryToCsv(store.entries);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/cubip-scan-${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]),
    );
  }

  void _bind(RfidClient client) {
    _subs.add(client.devices.listen((device) {
      final index = devices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        devices[index] = device;
      } else {
        devices.add(device);
      }
      notifyListeners();
    }));
    _subs.add(client.reads.listen((TagRead read) {
      if (pinningLocation) {
        _onPinRead(read);
        return;
      }
      store.add(read);
      unawaited(_activeSink.publish(read));
      notifyListeners();
    }));
    _subs.add(client.connection.listen((state) {
      connection = state;
      notifyListeners();
    }));
    _subs.add(client.errors.listen((message) {
      statusMessage = message;
      notifyListeners();
    }));
  }

  void _unbind() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  void _rebindSink() {
    if (_sinkSub != null) {
      _httpSink.listenable.removeListener(_onSinkChanged);
      _demoSink.listenable.removeListener(_onSinkChanged);
    }
    _sinkSub = _onSinkChanged;
    _activeSink.listenable.addListener(_onSinkChanged);
  }

  void _onSinkChanged() => notifyListeners();

  @override
  void dispose() {
    _unbind();
    _httpSink.listenable.removeListener(_onSinkChanged);
    _demoSink.listenable.removeListener(_onSinkChanged);
    _platformClient.dispose();
    _demoClient.dispose();
    super.dispose();
  }
}
