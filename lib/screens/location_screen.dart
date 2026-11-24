import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  late final TextEditingController _prefix;

  @override
  void initState() {
    super.initState();
    _prefix = TextEditingController(text: widget.controller.locationPrefix);
  }

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final locations = controller.visibleLocations;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ubicación'),
            actions: [
              IconButton(
                key: const Key('refresh-locations'),
                tooltip: 'Actualizar',
                onPressed: controller.locationsLoading ? null : controller.refreshLocations,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const Text(
                'Elige una ubicación o fíjala leyendo la etiqueta del bin. Es opcional: las lecturas se envían igual sin ella.',
                style: TextStyle(color: CubipColors.secondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pin-location'),
                onPressed: () {
                  Navigator.of(context).maybePop();
                  controller.startPinLocation();
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Fijar ubicación'),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('location-prefix'),
                controller: _prefix,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por código',
                  hintText: 'A01-01',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: controller.setLocationPrefix,
              ),
              if (controller.locationsFromCache) ...[
                const SizedBox(height: 8),
                const Text(
                  'Sin conexión: se muestran las ubicaciones guardadas.',
                  style: TextStyle(color: CubipColors.muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Ubicaciones de la bodega',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: CubipTheme.displayFamily,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (controller.locationsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (locations.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No hay ubicaciones para esta bodega.',
                    style: TextStyle(color: CubipColors.muted),
                  ),
                )
              else
                for (final location in locations)
                  Card(
                    key: Key('location-${location.id}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        Icons.place_outlined,
                        color: controller.selectedLocation?.id == location.id
                            ? CubipColors.cyanSoft
                            : CubipColors.secondary,
                      ),
                      title: Text(
                        location.code,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: location.name.isEmpty ? null : Text(location.name),
                      trailing: controller.selectedLocation?.id == location.id
                          ? const Text('Actual', style: TextStyle(color: CubipColors.cyanSoft))
                          : null,
                      onTap: () {
                        controller.selectLocation(location);
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
