import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/screens/rollos_screen.dart';
import 'package:pik_app/services/auth_service.dart';
import 'package:pik_app/services/mis_rollos.dart';
import 'package:pik_app/services/rollos_service.dart';
import 'package:pik_app/theme.dart';

void main() {
  testWidgets('Cuarto oscuro en lista con tiempo, revelados en cuadrícula con fecha, sin el activo',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 4000); // alto: que se vea todo sin desplazar
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ahora = DateTime.now().toUtc();
    Map<String, Object?> rollo(String titulo, String estado,
            {DateTime? inicio, DateTime? fin, DateTime? cierre}) =>
        {
          'id': titulo, 'titulo': titulo, 'filtro': 'Original', 'capacidad': 12, 'estado': estado,
          'fotosTomadas': 12, 'fotosRestantes': 0, 'horasRevelado': 6,
          'fechaCreacionUtc': '2026-11-20T10:00:00Z',
          'fechaCierreUtc': cierre?.toIso8601String(),
          'fechaInicioReveladoUtc': inicio?.toIso8601String(),
          'fechaFinReveladoUtc': fin?.toIso8601String(),
        };
    final datos = [
      rollo('Tomando', 'Activo'),
      rollo('Esperando', 'EnCola', cierre: ahora),
      rollo('Tarde', 'Revelando', inicio: ahora, fin: ahora.add(const Duration(hours: 5))),
      rollo('Pronto', 'Revelando', inicio: ahora, fin: ahora.add(const Duration(hours: 2, minutes: 5, seconds: 30))),
      // Ya pasó su hora aunque la API aún diga Revelando: va con los revelados.
      rollo('Recién', 'Revelando', inicio: ahora.subtract(const Duration(hours: 3)),
          fin: ahora.subtract(const Duration(minutes: 1))),
      rollo('Viejo', 'Revelado', fin: DateTime.utc(2026, 11, 2, 18)),
    ];
    final api = ApiClient(
      client: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(datos)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );
    final misRollos = MisRollos(RollosService(api));
    addTearDown(misRollos.dispose);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthService(api)),
        ChangeNotifierProvider.value(value: misRollos),
      ],
      child: MaterialApp(theme: temaPik, home: RollosScreen(onVolverACamara: () {})),
    ));
    await tester.runAsync(misRollos.cargar);
    await tester.pump();

    // El activo no aparece (se maneja desde la cámara).
    expect(find.text('TOMANDO'), findsNothing);

    // Cuarto oscuro: el que termina antes primero, luego el otro, al final la cola.
    double y(String texto) => tester.getTopLeft(find.text(texto)).dy;
    expect(y('PRONTO'), lessThan(y('TARDE')));
    expect(y('TARDE'), lessThan(y('ESPERANDO')));
    expect(find.text('2h 05m'), findsOneWidget);
    expect(find.text('FALTAN'), findsNWidgets(2));

    // Revelados (debajo del cuarto oscuro): el más reciente primero, con su fecha.
    expect(y('ESPERANDO'), lessThan(y('RECIÉN')));
    expect(y('RECIÉN'), lessThanOrEqualTo(y('VIEJO')));
    expect(find.text('02 NOV 2026'), findsOneWidget);
    expect(find.text('REVELADO'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox()); // detiene el reloj de la cuenta regresiva
  });
}
