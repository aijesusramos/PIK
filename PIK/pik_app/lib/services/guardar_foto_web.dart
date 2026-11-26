import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// En el navegador: crea un enlace temporal a los bytes y le hace clic, como si
/// el usuario descargara un archivo. Devuelve el mensaje para el usuario.
Future<String> guardarFoto(Uint8List bytes, String nombre) async {
  final archivo = '$nombre.jpg';
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/jpeg'));
  final url = web.URL.createObjectURL(blob);

  final enlace = web.HTMLAnchorElement()
    ..href = url
    ..download = archivo;
  web.document.body?.append(enlace);
  enlace.click();
  enlace.remove();

  // Se libera la memoria del blob cuando el navegador ya empezó la descarga.
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
  return 'Descargando $archivo';
}
