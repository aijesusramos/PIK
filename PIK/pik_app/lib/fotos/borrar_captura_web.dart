import 'package:camera/camera.dart' show XFile;
import 'package:web/web.dart' as web;

/// En web la captura no es un archivo: es una URL `blob:` que apunta a la foto en la
/// memoria del navegador. El plugin nunca la libera; aquí se libera en cuanto se leen
/// sus bytes.
Future<void> borrarCaptura(XFile captura) async {
  try {
    if (captura.path.startsWith('blob:')) web.URL.revokeObjectURL(captura.path);
  } catch (_) {}
}

/// En web no quedan archivos en disco: no hay nada que limpiar.
Future<int> limpiarCapturasViejas() async => 0;
