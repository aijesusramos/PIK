import 'package:material_ui/material_ui.dart';

/// Tema oscuro con acento ámbar, como la luz de un cuarto de revelado.
const colorAcento = Color(0xFFE8A33D);

final ThemeData temaPik = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: colorAcento,
    brightness: Brightness.dark,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
    ),
  ),
);
