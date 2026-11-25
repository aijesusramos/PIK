/// Filtros de los rollos.
///
/// Cada filtro es una **matriz de color 4×5** (el mismo formato que usa Flutter en
/// `ColorFilter.matrix`). Para cada píxel:
///
///     R' = m[0]·R  + m[1]·G  + m[2]·B  + m[3]·A  + m[4]
///     G' = m[5]·R  + m[6]·G  + m[7]·B  + m[8]·A  + m[9]
///     B' = m[10]·R + m[11]·G + m[12]·B + m[13]·A + m[14]
///     A' = m[15]·R + m[16]·G + m[17]·B + m[18]·A + m[19]
///
/// con valores de 0 a 255. La misma matriz se usa en dos lugares:
///  - en la vista previa de la cámara (`ColorFiltered`, lo hace la GPU), y
///  - en la foto final antes de subirla ([procesarFoto]),
/// para que lo que se ve en el visor sea lo que se guarda.
///
/// Este archivo no importa Flutter, para poder correr [procesarFoto] en un isolate.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/modelos.dart';

// Peso de cada canal en el brillo percibido (el ojo es más sensible al verde).
const _r = 0.299, _g = 0.587, _b = 0.114;

/// Blanco y negro con un poco más de contraste, como película B&W.
const _contrasteBN = 1.15;
const _offsetBN = 128 * (1 - _contrasteBN);

const List<double> _matrizBlancoNegro = [
  _r * _contrasteBN, _g * _contrasteBN, _b * _contrasteBN, 0, _offsetBN,
  _r * _contrasteBN, _g * _contrasteBN, _b * _contrasteBN, 0, _offsetBN,
  _r * _contrasteBN, _g * _contrasteBN, _b * _contrasteBN, 0, _offsetBN,
  0, 0, 0, 1, 0,
];

/// "Duotono" rojo y azul: las sombras se vuelven azules y las luces, rojas;
/// los medios tonos quedan morados. El verde casi desaparece.
///   negro  (L=0)   → (10, 0, 204)   azul
///   gris   (L=128) → (151, 32, 127) morado
///   blanco (L=255) → (255, 64, 51)  rojo
const List<double> _matrizRedBlue = [
  _r * 1.1, _g * 1.1, _b * 1.1, 0, 10,
  _r * 0.25, _g * 0.25, _b * 0.25, 0, 0,
  _r * -0.6, _g * -0.6, _b * -0.6, 0, 204,
  0, 0, 0, 1, 0,
];

/// Matriz del filtro, o `null` si el filtro no cambia los colores (Original).
List<double>? matrizDeFiltro(FiltroRollo filtro) => switch (filtro) {
      FiltroRollo.original => null,
      FiltroRollo.blancoNegro => _matrizBlancoNegro,
      FiltroRollo.redBlue => _matrizRedBlue,
    };

/// Foto lista para subir.
class FotoProcesada {
  const FotoProcesada(this.bytes, this.ancho, this.alto);

  /// JPEG final, ya con el filtro aplicado.
  final Uint8List bytes;
  final int ancho;
  final int alto;
}

/// Lado más largo permitido. Fotos más grandes se reducen: tardan menos en
/// procesarse y subirse, y para el estilo analógico no hace falta más.
const ladoMaximo = 1920;

/// Prepara la foto capturada para subirla:
///  1. la decodifica,
///  2. la endereza según su EXIF (los teléfonos guardan la rotación aparte),
///  3. la reduce si es muy grande,
///  4. le aplica el filtro del rollo y
///  5. la vuelve a codificar como JPEG.
///
/// Al recodificar se pierden los metadatos EXIF, incluida la ubicación GPS:
/// así no se sube al servidor dónde se tomó la foto.
///
/// Recibe un record para poder usarse con `compute` (que solo acepta un argumento).
FotoProcesada procesarFoto((Uint8List, FiltroRollo) datos) {
  final (original, filtro) = datos;

  var imagen = img.decodeImage(original);
  if (imagen == null) {
    throw const FormatException('No se pudo leer la foto capturada.');
  }

  imagen = img.bakeOrientation(imagen);

  if (math.max(imagen.width, imagen.height) > ladoMaximo) {
    imagen = imagen.width >= imagen.height
        ? img.copyResize(imagen, width: ladoMaximo, interpolation: img.Interpolation.average)
        : img.copyResize(imagen, height: ladoMaximo, interpolation: img.Interpolation.average);
  }

  // Trabajamos con 3 canales de 8 bits (RGB), el formato normal de un JPEG.
  if (imagen.format != img.Format.uint8 || imagen.numChannels != 3) {
    imagen = imagen.convert(format: img.Format.uint8, numChannels: 3);
  }

  final matriz = matrizDeFiltro(filtro);
  if (matriz != null) aplicarMatriz(imagen.buffer.asUint8List(), matriz);

  return FotoProcesada(
    img.encodeJpg(imagen, quality: 90),
    imagen.width,
    imagen.height,
  );
}

/// Aplica la matriz a una lista de píxeles RGB (3 bytes por píxel), modificándola.
///
/// Se trabaja directo sobre los bytes (y no píxel por píxel con objetos) porque es
/// mucho más rápido: una foto de 1920×1080 tiene más de 2 millones de píxeles.
void aplicarMatriz(Uint8List rgb, List<double> m) {
  for (var i = 0; i + 2 < rgb.length; i += 3) {
    final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    // La A (opacidad) de un JPEG siempre es 255, por eso se suma m[3]*255.
    rgb[i] = _limitar(m[0] * r + m[1] * g + m[2] * b + m[3] * 255 + m[4]);
    rgb[i + 1] = _limitar(m[5] * r + m[6] * g + m[7] * b + m[8] * 255 + m[9]);
    rgb[i + 2] = _limitar(m[10] * r + m[11] * g + m[12] * b + m[13] * 255 + m[14]);
  }
}

/// Recorta el valor a 0..255. Importante: si se guarda 300 en un Uint8List
/// no se queda en 255, "da la vuelta" y queda 44.
int _limitar(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
