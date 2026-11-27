/// Prepara la foto ORIGINAL antes de revelarla y subirla. No cambia los colores:
/// el look lo pone después el motor de revelado (lib/engine/).
///
/// Este archivo no importa Flutter, para poder correr [prepararOriginal] en un isolate.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Foto lista para revelar y subir.
class FotoPreparada {
  const FotoPreparada(this.bytes, this.ancho, this.alto);

  /// JPEG sin metadatos EXIF.
  final Uint8List bytes;
  final int ancho;
  final int alto;
}

/// Lado más largo permitido. Fotos más grandes se reducen: tardan menos en
/// revelarse y subirse, y para el estilo analógico no hace falta más.
const ladoMaximo = 1920;

/// Prepara la foto capturada:
///  1. la decodifica,
///  2. la endereza según su EXIF (los teléfonos guardan la rotación aparte),
///  3. la reduce si es muy grande y
///  4. la vuelve a codificar como JPEG.
///
/// Al recodificar se pierden los metadatos EXIF, incluida la ubicación GPS:
/// así no se sube al servidor dónde se tomó la foto.
FotoPreparada prepararOriginal(Uint8List capturada) {
  var imagen = img.decodeImage(capturada);
  if (imagen == null) {
    throw const FormatException('No se pudo leer la foto capturada.');
  }

  imagen = img.bakeOrientation(imagen);

  if (math.max(imagen.width, imagen.height) > ladoMaximo) {
    imagen = imagen.width >= imagen.height
        ? img.copyResize(imagen, width: ladoMaximo, interpolation: img.Interpolation.average)
        : img.copyResize(imagen, height: ladoMaximo, interpolation: img.Interpolation.average);
  }

  return FotoPreparada(img.encodeJpg(imagen, quality: 90), imagen.width, imagen.height);
}
