import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pik_app/engine/film_preset.dart';
import 'package:pik_app/engine/pik_engine.dart';

/// Imagen de prueba: degradado horizontal (todas las luminancias) con un punto
/// blanco en el centro, para que haya altas luces que generen halation.
img.Image imagenDePrueba() {
  const w = 300, h = 200;
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = (x / (w - 1) * 255).round();
      im.setPixelRgb(x, y, v, (v * 0.8).round(), (255 - v * 0.6).round());
    }
  }
  img.fillCircle(im, x: 150, y: 100, radius: 12, color: img.ColorRgb8(255, 255, 255));
  return im;
}

Future<ui.Image> aUiImage(img.Image im) async {
  final codec = await ui.instantiateImageCodec(img.encodePng(im));
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Uint8List> rgba(ui.Image im) async =>
    (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

/// Píxel (r, g, b) de un buffer RGBA.
List<int> pixel(Uint8List datos, int ancho, int x, int y) {
  final i = (y * ancho + x) * 4;
  return [datos[i], datos[i + 1], datos[i + 2]];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PikEngine engine;
  late ui.Image entrada;

  setUpAll(() async {
    engine = await PikEngine.load(); // compila/carga shaders/pik_develop.frag
    entrada = await aUiImage(imagenDePrueba());
  });

  test('Revela con el tamaño original', () async {
    final salida = await engine.develop(entrada, FilmPreset.original, seed: 1);
    expect(salida.width, entrada.width);
    expect(salida.height, entrada.height);
    salida.dispose();
  });

  test('Misma semilla → mismo grano; otra semilla → grano distinto', () async {
    final a = await rgba(await engine.develop(entrada, FilmPreset.original, seed: 1));
    final b = await rgba(await engine.develop(entrada, FilmPreset.original, seed: 1));
    final c = await rgba(await engine.develop(entrada, FilmPreset.original, seed: 2));
    expect(a, b);
    expect(a, isNot(c));
  });

  test('El LUT cambia los colores y la halation agrega rojo junto a las luces', () async {
    final antes = await rgba(entrada);
    final despues = await rgba(await engine.develop(entrada, FilmPreset.original, seed: 1));
    const w = 300;

    // Algún cambio de color en toda la imagen (el LUT "original" no es la identidad).
    var diferencia = 0;
    for (var i = 0; i < antes.length; i += 4) {
      diferencia += (antes[i] - despues[i]).abs();
    }
    expect(diferencia / (antes.length / 4), greaterThan(2));

    // Justo fuera del punto blanco (radio 12), en una zona oscura de la columna 150,
    // la halation (screen, tinte rojo-naranja) sube más el rojo que el azul.
    final cerca = pixel(despues, w, 150, 100 + 18);
    final lejos = pixel(despues, w, 150, 100 + 90);
    expect(cerca[0] - lejos[0], greaterThan(cerca[2] - lejos[2]),
        reason: 'cerca=$cerca lejos=$lejos');
  });

  test('Red&Blue: carga su LUT y da un resultado distinto a Original', () async {
    final original = await rgba(await engine.develop(entrada, FilmPreset.original, seed: 1));
    final redBlue = await rgba(
        await engine.develop(entrada, FilmPreset.of(FilmFilter.redBlue), seed: 1));
    expect(redBlue.length, original.length);
    expect(redBlue, isNot(original));
  });

  test('B&W: carga su LUT y el resultado es gris (salvo el grano, que es igual en R, G y B)', () async {
    final bw = await rgba(await engine.develop(entrada, FilmPreset.of(FilmFilter.bw), seed: 1));
    var maxDiferencia = 0;
    for (var i = 0; i < bw.length; i += 4) {
      final d = [(bw[i] - bw[i + 1]).abs(), (bw[i + 1] - bw[i + 2]).abs()];
      maxDiferencia = [maxDiferencia, ...d].reduce((a, b) => a > b ? a : b);
    }
    // LUT neutro + halation blanca + grano igual en los 3 canales → R = G = B
    // (±1 por redondeo de la GPU).
    expect(maxDiferencia, lessThanOrEqualTo(1));
  });

  test('developBytes devuelve un JPEG válido', () async {
    final jpg = await engine.developBytes(img.encodePng(imagenDePrueba()), FilmPreset.original, seed: 1);
    final decodificada = img.decodeJpg(jpg)!;
    expect(decodificada.width, 300);
    expect(decodificada.height, 200);
  });

  // Para comparar con tools/preview.py: PIK_EXPORT=carpeta flutter test test/pik_engine_test.dart
  final exportar = Platform.environment['PIK_EXPORT'];
  test('Exportar entrada/salida para comparar con preview.py', () async {
    File('$exportar/entrada.png').writeAsBytesSync(img.encodePng(imagenDePrueba()));
    // salida_original.png, salida_redBlue.png, salida_bw.png
    for (final filtro in FilmFilter.values) {
      final salida = await engine.develop(entrada, FilmPreset.of(filtro), seed: 1);
      final datos = await rgba(salida);
      final png = img.encodePng(img.Image.fromBytes(
        width: salida.width,
        height: salida.height,
        bytes: datos.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ));
      File('$exportar/salida_${filtro.name}.png').writeAsBytesSync(png);
    }
  }, skip: exportar == null ? 'solo con PIK_EXPORT' : false);
}
