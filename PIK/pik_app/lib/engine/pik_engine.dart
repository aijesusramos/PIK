import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'film_preset.dart';

/// Motor de revelado de PIK.
///
/// Pipeline (todo en GPU salvo la codificación a JPEG):
///   foto -> [halation: umbral/tinte + reducir + blur]  ─┐
///   foto -> [shader: LUT 3D -> screen(halation) -> grano] -> JPEG
///
/// Uso:
///   final engine = await PikEngine.load();            // una vez, al iniciar
///   final jpg = await engine.developBytes(bytes, FilmPreset.original, seed: foto.id);
class PikEngine {
  PikEngine._(this._program);

  static const _shaderAsset = 'shaders/pik_develop.frag';

  final ui.FragmentProgram _program;
  final Map<String, ui.Image> _lutCache = {};

  static Future<PikEngine> load() async =>
      PikEngine._(await ui.FragmentProgram.fromAsset(_shaderAsset));

  // ------------------------------------------------------------------ API

  /// Revela una foto codificada (JPEG/PNG/HEIC que soporte la plataforma)
  /// y devuelve un JPEG. [seed] debe ser estable por foto (p. ej. su id)
  /// para que el grano sea siempre el mismo si se vuelve a revelar.
  Future<Uint8List> developBytes(
    Uint8List encoded,
    FilmPreset preset, {
    required int seed,
    int maxSide = 2400,
    int jpegQuality = 90,
  }) async {
    final src = await _decode(encoded, maxSide);
    final out = await develop(src, preset, seed: seed);
    src.dispose();
    final jpg = await _encodeJpg(out, jpegQuality);
    out.dispose();
    return jpg;
  }

  /// Igual que [developBytes] pero trabajando con ui.Image (útil para previews).
  Future<ui.Image> develop(ui.Image src, FilmPreset preset, {required int seed}) async {
    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final longSide = math.max(w, h);

    final lut = await _loadLut(preset.lutAsset);
    final halation = await _buildHalation(src, preset);

    final shader = _program.fragmentShader();
    var i = 0;
    shader
      ..setFloat(i++, w) // uSize
      ..setFloat(i++, h)
      ..setFloat(i++, preset.lutSize.toDouble()) // uLutSize
      ..setFloat(i++, preset.halationStrength) // uHalationStrength
      ..setFloat(i++, preset.grainAmount) // uGrainAmount
      ..setFloat(i++, math.max(1.0, preset.grainSize * longSide)) // uGrainSize (px)
      ..setFloat(i++, (seed.abs() % 997) + 0.5) // uSeed (pequeño = precisión estable)
      ..setFloat(i++, halation.width.toDouble()) // uHalSize
      ..setFloat(i++, halation.height.toDouble())
      ..setImageSampler(0, src)
      ..setImageSampler(1, lut)
      ..setImageSampler(2, halation);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..shader = shader);
    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);

    picture.dispose();
    shader.dispose();
    halation.dispose();
    return out;
  }

  // ------------------------------------------------------------------ etapas

  /// Mapa de halation, con primitivas de Canvas en dos pases:
  ///   1) a resolución completa: umbral + tinte (ColorFilter.matrix). Se hace
  ///      antes de reducir para que las luces delgadas (letras de neón) no se
  ///      pierdan al promediarse con el fondo.
  ///   2) reducir a [halationScale] y desenfocar (ImageFilter.blur).
  Future<ui.Image> _buildHalation(ui.Image src, FilmPreset p) async {
    final longSide = math.max(src.width, src.height);
    final hw = math.max(1, (src.width * p.halationScale).round());
    final hh = math.max(1, (src.height * p.halationScale).round());
    final sigma = p.halationRadius * longSide * p.halationScale;

    // mask = clamp((dot(rgb, pesos) - t) / (1 - t)),  salida = mask * tinte
    final t = p.halationThreshold;
    final k = 1.0 / (1.0 - t);
    final (wr, wg, wb) = p.halationWeights;
    List<double> row(double c) => [c * k * wr, c * k * wg, c * k * wb, 0, -c * k * t * 255];
    final (tr, tg, tb) = p.halationTint;
    final matrix = <double>[...row(tr), ...row(tg), ...row(tb), 0, 0, 0, 1, 0];

    // Pase 1: umbral + tinte a resolución completa
    final srcRect = ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    final mask = await _render(src.width, src.height, (canvas) {
      canvas.drawImageRect(src, srcRect, srcRect,
          ui.Paint()..colorFilter = ui.ColorFilter.matrix(matrix));
    });

    // Pase 2: reducir + blur
    final dst = ui.Rect.fromLTWH(0, 0, hw.toDouble(), hh.toDouble());
    final halation = await _render(hw, hh, (canvas) {
      canvas.drawRect(dst, ui.Paint()..color = const ui.Color(0xFF000000));
      canvas.saveLayer(
        dst,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
      );
      canvas.drawImageRect(
          mask, srcRect, dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      canvas.restore();
    });
    mask.dispose();
    return halation;
  }

  Future<ui.Image> _render(int w, int h, void Function(ui.Canvas) paint) async {
    final recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  Future<ui.Image> _loadLut(String asset) async {
    final cached = _lutCache[asset];
    if (cached != null) return cached;
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final lut = (await codec.getNextFrame()).image;
    codec.dispose();
    return _lutCache[asset] = lut;
  }

  /// Decodifica limitando el lado largo a [maxSide] (memoria y tamaño de textura).
  /// instantiateImageCodecWithSize funciona igual en Android, iOS y web.
  Future<ui.Image> _decode(Uint8List bytes, int maxSide) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (int w, int h) {
        final scale = math.min(1.0, maxSide / math.max(w, h));
        return ui.TargetImageSize(
          width: (w * scale).round(),
          height: (h * scale).round(),
        );
      },
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  }

  /// La codificación a JPEG es CPU pura: se hace en otro hilo (compute) para
  /// no trabar la UI. En web compute corre en el mismo hilo, pero funciona.
  Future<Uint8List> _encodeJpg(ui.Image image, int quality) async {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return compute(_encodeJpgWorker, (
      rgba!.buffer.asUint8List(),
      image.width,
      image.height,
      quality,
    ));
  }

  static Uint8List _encodeJpgWorker((Uint8List, int, int, int) args) {
    final (bytes, w, h, quality) = args;
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(im, quality: quality);
  }

  void dispose() {
    for (final lut in _lutCache.values) {
      lut.dispose();
    }
    _lutCache.clear();
  }
}