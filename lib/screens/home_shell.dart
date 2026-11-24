import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import '../theme/cubip_theme.dart';
import 'about_screen.dart';
import 'connect_screen.dart';
import 'inventory_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller, this.initialIndex = 0});

  final AppController controller;
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConnectScreen(controller: widget.controller),
      InventoryScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
      AboutScreen(controller: widget.controller),
    ];
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.bluetooth_searching_outlined),
                selectedIcon: Icon(Icons.bluetooth_searching, color: CubipColors.cyanSoft),
                label: 'Conectar',
              ),
              NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: Icon(Icons.qr_code_scanner, color: CubipColors.cyanSoft),
                label: 'Lectura',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune, color: CubipColors.cyanSoft),
                label: 'Ajustes',
              ),
              NavigationDestination(
                icon: Icon(Icons.info_outline),
                selectedIcon: Icon(Icons.info, color: CubipColors.cyanSoft),
                label: 'Acerca de',
              ),
            ],
          ),
        );
      },
    );
  }
}
