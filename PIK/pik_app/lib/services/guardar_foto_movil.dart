import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Guarda la foto en la galería del teléfono y devuelve el mensaje para el usuario.
/// [nombre] va sin extensión: gal la detecta a partir de los bytes.
/// La primera vez, el sistema pide permiso.
Future<String> guardarFoto(Uint8List bytes, String nombre) async {
  try {
    await Gal.putImageBytes(bytes, name: nombre);
    return 'Foto guardada en tu galería.';
  } on GalException catch (e) {
    return switch (e.type) {
      GalExceptionType.permissionDenied =>
        'PIK no tiene permiso para guardar en tu galería. Actívalo en la configuración.',
      GalExceptionType.notEnoughSpace => 'No hay espacio suficiente en el teléfono.',
      _ => 'No se pudo guardar la foto.',
    };
  }
}
