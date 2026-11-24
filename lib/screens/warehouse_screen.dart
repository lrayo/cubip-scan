import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';
import '../warehouse/warehouse.dart';

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.controller.warehousesLoaded &&
        widget.controller.warehouses.isEmpty &&
        !widget.controller.warehousesLoading) {
      widget.controller.loadWarehouses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bodega'),
            actions: [
              IconButton(
                key: const Key('refresh-warehouses'),
                tooltip: 'Actualizar',
                onPressed: controller.warehousesLoading ? null : controller.refreshWarehouses,
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: controller.logout,
                child: const Text('Salir'),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'Elige la bodega en la que vas a leer etiquetas. Las lecturas se enviarán asociadas a esa bodega.',
                  style: TextStyle(color: CubipColors.secondary, height: 1.4),
                ),
              ),
              if (controller.warehousesFromCache)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Sin conexión: se muestran las bodegas guardadas.',
                    style: TextStyle(color: CubipColors.muted, fontSize: 13),
                  ),
                ),
              if (controller.warehousesError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    controller.warehousesError!,
                    key: const Key('warehouses-error'),
                    style: TextStyle(
                      color: controller.warehousesForbidden ? CubipColors.muted : Colors.orangeAccent,
                      height: 1.4,
                    ),
                  ),
                ),
              if (controller.warehousesCanRetry && !controller.warehousesLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: const Key('retry-warehouses'),
                      onPressed: controller.refreshWarehouses,
                      child: const Text('Reintentar'),
                    ),
                  ),
                ),
              if (controller.warehousesLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(child: _body(controller)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(AppController controller) {
    if (controller.warehousesForbidden && controller.warehouses.isEmpty) {
      return const SizedBox.shrink();
    }
    if (controller.warehouses.isEmpty && controller.warehousesError == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          warehouseEmptyMessage,
          key: Key('warehouses-empty'),
          style: TextStyle(color: CubipColors.muted, height: 1.4, fontSize: 16),
        ),
      );
    }
    if (controller.warehouses.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: controller.warehouses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final warehouse = controller.warehouses[index];
        final selected = controller.selectedWarehouse?.id == warehouse.id;
        return Card(
          key: Key('warehouse-${warehouse.id}'),
          child: ListTile(
            leading: Icon(
              Icons.warehouse_outlined,
              color: selected ? CubipColors.cyanSoft : CubipColors.secondary,
            ),
            title: Text(
              warehouse.code,
              style: const TextStyle(
                fontFamily: CubipTheme.displayFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(warehouse.name),
            trailing: selected
                ? const Icon(Icons.check_circle, color: CubipColors.cyanSoft)
                : (warehouse.isInactive
                    ? const Text('Inactiva', style: TextStyle(color: CubipColors.muted, fontSize: 12))
                    : null),
            onTap: () => controller.selectWarehouse(warehouse),
          ),
        );
      },
    );
  }
}
