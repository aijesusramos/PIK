import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';

import '../api/api_client.dart';
import '../filtros/filtros.dart';
import '../models/modelos.dart';

/// Llamadas a las rutas de fotos (FotosController en la API).
class FotosService {
  FotosService(this._api);

  final ApiClient _api;

  /// Sube una foto (ya con el filtro aplicado) a un rollo Activo.
  /// [fechaCaptura] se envía en UTC, como espera la API.
  Future<FotoSubida> subir(String rolloId, FotoProcesada foto, DateTime fechaCaptura) async {
    final json = await _api.postArchivo(
      '/api/rollos/$rolloId/fotos',
      campoArchivo: 'archivo',
      bytes: foto.bytes,
      nombreArchivo: 'foto.jpg',
      // La API revisa el Content-Type del archivo: solo acepta image/jpeg o image/png.
      tipo: MediaType('image', 'jpeg'),
      campos: {
        'ancho': '${foto.ancho}',
        'alto': '${foto.alto}',
        'fechaCapturaUtc': fechaCaptura.toUtc().toIso8601String(),
      },
    ) as Map<String, dynamic>;
    return FotoSubida.fromJson(json);
  }

  /// Fotos de un rollo. Antes del revelado la lista viene vacía y bloqueado = true.
  Future<FotosDeRollo> listar(String rolloId) async {
    final json = await _api.get('/api/rollos/$rolloId/fotos') as Map<String, dynamic>;
    return FotosDeRollo.fromJson(json);
  }

  /// Bytes de la imagen. Si el rollo aún no se revela, la API responde 423
  /// y llega como ApiException.
  Future<Uint8List> imagen(FotoInfo foto) => _api.getBytes(foto.urlArchivo);
}

/// Guarda en memoria las imágenes ya descargadas mientras la galería está abierta,
/// para no pedir la misma foto dos veces (cuadrícula → pantalla completa).
///
/// Guarda el *Future* y no los bytes: si dos widgets piden la misma foto a la vez,
/// comparten una sola descarga.
class CacheImagenes {
  CacheImagenes(this._fotos);

  final FotosService _fotos;
  final _imagenes = <String, Future<Uint8List>>{};

  Future<Uint8List> obtener(FotoInfo foto) {
    final existente = _imagenes[foto.id];
    if (existente != null) return existente;

    final descarga = _fotos.imagen(foto);
    _imagenes[foto.id] = descarga;
    // Si falla, se quita de la caché para poder reintentar.
    // Ojo: con llaves y no con "=>", para no devolver el valor de remove().
    descarga.then((_) {}, onError: (_) {
      _imagenes.remove(foto.id);
    });
    return descarga;
  }
}
