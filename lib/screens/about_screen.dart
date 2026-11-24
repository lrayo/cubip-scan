import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Center(
            child: Image.asset(
              'assets/logo/cubip-logo-apilado-oscuro-512.png',
              width: 140,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cubip Scan',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CubipTheme.displayFamily,
              fontWeight: FontWeight.w700,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aplicación móvil para el lector RFID GEE-UR-A7. Se conecta por Bluetooth.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CubipColors.secondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  const _AboutRow(label: 'Versión', value: '1.0.0'),
                  const _AboutRow(label: 'Lector', value: 'GEE-UR-A7'),
                  const _AboutRow(label: 'Banda', value: 'Colombia (915–928 MHz)'),
                  const _AboutRow(label: 'Idioma', value: 'Español'),
                  _AboutRow(
                    label: 'Modo',
                    value: controller.demoMode ? 'Demo' : 'Lector físico',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Las lecturas se envían a Cubip cuando hay conexión. Si no hay señal, se guardan y se reintentan solas.',
            style: TextStyle(color: CubipColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: CubipColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
