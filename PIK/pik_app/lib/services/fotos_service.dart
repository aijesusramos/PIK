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
}
