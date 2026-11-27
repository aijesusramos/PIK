import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:path_provider/path_provider.dart';

/// Borra el archivo temporal de una captura. Nunca lanza: si falla, la limpieza
/// al abrir la cámara ([limpiarCapturasViejas]) lo vuelve a intentar.
Future<void> borrarCaptura(XFile captura) async {
  try {
    final archivo = File(captura.path);
    if (await archivo.exists()) await archivo.delete();
  } catch (_) {}
}

/// Borra capturas que hayan quedado de antes (por ejemplo, si la app se cerró entre
/// la captura y el borrado). Solo toca los archivos con el nombre que usa el plugin:
///  - Android: `<caché>/CAP<número>.jpg`  (camera_android_camerax: getCacheDir)
///  - iOS:     `<tmp>/camera/pictures/CAP_<uuid>.<ext>`  (camera_avfoundation)
/// Devuelve cuántos archivos borró.
///
/// [temporal] es para las pruebas; por defecto es la carpeta temporal de la app, que en
/// Android es getCacheDir() y en iOS tmp (las mismas que usa el plugin).
Future<int> limpiarCapturasViejas({Directory? temporal}) async {
  try {
    final base = temporal ?? await getTemporaryDirectory();
    final android = RegExp(r'^CAP\d*\.jpg$');
    final ios = RegExp(r'^CAP_[0-9A-Fa-f-]+\.\w+$');

    var borrados = 0;
    Future<void> limpiar(Directory carpeta, RegExp patron) async {
      if (!await carpeta.exists()) return;
      await for (final e in carpeta.list(followLinks: false)) {
        final nombre = e.uri.pathSegments.last;
        if (e is File && patron.hasMatch(nombre)) {
          try {
            await e.delete();
            borrados++;
          } catch (_) {}
        }
      }
    }

    await limpiar(base, android);
    await limpiar(Directory('${base.path}${Platform.pathSeparator}camera'
        '${Platform.pathSeparator}pictures'), ios);
    return borrados;
  } catch (_) {
    return 0; // sin carpeta temporal (p. ej. en pruebas sin plugin): nada que limpiar
  }
}
