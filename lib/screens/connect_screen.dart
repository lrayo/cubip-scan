import 'package:material_ui/material_ui.dart';

import '../rfid/rfid_client.dart';
import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final connected =
            controller.connection == ReaderConnectionState.connected;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Conectar'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Text(
                    connected ? 'Conectado' : 'Sin conexión',
                    style: TextStyle(
                      fontFamily: CubipTheme.bodyFamily,
                      color: connected ? CubipColors.cyanSoft : CubipColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _HeroCard(),
              const SizedBox(height: 16),
              SwitchListTile(
                key: const Key('demo-mode-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Modo demo'),
                subtitle: const Text(
                  'Genera lecturas simuladas para presentar la app sin el lector.',
                ),
                value: controller.demoMode,
                activeThumbColor: CubipColors.navy,
                activeTrackColor: CubipColors.cyan,
                onChanged: (value) => controller.setDemoMode(value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('scan-button'),
                      onPressed: controller.startScan,
                      icon: const Icon(Icons.search),
                      label: const Text('Escanear lectores'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (connected)
                    OutlinedButton(
                      onPressed: controller.disconnect,
                      child: const Text('Desconectar'),
                    ),
                ],
              ),
              if (controller.statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.statusMessage!,
                  style: const TextStyle(color: CubipColors.cyanSoft),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Lectores cercanos',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: CubipTheme.displayFamily,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (controller.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Todavía no hay lectores. Pulsa escanear o activa el modo demo.',
                    style: TextStyle(color: CubipColors.muted),
                  ),
                )
              else
                ...controller.devices.map((device) {
                  final selected = controller.selected?.id == device.id && connected;
                  return Card(
                    key: Key('device-${device.id}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        Icons.rss_feed,
                        color: selected ? CubipColors.cyanSoft : CubipColors.secondary,
                      ),
                      title: Text(device.name),
                      subtitle: Text('Señal ${device.rssi} dBm'),
                      trailing: selected
                          ? const Text('Conectado', style: TextStyle(color: CubipColors.cyanSoft))
                          : TextButton(
                              onPressed: controller.connection ==
                                      ReaderConnectionState.connecting
                                  ? null
                                  : () => controller.connect(device),
                              child: Text(
                                controller.connection ==
                                        ReaderConnectionState.connecting
                                    ? 'Conectando…'
                                    : 'Conectar',
                              ),
                            ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CubipColors.navyRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CubipColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo/cubip-isotipo-256.png',
            width: 56,
            height: 56,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cubip Scan',
                  style: TextStyle(
                    fontFamily: CubipTheme.displayFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Lector RFID GEE-UR-A7 por Bluetooth.',
                  style: TextStyle(color: CubipColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
