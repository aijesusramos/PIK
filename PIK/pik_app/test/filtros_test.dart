import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pik_app/filtros/filtros.dart';
import 'package:pik_app/models/modelos.dart';

/// Un píxel RGB pasado por la matriz del filtro.
List<int> filtrar(FiltroRollo filtro, int r, int g, int b) {
  final rgb = Uint8List.fromList([r, g, b]);
  aplicarMatriz(rgb, matrizDeFiltro(filtro)!);
  return rgb;
}

/// JPEG de prueba de un solo color.
Uint8List jpegDeColor(int ancho, int alto, int r, int g, int b) {
  final imagen = img.Image(width: ancho, height: alto);
  img.fill(imagen, color: img.ColorRgb8(r, g, b));
  return img.encodeJpg(imagen, quality: 100);
}

void main() {
  group('Matrices de filtro', () {
    test('Original no tiene matriz (no cambia los colores)', () {
      expect(matrizDeFiltro(FiltroRollo.original), isNull);
    });

    test('Las matrices tienen 20 valores (4×5), como pide ColorFilter.matrix', () {
      expect(matrizDeFiltro(FiltroRollo.blancoNegro), hasLength(20));
      expect(matrizDeFiltro(FiltroRollo.redBlue), hasLength(20));
    });

    test('Blanco y negro: los tres canales quedan iguales', () {
      for (final (r, g, b) in [(200, 30, 90), (10, 250, 40), (128, 128, 128)]) {
        final p = filtrar(FiltroRollo.blancoNegro, r, g, b);
        expect(p[0], p[1]);
        expect(p[1], p[2]);
      }
    });

    test('Red&Blue: sombras azules y luces rojas', () {
      final negro = filtrar(FiltroRollo.redBlue, 0, 0, 0);
      final blanco = filtrar(FiltroRollo.redBlue, 255, 255, 255);
      expect(negro[2], greaterThan(negro[0]), reason: 'en lo oscuro domina el azul');
      expect(blanco[0], greaterThan(blanco[2]), reason: 'en lo claro domina el rojo');
    });

    test('Los valores se recortan a 0..255 (no "dan la vuelta")', () {
      // Con el contraste del B&W, el blanco daría ~274: debe quedar en 255, no en 18.
      expect(filtrar(FiltroRollo.blancoNegro, 255, 255, 255), [255, 255, 255]);
      // Y el negro daría un valor negativo: debe quedar en 0.
      expect(filtrar(FiltroRollo.blancoNegro, 0, 0, 0), [0, 0, 0]);
    });
  });

  group('procesarFoto', () {
    test('Aplica el filtro y devuelve un JPEG con sus medidas', () {
      final foto = procesarFoto((jpegDeColor(64, 48, 220, 40, 40), FiltroRollo.blancoNegro));

      expect(foto.ancho, 64);
      expect(foto.alto, 48);

      final resultado = img.decodeJpg(foto.bytes)!;
      final p = resultado.getPixel(32, 24);
      // JPEG comprime con pérdida: se permite una diferencia pequeña entre canales.
      expect((p.r - p.g).abs(), lessThan(6));
      expect((p.g - p.b).abs(), lessThan(6));
    });

    test('Reduce las fotos más grandes que el lado máximo, sin deformarlas', () {
      final foto = procesarFoto((jpegDeColor(3000, 1500, 90, 90, 90), FiltroRollo.original));
      expect(foto.ancho, ladoMaximo);
      expect(foto.alto, ladoMaximo ~/ 2);
    });

    test('Falla con un error claro si los bytes no son una imagen', () {
      expect(
        () => procesarFoto((Uint8List.fromList([1, 2, 3]), FiltroRollo.original)),
        throwsFormatException,
      );
    });
  });
}
