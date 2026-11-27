import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Obtiene el ID token de Google. Envuelve al paquete google_sign_in (versión 7).
///
/// Cómo funciona en cada plataforma:
///  - Android/iOS: [iniciar] abre el selector de cuentas de Google.
///  - Web: Google NO permite un botón propio; hay que mostrar su botón oficial
///    (ver widgets/boton_google.dart) y él inicia el flujo.
/// En los dos casos el resultado llega por [idTokens].
class InicioGoogle {
  Future<void>? _inicializado;

  /// Falta el Client ID: la pantalla de login lo dice en lugar de fallar en silencio.
  static bool get configurado => Config.googleClientIdWeb.isNotEmpty;

  /// El paquete exige llamar a initialize una sola vez antes de cualquier otra cosa.
  Future<void> inicializar() => _inicializado ??= GoogleSignIn.instance.initialize(
        // Web: el botón usa el Client ID web. iOS: necesita su propio Client ID.
        clientId: kIsWeb
            ? Config.googleClientIdWeb
            : (defaultTargetPlatform == TargetPlatform.iOS && Config.googleClientIdIos.isNotEmpty
                ? Config.googleClientIdIos
                : null),
        // Android/iOS: el ID token se emite para el Client ID web (lo que valida el backend).
        serverClientId: kIsWeb ? null : Config.googleClientIdWeb,
      );

  /// Cada vez que el usuario inicia sesión con Google, llega aquí su ID token.
  /// Los errores (por ejemplo, si cancela) llegan como errores del Stream.
  Stream<String> get idTokens => GoogleSignIn.instance.authenticationEvents
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .map((e) => (e as GoogleSignInAuthenticationEventSignIn).user.authentication.idToken)
      .where((t) => t != null)
      .cast<String>();

  /// true en Android/iOS (botón propio); false en web (botón oficial de Google).
  bool get permiteBotonPropio => GoogleSignIn.instance.supportsAuthenticate();

  /// Android/iOS: abre el selector de cuentas. El token llega por [idTokens].
  Future<void> iniciar() async {
    await GoogleSignIn.instance.authenticate();
  }

  /// Al cerrar sesión en PIK también se cierra en Google, para poder elegir otra cuenta.
  Future<void> cerrar() async {
    try {
      await inicializar();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Si Google no responde, la sesión de PIK se cierra igual.
    }
  }

  /// ¿El usuario solo canceló (cerró el selector)? Entonces no es un error que mostrar.
  static bool esCancelacion(Object error) =>
      error is GoogleSignInException &&
      (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted);
}
