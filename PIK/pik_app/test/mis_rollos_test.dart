import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/services/mis_rollos.dart';
import 'package:pik_app/services/rollos_service.dart';

Map<String, dynamic> rolloJson(String id, String titulo, String estado, {int tomadas = 0}) => {
      'id': id,
      'titulo': titulo,
      'filtro': 'Original',
      'capacidad': 6,
      'estado': estado,
      'fotosTomadas': tomadas,
      'fotosRestantes': 6 - tomadas,
      'horasRevelado': 3,
      'fechaCreacionUtc': '2026-11-25T10:00:00Z',
      'fechaCierreUtc': null,
      'fechaInicioReveladoUtc': null,
      'fechaFinReveladoUtc': estado == 'Revelando' ? '2099-01-01T00:00:00Z' : null,
    };

http.Response jsonUtf8(Object cuerpo, [int estado = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Espera a que terminen las peticiones pendientes (la carga inicial de MisRollos).
Future<void> esperar() => Future<void>.delayed(Duration.zero);

void main() {
  test('Carga los rollos y encuentra el activo', () async {
    final api = ApiClient(
      client: MockClient((_) async => jsonUtf8([
            rolloJson('a', 'Playa', 'Activo', tomadas: 2),
            rolloJson('b', 'Rollo 1', 'Revelando', tomadas: 6),
          ])),
    );
    final mis = MisRollos(RollosService(api));
    await esperar();

    expect(mis.cargando, isFalse);
    expect(mis.activo?.titulo, 'Playa');
    expect(mis.enProceso.single.id, 'b');
    expect(mis.revelados, isEmpty);
    mis.dispose();
  });

  test('Crear con título lo manda limpio; sin título no manda el campo', () async {
    final cuerpos = <Map<String, dynamic>>[];
    final api = ApiClient(
      client: MockClient((p) async {
        if (p.method == 'GET') return jsonUtf8(<dynamic>[]);
        final cuerpo = jsonDecode(p.body) as Map<String, dynamic>;
        cuerpos.add(cuerpo);
        return jsonUtf8(rolloJson('n', (cuerpo['titulo'] as String?) ?? 'Rollo 1', 'Activo'), 201);
      }),
    );
    final mis = MisRollos(RollosService(api));
    await esperar();

    await mis.crear(FiltroRollo.original, 6, titulo: '  Cumpleaños  ');
    expect(cuerpos.last['titulo'], 'Cumpleaños');
    expect(mis.activo?.titulo, 'Cumpleaños');

    await mis.crear(FiltroRollo.original, 6, titulo: '   ');
    expect(cuerpos.last.containsKey('titulo'), isFalse, reason: 'la API pone "Rollo N"');
    mis.dispose();
  });

  test('Renombrar y actualizar reemplazan el rollo en la lista y avisan', () async {
    final api = ApiClient(
      client: MockClient((p) async {
        if (p.method == 'PATCH') {
          expect(p.url.path, '/api/rollos/a');
          expect(jsonDecode(p.body), {'titulo': 'Nuevo nombre'});
          return jsonUtf8(rolloJson('a', 'Nuevo nombre', 'Activo', tomadas: 2));
        }
        return jsonUtf8([rolloJson('a', 'Viejo', 'Activo', tomadas: 2)]);
      }),
    );
    final mis = MisRollos(RollosService(api));
    await esperar();

    var avisos = 0;
    mis.addListener(() => avisos++);

    await mis.renombrar(mis.activo!, ' Nuevo nombre ');
    expect(mis.activo?.titulo, 'Nuevo nombre');

    // Después de subir una foto, la cámara actualiza el rollo con la respuesta de la API.
    mis.actualizar(Rollo.fromJson(rolloJson('a', 'Nuevo nombre', 'Activo', tomadas: 3)));
    expect(mis.activo?.fotosTomadas, 3);
    expect(avisos, 2);
    mis.dispose();
  });

  test('Si la carga falla, guarda el mensaje de error', () async {
    final api = ApiClient(client: MockClient((_) async => jsonUtf8({'mensaje': 'Falla'}, 500)));
    final mis = MisRollos(RollosService(api));
    await esperar();

    expect(mis.error, 'Falla');
    expect(mis.rollos, isEmpty);
    mis.dispose();
  });

  test('No falla si una petición termina después de cerrar sesión (dispose)', () async {
    final api = ApiClient(client: MockClient((_) async => jsonUtf8(<dynamic>[])));
    final mis = MisRollos(RollosService(api));
    mis.dispose(); // la carga inicial sigue en curso
    await esperar(); // no debe lanzar "used after being disposed"
  });
}
