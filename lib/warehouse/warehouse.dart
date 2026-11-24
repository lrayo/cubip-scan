/// Bodega accesible para el usuario (`WarehouseSummary` del contrato).
class Warehouse {
  const Warehouse({
    required this.id,
    required this.code,
    required this.name,
    this.status,
  });

  final String id;
  final String code;
  final String name;
  /// `ACTIVE` o `INACTIVE`, si la API lo envía.
  final String? status;

  bool get isInactive => status != null && status!.toUpperCase() == 'INACTIVE';

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        if (status != null) 'status': status,
      };

  factory Warehouse.fromJson(Map<Object?, Object?> map) {
    return Warehouse(
      id: '${map['id']}',
      code: '${map['code'] ?? ''}',
      name: '${map['name'] ?? ''}',
      status: map['status'] == null || '${map['status']}'.isEmpty ? null : '${map['status']}',
    );
  }

  Map<String, dynamic> toMap() => toJson();

  factory Warehouse.fromMap(Map<Object?, Object?> map) => Warehouse.fromJson(map);
}

class WarehouseListResult {
  const WarehouseListResult({
    required this.warehouses,
    this.fromCache = false,
    this.fetchedAt,
    this.warning,
    this.error,
  });

  final List<Warehouse> warehouses;
  final bool fromCache;
  final DateTime? fetchedAt;
  final String? warning;
  final WarehouseListException? error;
}

class WarehouseListException implements Exception {
  const WarehouseListException({
    required this.message,
    this.statusCode = 0,
    this.canRetry = true,
    this.isForbidden = false,
    this.isSessionExpired = false,
  });

  final String message;
  final int statusCode;
  final bool canRetry;
  final bool isForbidden;
  final bool isSessionExpired;

  @override
  String toString() => message;
}

const warehouseForbiddenMessage =
    'No tienes acceso a las bodegas. Pide acceso a tu administrador.';
const warehouseEmptyMessage = 'No tienes bodegas asignadas todavía.';
const warehouseUnavailableMessage =
    'No se pudieron cargar las bodegas. Inténtalo de nuevo.';
const warehouseBadRequestMessage =
    'No se pudieron cargar las bodegas. Inténtalo de nuevo.';

abstract class WarehouseRepository {
  Future<WarehouseListResult> list({bool forceRefresh = false});
}

/// Datos falsos para el modo demo y para las pruebas.
class FakeWarehouseRepository implements WarehouseRepository {
  const FakeWarehouseRepository({this.warehouses = defaultWarehouses});

  /// UUIDs del ejemplo del contrato (BOG-01 / MDE-01) más Cali para la demo.
  static const bogotaId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
  static const medellinId = '8d0f778a-8536-41ef-a55c-f18fd2fa1bf8';
  static const caliId = 'a2b3c4d5-e6f7-4a89-8b0c-1d2e3f4a5b6c';

  static const defaultWarehouses = [
    Warehouse(
      id: bogotaId,
      code: 'BOG-01',
      name: 'Centro de distribución Bogotá',
      status: 'ACTIVE',
    ),
    Warehouse(
      id: medellinId,
      code: 'MDE-01',
      name: 'Bodega Medellín',
      status: 'INACTIVE',
    ),
    Warehouse(
      id: caliId,
      code: 'CLO-01',
      name: 'Bodega Cali',
      status: 'ACTIVE',
    ),
  ];

  final List<Warehouse> warehouses;

  @override
  Future<WarehouseListResult> list({bool forceRefresh = false}) async {
    return WarehouseListResult(warehouses: List.unmodifiable(warehouses));
  }
}
