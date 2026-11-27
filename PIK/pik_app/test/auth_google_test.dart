import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pik_app/api/api_client.dart';
import 'package:pik_app/services/auth_service.dart';

http.Response jsonUtf8(Object cuerpo, [int estado = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('entrarConGoogle manda el ID token de Google y guarda NUESTRO JWT', () async {
    late http.Request enviada;
    final api = ApiClient(
      client: MockClient((p) async {
        enviada = p;
        return jsonUtf8({
          'token': 'jwt-de-pik',
          'expiraUtc': '2026-11-28T00:00:00Z',
          'usuario': {'id': 'u1', 'email': 'ana@gmail.com', 'nombreUsuario': 'ana'},
        });
      }),
    );
    final auth = AuthService(api);

    await auth.entrarConGoogle('id-token-de-google');

    expect(enviada.method, 'POST');
    expect(enviada.url.path, '/api/auth/google');
    expect(jsonDecode(enviada.body), {'idToken': 'id-token-de-google'});
    // El token de Google NO se guarda ni se usa en la API: se usa el JWT de PIK.
    expect(api.token, 'jwt-de-pik');
    expect(await const FlutterSecureStorage().read(key: 'pik_token'), 'jwt-de-pik');
    expect(auth.usuario?.nombreUsuario, 'ana');
  });

  test('Si el backend rechaza la cuenta, no queda sesión y llega el mensaje', () async {
    final api = ApiClient(
      client: MockClient((_) async => jsonUtf8(
          {'mensaje': 'Ese correo ya tiene una cuenta en PIK y Google no lo ha verificado.'}, 409)),
    );
    final auth = AuthService(api);

    await expectLater(
      auth.entrarConGoogle('token'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
    expect(auth.autenticado, isFalse);
    expect(api.token, isNull);
  });

  test('Cerrar sesión borra el JWT guardado', () async {
    final api = ApiClient(
      client: MockClient((_) async => jsonUtf8({
            'token': 'jwt',
            'expiraUtc': '2026-11-28T00:00:00Z',
            'usuario': {'id': 'u1', 'email': 'a@b.com', 'nombreUsuario': 'abc'},
          })),
    );
    final auth = AuthService(api);
    await auth.entrarConGoogle('token');

    await auth.cerrarSesion();

    expect(auth.autenticado, isFalse);
    expect(api.token, isNull);
    expect(await const FlutterSecureStorage().read(key: 'pik_token'), isNull);
  });
}
