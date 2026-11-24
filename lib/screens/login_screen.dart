import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
              children: [
                Center(
                  child: Image.asset(
                    'assets/logo/cubip-logo-apilado-oscuro-512.png',
                    width: 160,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Cubip Scan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CubipTheme.displayFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Inicia sesión con tu usuario de Cubip para enviar lecturas',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CubipColors.secondary, height: 1.4),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  key: const Key('oidc-login'),
                  onPressed: controller.login,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Iniciar sesión'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('demo-login'),
                  onPressed: controller.enterDemo,
                  child: const Text('Continuar en modo demo'),
                ),
                if (controller.statusMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    controller.statusMessage!,
                    style: const TextStyle(color: CubipColors.cyanSoft),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                const Text(
                  'Si tu empresa usa otro servidor, puedes configurarlo más adelante en Ajustes.',
                  style: TextStyle(color: CubipColors.muted, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
