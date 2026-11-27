import 'dart:typed_data';

import '../engine/film_preset.dart';
import '../engine/pik_engine.dart';
import '../engine/semilla.dart';
import '../models/modelos.dart';

/// Revela las fotos de los rollos con PikEngine.
///
/// Se revela AL CAPTURAR (no al terminar el tiempo): la foto ya está en memoria y el
/// motor solo corre dentro de la app (usa la GPU). La API guarda la original y la
/// revelada bloqueadas hasta que se cumple el tiempo, así que no importa si la app
/// está cerrada en ese momento.
class Revelador {
  Revelador({Future<PikEngine> Function()? cargarMotor})
      : _cargarMotor = cargarMotor ?? PikEngine.load;

  final Future<PikEngine> Function() _cargarMotor;
  Future<PikEngine>? _motor;

  /// Carga el shader una sola vez y lo reutiliza. Si falla, el siguiente intento
  /// vuelve a cargarlo (en lugar de quedarse con el error para siempre).
  Future<PikEngine> _obtenerMotor() {
    final motor = _motor ??= _cargarMotor();
    motor.then((_) {}, onError: (_) {
      if (identical(_motor, motor)) _motor = null;
    });
    return motor;
  }

  /// Empieza a cargar el shader de antemano, para que la primera foto no espere.
  void precargar() => _obtenerMotor().ignore();

  /// Revela [original] con el filtro del rollo. La semilla del grano sale del id
  /// de la foto: la misma foto revelada dos veces da exactamente el mismo resultado.
  Future<Uint8List> revelar(Uint8List original, FiltroRollo filtro, String fotoId) async {
    final motor = await _obtenerMotor();
    return motor.developBytes(original, presetDe(filtro), seed: semillaDeFoto(fotoId));
  }

  /// Único lugar donde se traduce el filtro del rollo (API) al preset del motor.
  static FilmPreset presetDe(FiltroRollo filtro) => FilmPreset.of(switch (filtro) {
        FiltroRollo.original => FilmFilter.original,
        FiltroRollo.blancoNegro => FilmFilter.bw,
        FiltroRollo.redBlue => FilmFilter.redBlue,
      });

  Future<void> dispose() async {
    final motor = _motor;
    _motor = null;
    try {
      if (motor != null) (await motor).dispose();
    } catch (_) {
      // El motor nunca cargó: no hay nada que liberar.
    }
  }
}
