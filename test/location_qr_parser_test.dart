import 'package:cubip_scan/auth/auth_session.dart';
import 'package:cubip_scan/location/location.dart';
import 'package:cubip_scan/location/location_qr_parser.dart';
import 'package:cubip_scan/rfid/demo_rfid_client.dart';
import 'package:cubip_scan/screens/location_screen.dart';
import 'package:cubip_scan/state/app_controller.dart';
import 'package:cubip_scan/theme/cubip_theme.dart';
import 'package:cubip_scan/warehouse/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const sampleLocations = [
    Location(
      id: '11111111-1111-4111-8111-111111111111',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'A-03-02',
      name: 'Zona 1 · Pasillo A01 · Rack R01 · Nivel L01 · A-03-02',
      labelEpc: 'E28011700000020F10C0A302',
    ),
    Location(
      id: '22222222-2222-4222-8222-222222222222',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'A01-01-01',
      name: 'Zona A · Rack 01 · Nivel 01 · A01-01-01',
      labelEpc: 'E28011700000020F10C00012',
    ),
    Location(
      id: '33333333-3333-4333-8333-333333333333',
      warehouseId: FakeWarehouseRepository.bogotaId,
      code: 'MUELLE-1',
      name: 'Muelle 1',
    ),
  ];

  group('extractLocationCodeFromQr', () {
    test('extrae código directo con trim', () {
      expect(extractLocationCodeFromQr('A-03-02'), 'A-03-02');
      expect(extractLocationCodeFromQr('  A01-01-01  '), 'A01-01-01');
    });

    test('extrae último segmento no vacío de payload jerárquico', () {
      expect(
        extractLocationCodeFromQr('WH01:Z1:A01:R01:L01:A-03-02'),
        'A-03-02',
      );
      expect(
        extractLocationCodeFromQr('WH01:Z1::A-03-02:'),
        'A-03-02',
      );
    });

    test('extrae y decodifica URI cubip://loc/', () {
      expect(extractLocationCodeFromQr('cubip://loc/A-03-02'), 'A-03-02');
      expect(
        extractLocationCodeFromQr('cubip://loc/A%2003%2D02/'),
        'A 03-02',
      );
      expect(extractLocationCodeFromQr('CUBIP://LOC/MUELLE-1'), 'MUELLE-1');
    });

    test('extrae código desde JSON con location_code o code', () {
      expect(
        extractLocationCodeFromQr('{"location_code":"A-03-02"}'),
        'A-03-02',
      );
      expect(
        extractLocationCodeFromQr('  {"code": "A01-01-01"}  '),
        'A01-01-01',
      );
    });

    test('retorna null para entradas vacías o inválidas', () {
      expect(extractLocationCodeFromQr(''), isNull);
      expect(extractLocationCodeFromQr('   '), isNull);
      expect(extractLocationCodeFromQr(':::'), isNull);
      expect(extractLocationCodeFromQr('{}'), isNull);
      expect(extractLocationCodeFromQr('{"other":"A-03-02"}'), isNull);
      expect(extractLocationCodeFromQr('{bad json'), isNull);
      expect(extractLocationCodeFromQr('cubip://loc/'), isNull);
      expect(extractLocationCodeFromQr('cubip://other/A-03-02'), isNull);
      expect(extractLocationCodeFromQr('https://example.com/A-03-02'), isNull);
    });
  });

  group('findLocationByQr', () {
    test('encuentra ubicación por los 4 formatos (case-insensitive)', () {
      expect(findLocationByQr('a-03-02', sampleLocations)?.code, 'A-03-02');
      expect(
        findLocationByQr(
          'WH01:Z1:A01:R01:L01:a-03-02',
          sampleLocations,
        )?.code,
        'A-03-02',
      );
      expect(
        findLocationByQr('cubip://loc/A%2D03%2D02', sampleLocations)?.code,
        'A-03-02',
      );
      expect(
        findLocationByQr('{"location_code":"a-03-02"}', sampleLocations)?.code,
        'A-03-02',
      );
      expect(
        findLocationByQr('{"code":"muelle-1"}', sampleLocations)?.code,
        'MUELLE-1',
      );
    });

    test('encuentra ubicación por id o labelEpc (case-insensitive)', () {
      expect(
        findLocationByQr(
          '22222222-2222-4222-8222-222222222222',
          sampleLocations,
        )?.code,
        'A01-01-01',
      );
      expect(
        findLocationByQr(
          'cubip://loc/e28011700000020f10c00012',
          sampleLocations,
        )?.code,
        'A01-01-01',
      );
    });

    test('retorna null cuando no hay coincidencia o payload inválido', () {
      expect(findLocationByQr('NO-EXISTE', sampleLocations), isNull);
      expect(findLocationByQr('', sampleLocations), isNull);
      expect(findLocationByQr('{malformed', sampleLocations), isNull);
      expect(findLocationByQr('A-03-02', const []), isNull);
    });
  });

  group('LocationScreen detección QR', () {
    AppController createController() {
      final controller = AppController(
        auth: MemoryAuthSession(loggedIn: true, demo: true),
        demoClient: DemoRfidClient(),
        platformClient: DemoRfidClient(),
      );
      controller.demoMode = true;
      controller.selectedWarehouse = FakeWarehouseRepository.defaultWarehouses.first;
      controller.locations = sampleLocations;
      return controller;
    }

    Future<void> openLocationScreen(
      WidgetTester tester,
      AppController controller,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CubipTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open-location-screen'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LocationScreen(controller: controller),
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-location-screen')));
      await tester.pumpAndSettle();
    }

    testWidgets('conserva UI existente y muestra coincidencia QR al ingresar payload',
        (tester) async {
      final controller = createController();
      addTearDown(controller.dispose);
      await openLocationScreen(tester, controller);

      expect(find.byKey(const Key('pin-location')), findsOneWidget);
      expect(find.byKey(const Key('location-prefix')), findsOneWidget);
      expect(find.byKey(const Key('qr-location-match')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('location-prefix')),
        'WH01:Z1:A01:R01:L01:A-03-02',
      );
      await tester.pump();

      expect(find.byKey(const Key('qr-location-match')), findsOneWidget);
      expect(
        find.text('Coincidencia QR: A-03-02 — Seleccionar'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('qr-location-match')));
      await tester.pumpAndSettle();

      expect(controller.selectedLocation?.code, 'A-03-02');
      expect(find.byType(LocationScreen), findsNothing);
    });

    testWidgets('al enviar (onSubmitted) un QR con coincidencia selecciona y cierra',
        (tester) async {
      final controller = createController();
      addTearDown(controller.dispose);
      await openLocationScreen(tester, controller);

      await tester.enterText(
        find.byKey(const Key('location-prefix')),
        'cubip://loc/MUELLE-1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.selectedLocation?.code, 'MUELLE-1');
      expect(find.byType(LocationScreen), findsNothing);
    });
  });
}
