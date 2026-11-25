import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';

/// Error que devuelve la API (o un problema de conexión, con statusCode 0).
class ApiException implements Exception {
  ApiException(this.statusCode, this.mensaje);

  final int statusCode;
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP de PIK: agrega el JWT a cada petición y convierte
/// las respuestas de error en [ApiException] con el mensaje de la API.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// JWT de la sesión actual. Lo asigna AuthService.
  String? token;

  /// Se llama cuando la API responde 401 con un token puesto (token vencido).
  void Function()? onNoAutorizado;

  Future<dynamic> get(String ruta, {Map<String, String>? query}) async {
    final respuesta = await _enviar(
      () => _client.get(_uri(ruta, query), headers: _headers(json: false)),
    );
    return _procesar(respuesta);
  }

  Future<dynamic> post(String ruta, [Object? cuerpo]) async {
    final respuesta = await _enviar(
      () => _client.post(
        _uri(ruta),
        headers: _headers(),
        body: cuerpo == null ? null : jsonEncode(cuerpo),
      ),
    );
    return _procesar(respuesta);
  }

  /// Sube un archivo con multipart/form-data (como un formulario HTML con <input type=file>).
  /// [campos] son los demás valores del formulario. Las fotos pueden tardar más, por eso
  /// el tiempo de espera es mayor que en las demás peticiones.
  Future<dynamic> postArchivo(
    String ruta, {
    required String campoArchivo,
    required List<int> bytes,
    required String nombreArchivo,
    required MediaType tipo,
    Map<String, String> campos = const {},
  }) async {
    final respuesta = await _enviar(
      () async {
        // Un MultipartRequest solo se puede enviar una vez: se crea uno nuevo en cada intento.
        final peticion = http.MultipartRequest('POST', _uri(ruta))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(campos)
          ..files.add(http.MultipartFile.fromBytes(
            campoArchivo,
            bytes,
            filename: nombreArchivo,
            contentType: tipo,
          ));
        return http.Response.fromStream(await _client.send(peticion));
      },
      limite: const Duration(seconds: 60),
    );
    return _procesar(respuesta);
  }

  Uri _uri(String ruta, [Map<String, String>? query]) {
    final uri = Uri.parse('${Config.apiUrl}$ruta');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _enviar(
    Future<http.Response> Function() peticion, {
    Duration limite = const Duration(seconds: 20),
  }) async {
    try {
      return await peticion().timeout(limite);
    } on TimeoutException {
      throw ApiException(0, 'El servidor tardó demasiado en responder.');
    } catch (_) {
      throw ApiException(
        0,
        'No se pudo conectar con el servidor. ¿Está corriendo la API en ${Config.apiUrl}?',
      );
    }
  }

  dynamic _procesar(http.Response r) {
    dynamic cuerpo;
    if (r.bodyBytes.isNotEmpty) {
      try {
        cuerpo = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        cuerpo = null;
      }
    }

    if (r.statusCode >= 200 && r.statusCode < 300) return cuerpo;

    if (r.statusCode == 401 && token != null) onNoAutorizado?.call();

    throw ApiException(r.statusCode, _mensajeDeError(r.statusCode, cuerpo));
  }

  String _mensajeDeError(int statusCode, dynamic cuerpo) {
    if (cuerpo is Map) {
      // Errores de PIK: { "mensaje": "..." }
      if (cuerpo['mensaje'] is String) return cuerpo['mensaje'] as String;

      // Errores de validación de ASP.NET: { "errors": { "Password": ["..."] } }
      final errores = cuerpo['errors'];
      if (errores is Map && errores.isNotEmpty) {
        final primero = errores.values.first;
        if (primero is List && primero.isNotEmpty) return primero.first.toString();
      }
      if (cuerpo['title'] is String) return cuerpo['title'] as String;
    }

    return switch (statusCode) {
      400 => 'Los datos enviados no son válidos.',
      401 => 'Tu sesión expiró. Inicia sesión de nuevo.',
      403 => 'No tienes permiso para hacer esto.',
      404 => 'No se encontró lo que buscas.',
      409 => 'La operación no está permitida en este momento.',
      423 => 'Todavía se está revelando.',
      _ => 'Ocurrió un error en el servidor ($statusCode).',
    };
  }
}
