/// Id de cada foto y la semilla del grano que se deriva de él.
///
/// La app genera el id ANTES de subir la foto, porque lo necesita para revelarla
/// (la semilla hace que el grano de cada foto sea único y siempre el mismo).
/// La API acepta ese id; reenviarlo no duplica la foto.
library;

import 'dart:math';

final _aleatorio = Random.secure();

/// GUID versión 4 (aleatorio), en minúsculas: "3f2a7c1e-9b0d-4c5e-8a1b-0123456789ab".
String nuevoIdFoto() {
  final b = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Semilla del grano para una foto: los primeros 8 dígitos hexadecimales del id como
/// número (0 .. 4 294 967 295).
///
/// No se usa `hashCode` (puede cambiar entre plataformas o versiones) ni un hash con
/// multiplicaciones grandes: en web los enteros son números de JavaScript y perderían
/// precisión, y la misma foto tendría otro grano que en el teléfono.
///
/// El shader recibe `(semilla % 997) + 0.5` (ver PikEngine). Para el mismo grano en
/// tools/preview.py: `--seed` = (semillaDeFoto(id) % 997) + 0.5.
int semillaDeFoto(String id) {
  final hex = id.replaceAll('-', '').toLowerCase();
  if (hex.length != 32 || int.tryParse(hex.substring(0, 8), radix: 16) == null) {
    throw FormatException('Id de foto no válido: $id');
  }
  return int.parse(hex.substring(0, 8), radix: 16);
}
