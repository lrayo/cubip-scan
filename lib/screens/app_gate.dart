import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'warehouse_screen.dart';

class AppGate extends StatelessWidget {
  const AppGate({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.auth]),
      builder: (context, _) {
        if (!controller.isLoggedIn) {
          return LoginScreen(controller: controller);
        }
        if (controller.selectedWarehouse == null) {
          return WarehouseScreen(controller: controller);
        }
        return HomeShell(controller: controller);
      },
    );
  }
}
