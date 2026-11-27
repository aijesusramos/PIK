import 'package:material_ui/material_ui.dart';

import '../models/modelos.dart';

/// Icono del rollo fotográfico de cada filtro (assets/rollos/). Sin filtro (`null`) es el
/// rollo vacío, el del botón de la cámara cuando todavía no hay un rollo activo.
///
/// Los PNG miden 450×450 con fondo transparente y los mismos márgenes, así que todos ocupan
/// el mismo lugar: [tamano] es el lado del cuadro donde se dibujan.
class IconoRollo extends StatelessWidget {
  const IconoRollo({super.key, required this.filtro, this.tamano = 56});

  final FiltroRollo? filtro;
  final double tamano;

  static String rutaDe(FiltroRollo? filtro) => switch (filtro) {
        FiltroRollo.original => 'assets/rollos/original.png',
        FiltroRollo.blancoNegro => 'assets/rollos/blanco_negro.png',
        FiltroRollo.redBlue => 'assets/rollos/red_blue.png',
        null => 'assets/rollos/vacio.png',
      };

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      rutaDe(filtro),
      width: tamano,
      height: tamano,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium, // se reduce mucho (450 px → ~50): que no se vea pixeleado
      gaplessPlayback: true, // al cambiar de rollo no parpadea en blanco
      semanticLabel: filtro == null ? 'Sin rollo' : 'Rollo ${filtro!.nombre}',
    );
  }
}
