import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pik_app/engine/film_preset.dart';
import 'package:pik_app/engine/semilla.dart';
import 'package:pik_app/fotos/preparar_foto.dart';
import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/services/revelador.dart';

/// JPEG de prueba: degradado con un punto claro (para que el revelado tenga qué cambiar).
Uint8List jpegDePrueba(int ancho, int alto) {
  final im = img.Image(width: ancho, height: alto);
  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      final v = (x / (ancho - 1) * 255).round();
      im.setPixelRgb(x, y, v, 120, 255 - v);
    }
  }
  return img.encodeJpg(im, quality: 95);
}

void main() {
  group('Id y semilla de la foto', () {
    test('nuevoIdFoto genera GUIDs v4 válidos y distintos', () {
      final guid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 200; i++) nuevoIdFoto()};
      expect(ids, hasLength(200));
      expect(ids.every(guid.hasMatch), isTrue);
    });

    test('semillaDeFoto: valor fijo, estable y sin importar mayúsculas', () {
      const id = '7e4a50bd-ba16-4b96-af3c-30b06deab9ab';
      expect(semillaDeFoto(id), 0x7e4a50bd); // 2118799549
      expect(semillaDeFoto(id.toUpperCase()), 0x7e4a50bd); // SQLite devuelve el GUID en mayúsculas
      expect(semillaDeFoto(id), semillaDeFoto(id));
    });

    test('semillaDeFoto rechaza ids que no son GUID', () {
      expect(() => semillaDeFoto('foto-1'), throwsFormatException);
    });
  });

  group('prepararOriginal', () {
    test('Conserva los colores (no aplica ningún filtro)', () {
      final im = img.Image(width: 40, height: 30);
      img.fill(im, color: img.ColorRgb8(200, 60, 30));
      final foto = prepararOriginal(img.encodeJpg(im, quality: 100));

      final p = img.decodeJpg(foto.bytes)!.getPixel(20, 15);
      expect((p.r - 200).abs(), lessThan(6));
      expect((p.g - 60).abs(), lessThan(6));
      expect((p.b - 30).abs(), lessThan(6));
      expect((foto.ancho, foto.alto), (40, 30));
    });

    test('Reduce las fotos grandes sin deformarlas', () {
      final foto = prepararOriginal(jpegDePrueba(3000, 1500));
      expect((foto.ancho, foto.alto), (ladoMaximo, ladoMaximo ~/ 2));
    });

    test('Falla con un error claro si los bytes no son una imagen', () {
      expect(() => prepararOriginal(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });

  group('Revelador (motor real)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final revelador = Revelador();
    final original = prepararOriginal(jpegDePrueba(160, 120)).bytes;
    const idA = '11111111-2222-4333-8444-555555555555';
    const idB = '99999999-2222-4333-8444-555555555555';

    tearDownAll(revelador.dispose);

    test('El filtro de cada rollo usa su preset', () {
      expect(Revelador.presetDe(FiltroRollo.original), same(FilmPreset.original));
      expect(Revelador.presetDe(FiltroRollo.blancoNegro), same(FilmPreset.bw));
      expect(Revelador.presetDe(FiltroRollo.redBlue), same(FilmPreset.redBlue));
    });

    test('Misma foto y mismo id → exactamente la misma revelada', () async {
      final a = await revelador.revelar(original, FiltroRollo.redBlue, idA);
      final b = await revelador.revelar(original, FiltroRollo.redBlue, idA);
      expect(a, b);
    });

    test('Otro id → otro grano; otro filtro → otro look', () async {
      final a = await revelador.revelar(original, FiltroRollo.redBlue, idA);
      final otroId = await revelador.revelar(original, FiltroRollo.redBlue, idB);
      final otroFiltro = await revelador.revelar(original, FiltroRollo.blancoNegro, idA);
      expect(a, isNot(otroId));
      expect(a, isNot(otroFiltro));
    });

    test('La revelada tiene las mismas medidas que la original y no es la original', () async {
      final revelada = await revelador.revelar(original, FiltroRollo.original, idA);
      final im = img.decodeJpg(revelada)!;
      expect((im.width, im.height), (160, 120));
      expect(revelada, isNot(original));
    });
  });
}
