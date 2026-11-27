import 'package:material_ui/material_ui.dart';

import '../models/modelos.dart';
import '../utils/formato.dart';

/// Tarjeta de un rollo en la galería de rollos.
class TarjetaRollo extends StatelessWidget {
  const TarjetaRollo({super.key, required this.rollo, this.onTap});

  final Rollo rollo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconoRollo(filtro: rollo.filtro, tamano: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rollo.titulo,
                      style: tema.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${rollo.filtro.nombre} · ${rollo.capacidad} fotos',
                      style: tema.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(_detalle(), style: tema.textTheme.bodySmall),
                    if (rollo.estado == EstadoRollo.activo) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: rollo.capacidad == 0 ? 0 : rollo.fotosTomadas / rollo.capacidad,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ChipEstado(estado: rollo.estado),
            ],
          ),
        ),
      ),
    );
  }

  String _detalle() {
    switch (rollo.estado) {
      case EstadoRollo.activo:
        return '${rollo.fotosTomadas} de ${rollo.capacidad} tomadas · quedan ${rollo.fotosRestantes}';
      case EstadoRollo.enCola:
        return '${rollo.fotosTomadas} fotos · esperando turno para revelarse';
      case EstadoRollo.revelando:
        final restante = rollo.tiempoRestante ?? Duration.zero;
        return '${rollo.fotosTomadas} fotos · listo en ${formatearDuracion(restante)}';
      case EstadoRollo.revelado:
        return '${rollo.fotosTomadas} fotos reveladas';
    }
  }
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.estado});

  final EstadoRollo estado;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final (fondo, texto) = switch (estado) {
      EstadoRollo.activo => (esquema.primaryContainer, esquema.onPrimaryContainer),
      EstadoRollo.enCola => (esquema.surfaceContainerHighest, esquema.onSurfaceVariant),
      EstadoRollo.revelando => (esquema.tertiaryContainer, esquema.onTertiaryContainer),
      EstadoRollo.revelado => (esquema.secondaryContainer, esquema.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
      child: Text(estado.nombre, style: TextStyle(color: texto, fontSize: 12)),
    );
  }
}

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
