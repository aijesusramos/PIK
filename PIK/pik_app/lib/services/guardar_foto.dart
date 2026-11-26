/// Guarda una foto revelada en el dispositivo.
///
/// Cada plataforma lo hace distinto, así que hay dos archivos con la misma función
/// `guardarFoto` y Dart elige uno al compilar (import condicional):
///  - web (`dart.library.js_interop` existe): descarga del navegador.
///  - teléfono: se guarda en la galería con el paquete gal.
library;

export 'guardar_foto_movil.dart' if (dart.library.js_interop) 'guardar_foto_web.dart';
