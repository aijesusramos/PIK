import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/fotos/preparar_foto.dart';
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
  final foto = FotoParaSubir(
    id: '3f2a7c1e-9b0d-4c5e-8a1b-0123456789ab',
    rolloId: 'rollo-1',
    original: FotoPreparada(Uint8List.fromList([0xFF, 0xD8, 0x01, 0xFF, 0xD9]), 1920, 1080),
    revelada: Uint8List.fromList([0xFF, 0xD8, 0x02, 0xFF, 0xD9]),
    fechaCaptura: DateTime.utc(2026, 11, 25, 12),
  );

  test('Sube original y revelada en un multipart con los campos que espera la API', () async {
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

    final subida = await FotosService(api).subir(foto);

    expect(enviada.method, 'POST');
    expect(enviada.url.path, '/api/rollos/rollo-1/fotos');
    expect(enviada.headers['Authorization'], 'Bearer mi-token');
    expect(enviada.headers['content-type'], startsWith('multipart/form-data'));

    final cuerpo = latin1.decode(enviada.bodyBytes);
    expect(cuerpo, contains('name="archivo"; filename="original.jpg"'));
    expect(cuerpo, contains('name="revelada"; filename="revelada.jpg"'));
    // Los dos archivos van como image/jpeg (la API lo revisa).
    expect('content-type: image/jpeg'.allMatches(cuerpo.toLowerCase()), hasLength(2));
    // Cada campo lleva sus propios bytes (0x01 = original, 0x02 = revelada).
    // (el paquete http escribe "content-type" antes de "content-disposition" en cada parte).
    expect(cuerpo, contains('filename="original.jpg"\r\n\r\n\xFF\xD8\x01'));
    expect(cuerpo, contains('filename="revelada.jpg"\r\n\r\n\xFF\xD8\x02'));
    expect(cuerpo, contains('name="id"\r\n\r\n3f2a7c1e-9b0d-4c5e-8a1b-0123456789ab'));
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

    final subida = await FotosService(api).subir(foto);
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
      () => FotosService(api).subir(foto),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.mensaje, 'mensaje', contains('ya está cerrado'))),
    );
  });
}
