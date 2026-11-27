import 'package:material_ui/material_ui.dart';

/// Tema oscuro con acento ámbar, como la luz de un cuarto de revelado.
const colorAcento = Color(0xFFE8A33D);

/// Cuerpo de la cámara: gris claro metálico (el tono medio de assets/texturas/metal.png).
const colorMetal = Color(0xFFCACCD0);

/// Paneles hundidos en el metal (visor, contador, compartimento del rollo).
const colorPanel = Color(0xFF1C1D1F);

/// Iconos y controles sobre el metal.
const colorGrafito = Color(0xFF2B2D30);

/// Tipografía: Archivo (Google Fonts, licencia OFL, en assets/fuentes/).
/// Es una grotesca sobria pero con carácter; la versión expandida y muy gruesa
/// (ArchivoExpanded) se usa en los rótulos de la cámara, como las letras grabadas en el
/// cuerpo de una cámara de rollo.
const fuenteTexto = 'Archivo';
const fuenteRotulos = 'ArchivoExpanded';

final ThemeData temaPik = ThemeData(
  useMaterial3: true,
  fontFamily: fuenteTexto,
  colorScheme: ColorScheme.fromSeed(seedColor: colorAcento, brightness: Brightness.dark),
  inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
  ),
);
