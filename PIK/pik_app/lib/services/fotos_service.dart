import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';

import '../api/api_client.dart';
import '../fotos/preparar_foto.dart';
import '../models/modelos.dart';

/// Una foto tomada y revelada, lista para subir (o para reintentar si falló la red).
class FotoParaSubir {
  const FotoParaSubir({
    required this.id,
    required this.rolloId,
    required this.original,
    required this.revelada,
    required this.fechaCaptura,
  });

  /// Generado por la app (nuevoIdFoto). Es la semilla del grano y hace que
  /// reintentar la subida no duplique la foto.
  final String id;
  final String rolloId;
  final FotoPreparada original;

  /// JPEG revelado por PikEngine con el filtro del rollo.
  final Uint8List revelada;
  final DateTime fechaCaptura;
}

/// Llamadas a las rutas de fotos (FotosController en la API).
class FotosService {
  FotosService(this._api);

  final ApiClient _api;

  /// Sube la original y la revelada a un rollo Activo, en una sola petición.
  /// Si ya se había subido (mismo id), la API responde 200 con la misma foto.
  Future<FotoSubida> subir(FotoParaSubir foto) async {
    // La API revisa el Content-Type de cada archivo: solo acepta image/jpeg o image/png.
    final jpeg = MediaType('image', 'jpeg');
    final json = await _api.postArchivos(
      '/api/rollos/${foto.rolloId}/fotos',
      archivos: [
        ArchivoSubida('archivo', foto.original.bytes, 'original.jpg', jpeg),
        ArchivoSubida('revelada', foto.revelada, 'revelada.jpg', jpeg),
      ],
      campos: {
        'id': foto.id,
        'ancho': '${foto.original.ancho}',
        'alto': '${foto.original.alto}',
        // UTC, como espera la API.
        'fechaCapturaUtc': foto.fechaCaptura.toUtc().toIso8601String(),
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
