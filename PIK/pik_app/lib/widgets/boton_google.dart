/// Botón "Continuar con Google".
///
/// En web Google solo permite su botón oficial (`renderButton`); en Android/iOS se usa
/// un botón propio que llama a InicioGoogle.iniciar(). Cada plataforma tiene su archivo
/// y Dart elige uno al compilar (import condicional).
library;

export 'boton_google_movil.dart' if (dart.library.js_interop) 'boton_google_web.dart';
