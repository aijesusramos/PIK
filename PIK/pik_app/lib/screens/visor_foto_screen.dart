import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/fotos_service.dart';
import '../services/guardar_foto.dart';
import '../utils/formato.dart';
import '../widgets/imagen_protegida.dart';

/// Foto a pantalla completa. Se desliza para pasar a la siguiente y se pellizca
/// (o se usa la rueda del ratón en web) para hacer zoom.
class VisorFotoScreen extends StatefulWidget {
  const VisorFotoScreen({
    super.key,
    required this.fotos,
    required this.indiceInicial,
    required this.cache,
  });

  final List<FotoInfo> fotos;
  final int indiceInicial;
  final CacheImagenes cache;

  @override
  State<VisorFotoScreen> createState() => _VisorFotoScreenState();
}

class _VisorFotoScreenState extends State<VisorFotoScreen> {
  late final PageController _paginas;
  late int _indice;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _indice = widget.indiceInicial;
    _paginas = PageController(initialPage: _indice);
  }

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  FotoInfo get _foto => widget.fotos[_indice];

  Future<void> _descargar() async {
    final foto = _foto;
    final mensajes = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      // Si ya se ve en pantalla, sale de la caché sin volver a descargarla.
      final bytes = await widget.cache.obtener(foto);
      final mensaje = await guardarFoto(bytes, foto.nombreArchivo);
      mensajes.showSnackBar(SnackBar(content: Text(mensaje)));
    } on ApiException catch (e) {
      mensajes.showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _irA(int delta) {
    _paginas.animateToPage(
      _indice + delta,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.fotos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_foto.numeroEnRollo} / $total'),
            Text(
              formatearFecha(_foto.fechaCaptura),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Descargar',
            onPressed: _guardando ? null : _descargar,
            icon: _guardando
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _paginas,
            itemCount: total,
            onPageChanged: (i) => setState(() => _indice = i),
            itemBuilder: (context, i) {
              final foto = widget.fotos[i];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: foto.id,
                    child: ImagenProtegida(foto: foto, cache: widget.cache),
                  ),
                ),
              );
            },
          ),
          // Flechas: en web con ratón no se puede "deslizar" con el dedo.
          if (_indice > 0)
            _Flecha(alineacion: Alignment.centerLeft, icono: Icons.chevron_left, onPressed: () => _irA(-1)),
          if (_indice < total - 1)
            _Flecha(alineacion: Alignment.centerRight, icono: Icons.chevron_right, onPressed: () => _irA(1)),
        ],
      ),
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({required this.alineacion, required this.icono, required this.onPressed});

  final Alignment alineacion;
  final IconData icono;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alineacion,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton.filledTonal(
          tooltip: icono == Icons.chevron_left ? 'Anterior' : 'Siguiente',
          onPressed: onPressed,
          icon: Icon(icono),
        ),
      ),
    );
  }
}
