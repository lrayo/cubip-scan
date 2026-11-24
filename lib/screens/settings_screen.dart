import 'package:material_ui/material_ui.dart';

import '../config/app_config.dart';
import '../config/app_flavor.dart';
import '../rfid/frequency.dart';
import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channels = FrequencyTables.colombiaChannels;
        final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFamily: CubipTheme.displayFamily,
              fontWeight: FontWeight.w600,
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text('Potencia', style: titleStyle),
              const SizedBox(height: 4),
              Text(
                '${controller.powerDbm} dBm',
                key: const Key('power-value'),
                style: const TextStyle(
                  fontFamily: CubipTheme.displayFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: CubipColors.cyanSoft,
                ),
              ),
              Slider(
                key: const Key('power-slider'),
                min: 5,
                max: 33,
                divisions: 28,
                value: controller.powerDbm.toDouble(),
                label: '${controller.powerDbm} dBm',
                onChanged: (value) => controller.setPower(value.round()),
              ),
              const Text(
                'Rango típico: 5 a 33 dBm.',
                style: TextStyle(color: CubipColors.muted),
              ),
              const SizedBox(height: 28),
              Text('Banda', style: titleStyle),
              const SizedBox(height: 8),
              const Card(
                child: ListTile(
                  title: Text('Colombia (915–928 MHz)'),
                  subtitle: Text('Banda autorizada para operar en Colombia.'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('apply-band'),
                onPressed: controller.applyColombiaBand,
                child: const Text('Aplicar banda Colombia'),
              ),
              if (controller.statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.statusMessage!,
                  style: const TextStyle(color: CubipColors.cyanSoft),
                ),
              ],
              const SizedBox(height: 28),
              Text('Sesión', style: titleStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('change-warehouse'),
                    onPressed: controller.clearWarehouse,
                    child: const Text('Cambiar bodega'),
                  ),
                  OutlinedButton(
                    key: const Key('logout-button'),
                    onPressed: controller.logout,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('advanced-section'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text('Avanzado', style: titleStyle),
                  children: [
                    _AdvancedServerSection(controller: controller),
                    const SizedBox(height: 16),
                    const Text(
                      'FCC índice 3 (902.750–927.250 MHz), canales limitados a 915–928 MHz.',
                      style: TextStyle(color: CubipColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Canales activos (${channels.length})',
                      style: const TextStyle(color: CubipColors.secondary),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final mhz in channels)
                            Chip(
                              label: Text('$mhz MHz'),
                              backgroundColor: CubipColors.navyRaised,
                              side: const BorderSide(color: CubipColors.border, width: 0.6),
                              labelStyle: const TextStyle(fontSize: 12, color: CubipColors.paper),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdvancedServerSection extends StatefulWidget {
  const _AdvancedServerSection({required this.controller});

  final AppController controller;

  @override
  State<_AdvancedServerSection> createState() => _AdvancedServerSectionState();
}

class _AdvancedServerSectionState extends State<_AdvancedServerSection> {
  late final TextEditingController _api;
  late final TextEditingController _keycloak;
  late final TextEditingController _realm;
  late final TextEditingController _issuer;
  bool _updatingIssuer = false;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final config = _controller.config;
    _api = TextEditingController(text: config.apiBaseUrl);
    _keycloak = TextEditingController(text: config.keycloakUrl);
    _realm = TextEditingController(text: config.realm);
    _issuer = TextEditingController(text: config.trimmedIssuer);
  }

  void _onKeycloakChanged(String value) {
    _controller.setKeycloakUrl(value);
    _syncBuiltIssuer();
  }

  void _onRealmChanged(String value) {
    _controller.setRealm(value);
    _syncBuiltIssuer();
  }

  void _syncBuiltIssuer() {
    if (_controller.config.hasIssuerOverride) return;
    _updatingIssuer = true;
    _issuer.text = _controller.config.builtIssuer;
    _updatingIssuer = false;
  }

  @override
  void dispose() {
    _api.dispose();
    _keycloak.dispose();
    _realm.dispose();
    _issuer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final result = _controller.connectionCheckMessage;
        final ok = _controller.connectionCheckOk;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (AppFlavor.allowsLanHttp()) ...[
              const Text(
                'En el piloto puedes usar la IP de la red local, por ejemplo http://192.168.1.10:8080.',
                style: TextStyle(color: CubipColors.muted, fontSize: 12, height: 1.3),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('api-base-field'),
              controller: _api,
              decoration: const InputDecoration(
                labelText: 'URL de la API',
                hintText: AppConfig.defaultApiBaseUrl,
                border: OutlineInputBorder(),
              ),
              onChanged: _controller.setApiBaseUrl,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('keycloak-field'),
              controller: _keycloak,
              decoration: const InputDecoration(
                labelText: 'URL de Keycloak',
                hintText: AppConfig.defaultKeycloakUrl,
                border: OutlineInputBorder(),
              ),
              onChanged: _onKeycloakChanged,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('realm-field'),
              controller: _realm,
              decoration: const InputDecoration(
                labelText: 'Realm',
                hintText: AppConfig.defaultRealm,
                border: OutlineInputBorder(),
              ),
              onChanged: _onRealmChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('issuer-field'),
              controller: _issuer,
              decoration: const InputDecoration(
                labelText: 'Issuer',
                helperText: 'Se arma como {Keycloak}/realms/{realm}. Puedes cambiarlo.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (_updatingIssuer) return;
                _controller.setIssuer(value);
              },
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('test-connection'),
              onPressed: _controller.connectionChecking ? null : _controller.testConnection,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(_controller.connectionChecking ? 'Comprobando…' : 'Probar conexión'),
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(
                result,
                key: const Key('connection-result'),
                style: TextStyle(
                  color: ok == true ? CubipColors.cyanSoft : const Color(0xFFFF8A80),
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Cliente: ${AppConfig.clientId}',
              style: TextStyle(color: CubipColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Redirect: ${AppConfig.redirectUrl}',
              style: TextStyle(color: CubipColors.muted, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
