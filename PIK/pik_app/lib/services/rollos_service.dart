import '../api/api_client.dart';
import '../models/modelos.dart';

/// Llamadas a /api/rollos.
class RollosService {
  RollosService(this._api);

  final ApiClient _api;

  Future<List<Rollo>> listar({EstadoRollo? estado}) async {
    final json = await _api.get(
      '/api/rollos',
      query: estado == null ? null : {'estado': estado.api},
    ) as List<dynamic>;
    return json.map((j) => Rollo.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// [titulo] es opcional: si va vacío, la API lo nombra "Rollo N".
  Future<Rollo> crear(FiltroRollo filtro, int capacidad, {String? titulo}) async {
    final limpio = titulo?.trim() ?? '';
    final json = await _api.post('/api/rollos', {
      'filtro': filtro.api,
      'capacidad': capacidad,
      if (limpio.isNotEmpty) 'titulo': limpio,
    }) as Map<String, dynamic>;
    return Rollo.fromJson(json);
  }

  /// Cambia el título (lo único que se puede cambiar de un rollo ya creado).
  Future<Rollo> renombrar(String rolloId, String titulo) async {
    final json = await _api.patch('/api/rollos/$rolloId', {'titulo': titulo.trim()})
        as Map<String, dynamic>;
    return Rollo.fromJson(json);
  }

  Future<Rollo> cerrar(String rolloId) async {
    final json = await _api.post('/api/rollos/$rolloId/cerrar') as Map<String, dynamic>;
    return Rollo.fromJson(json);
  }
}
