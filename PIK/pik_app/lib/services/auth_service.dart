import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';

/// Maneja la sesión: registro, login, logout y recordar el token entre aperturas.
/// Es un ChangeNotifier: cuando cambia la sesión, la app redibuja la pantalla correcta.
class AuthService extends ChangeNotifier {
  AuthService(this._api, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    // Si el token venció, la API responde 401 y se cierra la sesión.
    _api.onNoAutorizado = () {
      if (autenticado) cerrarSesion();
    };
  }

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  static const _claveToken = 'pik_token';

  Usuario? usuario;
  bool cargando = true;

  bool get autenticado => usuario != null;

  /// Al abrir la app: si hay un token guardado, lo valida con /api/auth/yo.
  Future<void> iniciar() async {
    try {
      final token = await _storage.read(key: _claveToken);
      if (token != null) {
        _api.token = token;
        final json = await _api.get('/api/auth/yo') as Map<String, dynamic>;
        usuario = Usuario.fromJson(json);
      }
    } on ApiException catch (e) {
      _api.token = null;
      if (e.statusCode == 401) await _storage.delete(key: _claveToken);
    } catch (_) {
      _api.token = null;
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final json = await _api.post('/api/auth/login', {
      'email': email.trim(),
      'password': password,
    }) as Map<String, dynamic>;
    await _guardarSesion(json);
  }

  Future<void> registro(String email, String nombreUsuario, String password) async {
    final json = await _api.post('/api/auth/registro', {
      'email': email.trim(),
      'nombreUsuario': nombreUsuario.trim(),
      'password': password,
    }) as Map<String, dynamic>;
    await _guardarSesion(json);
  }

  Future<void> cerrarSesion() async {
    _api.token = null;
    usuario = null;
    await _storage.delete(key: _claveToken);
    notifyListeners();
  }

  Future<void> _guardarSesion(Map<String, dynamic> json) async {
    final token = json['token'] as String;
    _api.token = token;
    await _storage.write(key: _claveToken, value: token);
    usuario = Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
    notifyListeners();
  }
}
