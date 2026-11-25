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

  Future<Rollo> crear(FiltroRollo filtro, int capacidad) async {
    final json = await _api.post('/api/rollos', {
      'filtro': filtro.api,
      'capacidad': capacidad,
    }) as Map<String, dynamic>;
    return Rollo.fromJson(json);
  }

  Future<Rollo> cerrar(String rolloId) async {
    final json = await _api.post('/api/rollos/$rolloId/cerrar') as Map<String, dynamic>;
    return Rollo.fromJson(json);
  }
}
