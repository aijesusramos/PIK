import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import 'inicio_google.dart';

/// Maneja la sesión: entrar con Google, cerrar sesión y recordar el token entre aperturas.
/// Es un ChangeNotifier: cuando cambia la sesión, la app redibuja la pantalla correcta.
///
/// PIK no maneja contraseñas: la app obtiene un ID token de Google y el backend lo valida
/// con Google y responde con NUESTRO JWT, que es el que se guarda y se usa en la API.
class AuthService extends ChangeNotifier {
  AuthService(this._api, {FlutterSecureStorage? storage, this._google})
      : _storage = storage ?? const FlutterSecureStorage() {
    // Si el token venció, la API responde 401 y se cierra la sesión.
    _api.onNoAutorizado = () {
      if (autenticado) cerrarSesion();
    };
  }

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final InicioGoogle? _google;
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

  /// Cambia el ID token de Google por nuestro JWT. Si es la primera vez, el backend
  /// crea la cuenta (o la vincula a una existente con el mismo correo verificado).
  Future<void> entrarConGoogle(String idToken) async {
    final json = await _api.post('/api/auth/google', {'idToken': idToken})
        as Map<String, dynamic>;
    await _guardarSesion(json);
  }

  Future<void> cerrarSesion() async {
    _api.token = null;
    usuario = null;
    await _storage.delete(key: _claveToken);
    notifyListeners();
    // También en Google, para que la próxima vez se pueda elegir otra cuenta.
    await _google?.cerrar();
  }

  Future<void> _guardarSesion(Map<String, dynamic> json) async {
    final token = json['token'] as String;
    _api.token = token;
    await _storage.write(key: _claveToken, value: token);
    usuario = Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
    notifyListeners();
  }
}
