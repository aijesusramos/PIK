import 'package:material_ui/material_ui.dart';

import '../filtros/filtros.dart';
import '../models/modelos.dart';
import '../theme.dart';

/// Tarjeta de un rollo en la pantalla principal.
class TarjetaRollo extends StatelessWidget {
  const TarjetaRollo({super.key, required this.rollo, this.onTap, this.onCerrar});

  final Rollo rollo;
  final VoidCallback? onTap;

  /// Solo para rollos Activos con al menos una foto.
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final puedeCerrar =
        onCerrar != null && rollo.estado == EstadoRollo.activo && rollo.fotosTomadas > 0;

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
                      'Rollo ${rollo.filtro.nombre} · ${rollo.capacidad} fotos',
                      style: tema.textTheme.titleMedium,
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
              if (puedeCerrar)
                IconButton(
                  tooltip: 'Cerrar rollo',
                  icon: const Icon(Icons.lock_outline),
                  onPressed: onCerrar,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _detalle() {
    switch (rollo.estado) {
      case EstadoRollo.activo:
        return '${rollo.fotosTomadas} de ${rollo.capacidad} fotos · quedan ${rollo.fotosRestantes}';
      case EstadoRollo.enCola:
        return '${rollo.fotosTomadas} fotos · esperando turno para revelarse';
      case EstadoRollo.revelando:
        final restante = rollo.tiempoRestante ?? Duration.zero;
        return '${rollo.fotosTomadas} fotos · listo en ${_formatear(restante)}';
      case EstadoRollo.revelado:
        return '${rollo.fotosTomadas} fotos reveladas';
    }
  }

  static String _formatear(Duration d) {
    if (d <= Duration.zero) return 'unos segundos';
    final horas = d.inHours;
    final minutos = d.inMinutes.remainder(60);
    if (horas > 0) return '$horas h $minutos min';
    if (minutos > 0) return '$minutos min';
    return 'menos de 1 min';
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

/// Cuadro que muestra el efecto del filtro: un degradado de colores al que se le
/// aplica la misma matriz que a las fotos (ver filtros.dart).
class MuestraFiltro extends StatelessWidget {
  const MuestraFiltro({super.key, required this.filtro, this.tamano = 56});

  final FiltroRollo filtro;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    Widget muestra = Container(
      width: tamano,
      height: tamano,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2C14E), Color(0xFFE76F51), Color(0xFF5DA9E9), Color(0xFF6BBF59)],
        ),
      ),
    );

    final matriz = matrizDeFiltro(filtro);
    if (matriz != null) {
      muestra = ColorFiltered(colorFilter: ColorFilter.matrix(matriz), child: muestra);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorAcento.withValues(alpha: 0.4)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(7), child: muestra),
    );
  }
}
