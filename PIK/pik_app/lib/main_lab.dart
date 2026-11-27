import 'package:material_ui/material_ui.dart';

import 'debug/laboratorio_screen.dart';
import 'theme.dart';

/// TEMPORAL — Punto de entrada del laboratorio de revelado (no es la app PIK).
///
///   flutter run -d chrome -t lib/main_lab.dart
///
/// No usa la API, ni la sesión, ni los rollos: solo el motor (lib/engine/).
/// Para quitarlo: borrar este archivo y lib/debug/.
void main() {
  runApp(
    MaterialApp(
      title: 'PIK · Laboratorio',
      debugShowCheckedModeBanner: false,
      theme: temaPik,
      home: const LaboratorioScreen(),
    ),
  );
}
