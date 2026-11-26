import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/main.dart';
import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/services/auth_service.dart';
import 'package:pik_app/services/rollos_service.dart';

void main() {
  test('Rollo.fromJson lee el JSON de la API (enums como texto, fechas UTC)', () {
    final rollo = Rollo.fromJson({
      'id': '3f2a7c1e-0000-0000-0000-000000000001',
      'titulo': 'Vacaciones',
      'filtro': 'BlancoNegro',
      'capacidad': 12,
      'estado': 'Revelando',
      'fotosTomadas': 5,
      'fotosRestantes': 7,
      'horasRevelado': 6,
      'fechaCreacionUtc': '2026-11-25T10:00:00Z',
      'fechaCierreUtc': '2026-11-25T11:00:00Z',
      'fechaInicioReveladoUtc': '2026-11-25T11:00:00Z',
      'fechaFinReveladoUtc': '2026-11-25T17:00:00Z',
      // Campos que la app no usa no deben romper el parseo.
      'otroCampo': true,
    });

    expect(rollo.titulo, 'Vacaciones');
    expect(rollo.filtro, FiltroRollo.blancoNegro);
    expect(rollo.estado, EstadoRollo.revelando);
    expect(rollo.capacidad, 12);
    expect(rollo.fechaFinRevelado!.isUtc, isTrue);
    expect(rollo.fechaCierre, isNotNull);
  });

  testWidgets('Sin sesión guardada, la app muestra el login', (tester) async {
    // Almacenamiento seguro simulado y vacío: no hay token guardado.
    FlutterSecureStorage.setMockInitialValues({});

    final api = ApiClient();
    final auth = AuthService(api);
    await auth.iniciar();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<RollosService>(create: (_) => RollosService(api)),
        ],
        child: const PikApp(),
      ),
    );

    expect(find.text('PIK'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
