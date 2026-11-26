import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/fotos_service.dart';
import '../services/mis_rollos.dart';
import '../utils/formato.dart';
import '../widgets/imagen_protegida.dart';
import '../widgets/panel_rollo.dart';
import 'visor_foto_screen.dart';

/// Galería de un rollo revelado: sus fotos en cuadrícula, como una hoja de contactos.
class GaleriaScreen extends StatefulWidget {
  const GaleriaScreen({super.key, required this.rollo, required this.misRollos});

  final Rollo rollo;

  /// Para cambiar el título (esta pantalla es una ruta y no hereda el provider).
  final MisRollos misRollos;

  @override
  State<GaleriaScreen> createState() => _GaleriaScreenState();
}

class _GaleriaScreenState extends State<GaleriaScreen> {
  late final FotosService _fotos;

  /// Vive mientras la galería esté abierta (y la comparte con el visor).
  late final CacheImagenes _cache;

  FotosDeRollo? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fotos = context.read<FotosService>();
    _cache = CacheImagenes(_fotos);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final datos = await _fotos.listar(widget.rollo.id);
      if (mounted) setState(() => _datos = datos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  void _abrirFoto(int indice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisorFotoScreen(fotos: _datos!.fotos, indiceInicial: indice, cache: _cache),
      ),
    );
  }

  /// La versión más reciente del rollo (por si se renombró mientras está abierta).
  Rollo get _rollo {
    for (final r in widget.misRollos.rollos) {
      if (r.id == widget.rollo.id) return r;
    }
    return _datos?.rollo ?? widget.rollo;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.misRollos,
      builder: (context, _) => _construir(context, _rollo),
    );
  }

  Widget _construir(BuildContext context, Rollo rollo) {
    return Scaffold(
      appBar: AppBar(
        title: Text(rollo.titulo),
        actions: [
          IconButton(
            tooltip: 'Cambiar título',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => renombrarRollo(context, widget.misRollos, rollo),
          ),
        ],
        bottom: rollo.fechaFinRevelado == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${rollo.filtro.nombre} · ${rollo.fotosTomadas} fotos · '
                    'revelado el ${formatearFecha(rollo.fechaFinRevelado!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    final datos = _datos;

    if (_error != null) {
      return _Mensaje(
        icono: Icons.cloud_off,
        texto: _error!,
        accion: OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
      );
    }

    if (datos == null) return const Center(child: CircularProgressIndicator());

    // El servidor decide si ya se reveló (por la hora), no la app.
    if (datos.bloqueado) {
      final restante = Duration(seconds: datos.segundosRestantes ?? 0);
      return _Mensaje(
        icono: Icons.hourglass_top,
        texto: datos.rollo.estado == EstadoRollo.enCola
            ? 'Este rollo está en cola. Empezará a revelarse cuando termine otro.'
            : 'Este rollo se sigue revelando.\nListo en ${formatearDuracion(restante)}.',
        accion: OutlinedButton(onPressed: _cargar, child: const Text('Actualizar')),
      );
    }

    if (datos.fotos.isEmpty) {
      return const _Mensaje(icono: Icons.photo_outlined, texto: 'Este rollo no tiene fotos.');
    }

    final proporcion = MediaQuery.devicePixelRatioOf(context);
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      // Columnas de máximo 180 px: 2–3 en un teléfono, más en una ventana ancha.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: datos.fotos.length,
      itemBuilder: (context, i) {
        final foto = datos.fotos[i];
        return _Miniatura(
          foto: foto,
          cache: _cache,
          tamanoDecodificado: (180 * proporcion).round(),
          onTap: () => _abrirFoto(i),
        );
      },
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({
    required this.foto,
    required this.cache,
    required this.tamanoDecodificado,
    required this.onTap,
  });

  final FotoInfo foto;
  final CacheImagenes cache;
  final int tamanoDecodificado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Foto ${foto.numeroEnRollo}',
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: esquema.surfaceContainerHighest),
            // Hero: la miniatura "vuela" a la pantalla completa al abrirla.
            Hero(
              tag: foto.id,
              child: ImagenProtegida(
                foto: foto,
                cache: cache,
                fit: BoxFit.cover,
                tamanoDecodificado: tamanoDecodificado,
              ),
            ),
            // Número de cuadro, como en los bordes de un negativo.
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  foto.numeroEnRollo.toString().padLeft(2, '0'),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ],
        ),
      ),
    );
  }
}
