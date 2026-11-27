import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pik_app/models/modelos.dart';
import 'package:pik_app/widgets/tarjeta_rollo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cada filtro (y el rollo vacío) tiene su propio icono y el archivo existe', () async {
    final filtros = <FiltroRollo?>[...FiltroRollo.values, null];
    final rutas = filtros.map(IconoRollo.rutaDe).toList();

    expect(rutas.toSet(), hasLength(filtros.length)); // ninguno repetido
    for (final ruta in rutas) {
      // Falla si el PNG no está o no se registró assets/rollos/ en pubspec.yaml.
      final datos = await rootBundle.load(ruta);
      expect(datos.lengthInBytes, greaterThan(0), reason: ruta);
    }
  });

  test('Los demás assets de la cámara existen (nombres en minúsculas: Android y web distinguen)',
      () async {
    for (final ruta in ['assets/iconos/galeria.png', 'assets/texturas/metal.png']) {
      final datos = await rootBundle.load(ruta);
      expect(datos.lengthInBytes, greaterThan(0), reason: ruta);
    }
  });
}
