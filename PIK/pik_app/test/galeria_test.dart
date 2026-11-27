import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/services/fotos_service.dart';

Map<String, dynamic> rolloJson(String estado) => {
      'id': 'rollo-1',
      'titulo': 'Rollo 1',
      'filtro': 'BlancoNegro',
      'capacidad': 6,
      'estado': estado,
      'fotosTomadas': 2,
      'fotosRestantes': 4,
      'horasRevelado': 3,
      'fechaCreacionUtc': '2026-11-25T10:00:00Z',
      'fechaCierreUtc': '2026-11-25T10:30:00Z',
      'fechaInicioReveladoUtc': '2026-11-25T10:30:00Z',
      'fechaFinReveladoUtc': '2026-11-25T13:30:00Z',
    };

Map<String, dynamic> fotoJson(int n) => {
      'id': 'foto-$n',
      'numeroEnRollo': n,
      'ancho': 1920,
      'alto': 1080,
      'tamanoBytes': 123456,
      'fechaCapturaUtc': '2026-11-25T10:1$n:00Z',
      'urlArchivo': '/api/fotos/foto-$n/archivo',
      'urlOriginal': '/api/fotos/foto-$n/archivo?version=original',
    };

/// Respuesta JSON en UTF-8, como la de la API.
http.Response jsonUtf8(Object cuerpo, int estado) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('Modelos', () {
    test('FotosDeRollo revelado trae las fotos', () {
      final datos = FotosDeRollo.fromJson({
        'rollo': rolloJson('Revelado'),
        'bloqueado': false,
        'segundosRestantes': null,
        'fotos': [fotoJson(1), fotoJson(2)],
      });
      expect(datos.bloqueado, isFalse);
      expect(datos.fotos, hasLength(2));
      expect(datos.fotos[1].urlArchivo, '/api/fotos/foto-2/archivo');
      expect(datos.fotos[1].urlOriginal, '/api/fotos/foto-2/archivo?version=original');
      expect(datos.fotos[0].nombreArchivo, 'pik_01');
    });

    test('FotosDeRollo bloqueado: lista vacía y segundos restantes', () {
      final datos = FotosDeRollo.fromJson({
        'rollo': rolloJson('Revelando'),
        'bloqueado': true,
        'segundosRestantes': 95,
        'fotos': <dynamic>[],
      });
      expect(datos.bloqueado, isTrue);
      expect(datos.segundosRestantes, 95);
      expect(datos.fotos, isEmpty);
    });
  });

  group('Descarga de imágenes', () {
    final foto = FotoInfo.fromJson(fotoJson(1));

    test('Envía el JWT y devuelve los bytes', () async {
      late http.Request enviada;
      final api = ApiClient(
        client: MockClient((p) async {
          enviada = p;
          return http.Response.bytes([0xFF, 0xD8, 0xFF, 0xD9], 200,
              headers: {'content-type': 'image/jpeg'});
        }),
      )..token = 'mi-token';

      final bytes = await FotosService(api).imagen(foto);

      expect(enviada.url.path, '/api/fotos/foto-1/archivo');
      expect(enviada.headers['Authorization'], 'Bearer mi-token');
      expect(bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('Un 423 llega como ApiException con el mensaje de la API', () async {
      final api = ApiClient(
        client: MockClient((_) async => jsonUtf8({'mensaje': 'Esta foto aún se está revelando.'}, 423)),
      );

      expect(
        () => FotosService(api).imagen(foto),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 423)
            .having((e) => e.mensaje, 'mensaje', 'Esta foto aún se está revelando.')),
      );
    });
  });

  group('CacheImagenes', () {
    final foto = FotoInfo.fromJson(fotoJson(1));

    test('Descarga cada foto una sola vez', () async {
      var peticiones = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          peticiones++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final cache = CacheImagenes(FotosService(api));

      // Dos widgets la piden a la vez y luego otro más tarde.
      await Future.wait([cache.obtener(foto), cache.obtener(foto)]);
      final bytes = await cache.obtener(foto);

      expect(peticiones, 1);
      expect(bytes, Uint8List.fromList([1, 2, 3]));
    });

    test('Si la descarga falla, se puede reintentar', () async {
      var peticiones = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          peticiones++;
          return peticiones == 1
              ? jsonUtf8({'mensaje': 'Error'}, 500)
              : http.Response.bytes([9], 200);
        }),
      );
      final cache = CacheImagenes(FotosService(api));

      await expectLater(cache.obtener(foto), throwsA(isA<ApiException>()));
      expect(await cache.obtener(foto), [9]);
      expect(peticiones, 2);
    });
  });
}
