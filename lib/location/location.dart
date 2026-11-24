import '../models/tag_read.dart';
import '../warehouse/warehouse.dart';

/// Ubicación del directorio de una bodega (`LocationDirectoryEntry`).
class Location {
  const Location({
    required this.id,
    required this.warehouseId,
    required this.code,
    required this.name,
    this.labelEpc,
  });

  final String id;
  final String warehouseId;
  /// Código principal para mostrar (p. ej. A01-01-01).
  final String code;
  /// Nombre secundario, armado por la API.
  final String name;
  /// EPC de la etiqueta del bin en hex mayúsculas, o null si no hay etiqueta.
  final String? labelEpc;

  Map<String, dynamic> toJson() => {
        'id': id,
        'warehouse_id': warehouseId,
        'code': code,
        'name': name,
        'label_epc': labelEpc,
      };

  factory Location.fromJson(Map<Object?, Object?> map, {String? warehouseId}) {
    final epc = map['label_epc'] ?? map['epc'];
    final rawEpc = epc == null ? null : '$epc';
    return Location(
      id: '${map['id']}',
      warehouseId: warehouseId ?? '${map['warehouse_id'] ?? map['warehouseId'] ?? ''}',
      code: '${map['code'] ?? ''}',
      name: '${map['name'] ?? ''}',
      labelEpc: (rawEpc == null || rawEpc.isEmpty || rawEpc == 'null')
          ? null
          : normalizeLabelEpc(rawEpc),
    );
  }

  /// Compatibilidad con el mapa anterior.
  factory Location.fromMap(Map<Object?, Object?> map) => Location.fromJson(map);

  Map<String, dynamic> toMap() => toJson();
}

class LocationDirectoryResult {
  const LocationDirectoryResult({
    required this.locations,
    this.fromCache = false,
    this.fetchedAt,
  });

  final List<Location> locations;
  final bool fromCache;
  final DateTime? fetchedAt;
}

/// Directorio de ubicaciones por bodega.
abstract class LocationRepository {
  Future<LocationDirectoryResult> listByWarehouse(
    String warehouseId, {
    bool forceRefresh = false,
  });
}

class FakeLocationRepository implements LocationRepository {
  const FakeLocationRepository({this.locations = defaultLocations});

  static const binA12Id = '2b1e4c3a-5d6f-4a7b-8c9d-0e1f2a3b4c5d';
  static const binA12Epc = 'E28011700000020F10C00012';
  static const binA12Code = 'A01-01-01';

  static const defaultLocations = [
    Location(
      id: binA12Id,
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: binA12Code,
      name: 'Zona A · Rack 01 · Nivel 01 · A01-01-01',
      labelEpc: binA12Epc,
    ),
    Location(
      id: '11a22b33-c44d-4e55-8f66-778899aabbcc',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'A01-01-02',
      name: 'Zona A · Rack 01 · Nivel 01 · A01-01-02',
    ),
    Location(
      id: '0aa11bb2-2cc3-4dd4-8ee5-ff6677889900',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'MUELLE-1',
      name: 'Muelle 1',
      labelEpc: 'E28011700000020F10C00001',
    ),
    Location(
      id: 'c0ffee00-1111-4222-8333-444455556666',
      warehouseId: FakeWarehouseRepository.medellinId,
      code: 'B01-01-01',
      name: 'Pasillo B · Bin 01',
      labelEpc: 'E28011700000020F10C00B01',
    ),
    Location(
      id: 'abcdef01-2345-4678-8abc-def012345678',
      warehouseId: FakeWarehouseRepository.caliId,
      code: 'C01-01-01',
      name: 'Pasillo C · Bin 01',
      labelEpc: 'E28011700000020F10C00C01',
    ),
  ];

  final List<Location> locations;

  static List<Location> forWarehouse(String warehouseId) =>
      defaultLocations.where((item) => item.warehouseId == warehouseId).toList();

  @override
  Future<LocationDirectoryResult> listByWarehouse(
    String warehouseId, {
    bool forceRefresh = false,
  }) async {
    return LocationDirectoryResult(
      locations: List.unmodifiable(
        locations.where((item) => item.warehouseId == warehouseId),
      ),
    );
  }
}

/// Hex en mayúsculas, sin espacios ni prefijo 0x, solo dígitos 0-9A-F.
String normalizeLabelEpc(String raw) {
  var value = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (value.startsWith('0X')) {
    value = value.substring(2);
  }
  return value.replaceAll(RegExp(r'[^0-9A-F]'), '');
}

/// Filtra el directorio por prefijo de [code], sin distinguir mayúsculas.
List<Location> filterLocationsByCodePrefix(List<Location> locations, String prefix) {
  final needle = prefix.trim().toUpperCase();
  if (needle.isEmpty) return List.unmodifiable(locations);
  return [
    for (final location in locations)
      if (location.code.toUpperCase().startsWith(needle)) location,
  ];
}

/// Toma la lectura con más señal y la resuelve contra [label_epc].
Location? resolveLocationFromReads({
  required List<TagRead> reads,
  required List<Location> locations,
}) {
  if (reads.isEmpty || locations.isEmpty) return null;
  var best = reads.first;
  for (final read in reads) {
    if (read.rssi > best.rssi) best = read;
  }
  final epc = normalizeLabelEpc(best.epc);
  if (epc.isEmpty) return null;
  for (final location in locations) {
    final tag = location.labelEpc;
    if (tag == null || tag.isEmpty) continue;
    if (normalizeLabelEpc(tag) == epc) return location;
  }
  return null;
}

const locationNotFoundMessage =
    'La etiqueta leída no coincide con ninguna ubicación de esta bodega.';
