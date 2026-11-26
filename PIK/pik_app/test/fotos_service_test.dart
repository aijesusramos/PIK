import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/filtros/filtros.dart';
import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/services/fotos_service.dart';

/// JSON de un rollo como lo devuelve la API.
Map<String, dynamic> rolloJson({required String estado, required int tomadas}) => {
      'id': 'rollo-1',
      'titulo': 'Rollo 1',
      'filtro': 'RedBlue',
      'capacidad': 6,
      'estado': estado,
      'fotosTomadas': tomadas,
      'fotosRestantes': 6 - tomadas,
      'horasRevelado': 3,
      'fechaCreacionUtc': '2026-11-25T10:00:00Z',
      'fechaCierreUtc': null,
      'fechaInicioReveladoUtc': null,
      'fechaFinReveladoUtc': null,
    };

void main() {
  final foto = FotoProcesada(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]), 1920, 1080);

  test('Sube la foto como multipart con los campos que espera la API', () async {
    late http.Request enviada;
    final cliente = MockClient((peticion) async {
      enviada = peticion;
      return http.Response(
        jsonEncode({
          'fotoId': 'foto-1',
          'numeroEnRollo': 1,
          'rollo': rolloJson(estado: 'Activo', tomadas: 1),
        }),
        201,
      );
    });
    final api = ApiClient(client: cliente)..token = 'mi-token';

    final subida = await FotosService(api).subir('rollo-1', foto, DateTime.utc(2026, 11, 25, 12));

    expect(enviada.method, 'POST');
    expect(enviada.url.path, '/api/rollos/rollo-1/fotos');
    expect(enviada.headers['Authorization'], 'Bearer mi-token');
    expect(enviada.headers['content-type'], startsWith('multipart/form-data'));

    final cuerpo = latin1.decode(enviada.bodyBytes);
    expect(cuerpo, contains('name="archivo"; filename="foto.jpg"'));
    expect(cuerpo.toLowerCase(), contains('content-type: image/jpeg'));
    expect(cuerpo, contains('name="ancho"\r\n\r\n1920'));
    expect(cuerpo, contains('name="alto"\r\n\r\n1080'));
    expect(cuerpo, contains('2026-11-25T12:00:00.000Z'));

    expect(subida.numeroEnRollo, 1);
    expect(subida.rollo.fotosTomadas, 1);
  });

  test('Al subir la última foto, el rollo vuelve cerrado', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'fotoId': 'foto-6',
              'numeroEnRollo': 6,
              'rollo': rolloJson(estado: 'Revelando', tomadas: 6),
            }),
            201,
          )),
    );

    final subida = await FotosService(api).subir('rollo-1', foto, DateTime.now());
    expect(subida.rollo.estado, EstadoRollo.revelando);
  });

  test('Un 409 de la API llega como ApiException con su mensaje', () async {
    final api = ApiClient(
      // La API responde en UTF-8 (http.Response con String usaría Latin-1 y la "á" se rompería).
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'mensaje': 'Este rollo ya está cerrado. No se pueden agregar más fotos.'})),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );

    expect(
      () => FotosService(api).subir('rollo-1', foto, DateTime.now()),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.mensaje, 'mensaje', contains('ya está cerrado'))),
    );
  });
}
