/// Borra del teléfono la foto que deja el plugin `camera` al capturar.
///
/// `takePicture()` escribe la captura en un archivo temporal y NO lo borra nunca. Esa
/// copia es la foto en bruto (con EXIF y ubicación GPS) y quedaría en el teléfono antes
/// de que el rollo se revele. Por eso, en cuanto se leen sus bytes, se borra.
///
/// Cada plataforma lo hace distinto (import condicional, igual que guardar_foto.dart):
///  - teléfono: se borra el archivo temporal.
///  - web: la captura es una URL `blob:` en memoria; se libera.
library;

export 'borrar_captura_movil.dart' if (dart.library.js_interop) 'borrar_captura_web.dart';
