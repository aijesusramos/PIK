import 'dart:async';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/inicio_google.dart';
import '../theme.dart';
import '../widgets/boton_google.dart';
import '../widgets/cuerpo_camara.dart';
import '../widgets/tarjeta_rollo.dart';

/// Inicio de sesión (y registro) con Google. No hay contraseñas en PIK.
///
///   botón de Google → ID token de Google → POST /api/auth/google → nuestro JWT
///
/// Si es la primera vez, el backend crea la cuenta: no hace falta una pantalla de registro.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final InicioGoogle _google;
  StreamSubscription<String>? _suscripcion;

  /// Google ya está listo (en web, el botón oficial solo se puede dibujar después).
  bool _listo = false;
  bool _entrando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _google = context.read<InicioGoogle>();
    _prepararGoogle();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  Future<void> _prepararGoogle() async {
    if (!InicioGoogle.configurado) {
      setState(() => _error = 'Falta configurar el Client ID de Google '
          '(GOOGLE_CLIENT_ID_WEB en lib/config.dart).');
      return;
    }
    try {
      await _google.inicializar();
      // El ID token llega por aquí, tanto del botón propio (móvil) como del oficial (web).
      _suscripcion = _google.idTokens.listen(_entrar, onError: _errorDeGoogle);
      if (mounted) setState(() => _listo = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo iniciar Google: $e');
    }
  }

  Future<void> _tocarBoton() async {
    setState(() => _error = null);
    try {
      await _google.iniciar();
    } catch (_) {
      // Los errores de Google también llegan por el Stream (_errorDeGoogle): se manejan ahí.
    }
  }

  void _errorDeGoogle(Object error) {
    if (!mounted || InicioGoogle.esCancelacion(error)) return;
    setState(() => _error = 'No se pudo iniciar sesión con Google.');
  }

  Future<void> _entrar(String idToken) async {
    if (_entrando) return;
    setState(() {
      _entrando = true;
      _error = null;
    });
    try {
      // Si funciona, AuthService avisa y main.dart muestra la cámara (InicioScreen).
      await context.read<AuthService>().entrarConGoogle(idToken);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
      await _google.cerrar(); // para poder intentar con otra cuenta
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // Mismo cuerpo metálico y tipografía que la cámara y "Mis rollos".
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colorMetal,
        body: CuerpoMetalico(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: IconoRollo(filtro: FiltroRollo.original, tamano: 150)),
                      const Center(child: TextoGrabado('PIK', tamano: 44)),
                      const SizedBox(height: 10),
                      const Text(
                        'Toma fotos como en un rollo:\nlas verás cuando se revelen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorGrafito, fontSize: 15, height: 1.4),
                      ),
                      const SizedBox(height: 32),
                      // El inicio de sesión va en un panel hundido, como el contador de la cámara.
                      PanelHundido(
                        radio: 16,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'ENTRA CON TU CUENTA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: fuenteRotulos,
                                fontWeight: FontWeight.w700,
                                fontSize: 10.5,
                                letterSpacing: 1.6,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_entrando)
                              const Center(child: CircularProgressIndicator())
                            else if (_listo)
                              // En web es el botón oficial de Google; en móvil, uno propio.
                              Center(child: BotonGoogle(onPressed: _tocarBoton))
                            else if (_error == null)
                              const Center(child: CircularProgressIndicator()),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: tema.colorScheme.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Si es tu primera vez, se crea tu cuenta con tu correo de Google.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF55585C), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
