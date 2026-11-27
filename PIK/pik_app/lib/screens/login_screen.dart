import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../services/auth_service.dart';
import '../services/inicio_google.dart';
import '../theme.dart';
import '../widgets/boton_google.dart';

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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.camera_roll_outlined, size: 64, color: colorAcento),
                  const SizedBox(height: 8),
                  Text('PIK', textAlign: TextAlign.center, style: tema.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Toma fotos como en un rollo: las verás cuando se revelen.',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 40),
                  if (_entrando)
                    const Center(child: CircularProgressIndicator())
                  else if (_listo)
                    // En web es el botón oficial de Google; en móvil, uno propio.
                    BotonGoogle(onPressed: _tocarBoton)
                  else if (_error == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tema.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Si es tu primera vez, se crea tu cuenta con tu correo de Google.',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
