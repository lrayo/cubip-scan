import 'package:material_ui/material_ui.dart';

import '../rfid/inventory_store.dart';
import '../rfid/rfid_client.dart';
import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';
import 'location_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.store.entries;
        final canRun =
            controller.connection == ReaderConnectionState.connected ||
                controller.demoMode;
        return Scaffold(
          appBar: AppBar(title: const Text('Lectura')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatChip(label: 'Únicos', value: '${controller.store.uniqueCount}'),
                        const SizedBox(width: 8),
                        _StatChip(label: 'Lecturas', value: '${controller.store.totalReads}'),
                        const Spacer(),
                        if (controller.inventoryRunning)
                          const Text('En curso', style: TextStyle(color: CubipColors.cyanSoft)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _SyncIndicator(
                      pending: controller.pendingCount,
                      sent: controller.sentCount,
                    ),
                    const SizedBox(height: 8),
                    _LocationBar(controller: controller),
                    if (controller.syncError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        controller.syncError!,
                        key: const Key('sync-error'),
                        style: const TextStyle(color: Color(0xFFFF8A80), height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('start-inventory'),
                      onPressed: canRun && !controller.inventoryRunning
                          ? controller.startInventory
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('stop-inventory'),
                      onPressed: controller.inventoryRunning
                          ? controller.stopInventory
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Detener'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('clear-inventory'),
                      onPressed: entries.isEmpty ? null : controller.clearInventory,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Limpiar'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('export-csv'),
                      onPressed: entries.isEmpty ? null : () => controller.exportCsv(),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Exportar CSV'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin lecturas. Pulsa Iniciar para ver las etiquetas.',
                          style: TextStyle(color: CubipColors.muted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _TagTile(entry: entry);
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CubipColors.navyRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CubipColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: CubipColors.muted, fontSize: 11)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: CubipTheme.displayFamily,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.entry});
  final InventoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.lastSeen.hour.toString().padLeft(2, '0')}:${entry.lastSeen.minute.toString().padLeft(2, '0')}:${entry.lastSeen.second.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        title: Text(
          entry.epc,
          style: const TextStyle(
            fontFamily: 'IBMPlexSans',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          [
            'Señal ${entry.rssi} dBm',
            'Ant. ${entry.antenna}',
            if (entry.tid != null) 'TID ${entry.tid}',
            time,
          ].join('  ·  '),
          style: const TextStyle(color: CubipColors.secondary, fontSize: 12),
        ),
        trailing: CircleAvatar(
          backgroundColor: const Color(0x3314B8C8),
          foregroundColor: CubipColors.cyanSoft,
          child: Text('${entry.count}'),
        ),
      ),
    );
  }
}



class _LocationBar extends StatelessWidget {
  const _LocationBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final location = controller.selectedLocation;
    final pinning = controller.pinningLocation;
    return Container(
      key: const Key('location-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CubipColors.navyRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CubipColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pinning ? Icons.sensors : Icons.place_outlined,
                size: 18,
                color: CubipColors.cyanSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pinning
                      ? 'Acerca la etiqueta del bin…'
                      : location == null
                          ? 'Sin ubicación (se envía igual)'
                          : 'Ubicación actual: ${location.code}',
                  key: const Key('location-label'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (location != null && !pinning)
                TextButton(
                  key: const Key('clear-location'),
                  onPressed: controller.clearLocation,
                  child: const Text('Quitar'),
                ),
              if (pinning)
                TextButton(
                  key: const Key('cancel-pin-location'),
                  onPressed: controller.cancelPinLocation,
                  child: const Text('Cancelar'),
                ),
            ],
          ),
          if (!pinning) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  key: const Key('start-pin-location'),
                  onPressed: controller.startPinLocation,
                  child: const Text('Fijar ubicación'),
                ),
                OutlinedButton(
                  key: const Key('choose-location'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LocationScreen(controller: controller),
                      ),
                    );
                  },
                  child: const Text('Elegir'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.pending, required this.sent});

  final int pending;
  final int sent;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sync-indicator'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CubipColors.navyRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CubipColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 18, color: CubipColors.cyanSoft),
          const SizedBox(width: 8),
          Text(
            'Pendientes $pending',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          Text(
            'Enviadas $sent',
            style: const TextStyle(color: CubipColors.secondary),
          ),
        ],
      ),
    );
  }
}
