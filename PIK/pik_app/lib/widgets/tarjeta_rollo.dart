import 'package:material_ui/material_ui.dart';

import '../models/modelos.dart';
import '../theme.dart';
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
              MuestraFiltro(filtro: rollo.filtro, tamano: 48),
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

/// Cuadro que representa el look de cada filtro con un degradado.
///
/// Los colores son los de un mismo degradado base (amarillo, coral, azul, verde y un
/// tono oscuro) pasado por la función de cada filtro en tools/generate_lut.py, la
/// misma que genera su LUT. Si cambian los LUTs, hay que recalcularlos.
class MuestraFiltro extends StatelessWidget {
  const MuestraFiltro({super.key, required this.filtro, this.tamano = 56});

  final FiltroRollo filtro;
  final double tamano;

  static const _colores = {
    FiltroRollo.original: [
      Color(0xFFE9C449), Color(0xFFCB6C4F), Color(0xFF5FAACF), Color(0xFF6FBE57), Color(0xFF1A2637),
    ],
    FiltroRollo.blancoNegro: [
      Color(0xFFE4E4E4), Color(0xFFB6B6B6), Color(0xFFB9B9B9), Color(0xFFBDBDBD), Color(0xFF282828),
    ],
    FiltroRollo.redBlue: [
      Color(0xFFDAC996), Color(0xFFE77656), Color(0xFF5DB7ED), Color(0xFF95B790), Color(0xFF262F51),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorAcento.withValues(alpha: 0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colores[filtro]!,
        ),
      ),
    );
  }
}
