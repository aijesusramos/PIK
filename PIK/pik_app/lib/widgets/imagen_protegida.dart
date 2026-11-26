import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/fotos_service.dart';

/// Muestra una foto protegida de la API: la descarga con el JWT (vía [CacheImagenes])
/// y mientras tanto muestra un indicador. Si falla, permite reintentar.
class ImagenProtegida extends StatefulWidget {
  const ImagenProtegida({
    super.key,
    required this.foto,
    required this.cache,
    this.fit = BoxFit.contain,
    this.tamanoDecodificado,
  });

  final FotoInfo foto;
  final CacheImagenes cache;
  final BoxFit fit;

  /// Si se indica, la imagen se decodifica a este tamaño (en píxeles) en su lado más
  /// corto. Para miniaturas: una foto de 1920 px ocupa ~8 MB de memoria ya
  /// decodificada; a 360 px, unos 0.5 MB.
  final int? tamanoDecodificado;

  @override
  State<ImagenProtegida> createState() => _ImagenProtegidaState();
}

class _ImagenProtegidaState extends State<ImagenProtegida> {
  late Future<Uint8List> _imagen;

  @override
  void initState() {
    super.initState();
    _imagen = widget.cache.obtener(widget.foto);
  }

  @override
  void didUpdateWidget(ImagenProtegida anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.foto.id != widget.foto.id) _imagen = widget.cache.obtener(widget.foto);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imagen,
      builder: (context, estado) {
        if (estado.hasError) return _error(estado.error);
        if (!estado.hasData) {
          return const Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        // Se reduce el lado más corto para que, con BoxFit.cover, la miniatura no se vea borrosa.
        final tamano = widget.tamanoDecodificado;
        final horizontal = widget.foto.ancho >= widget.foto.alto;
        return Image.memory(
          estado.data!,
          fit: widget.fit,
          gaplessPlayback: true,
          cacheWidth: tamano != null && !horizontal ? tamano : null,
          cacheHeight: tamano != null && horizontal ? tamano : null,
        );
      },
    );
  }

  Widget _error(Object? error) {
    // 423: la API dice que el rollo aún se revela (no debería pasar en la galería,
    // pero el servidor es quien decide).
    final bloqueada = error is ApiException && error.statusCode == 423;
    return Center(
      child: IconButton(
        tooltip: bloqueada ? 'Todavía se está revelando' : 'No se pudo cargar. Toca para reintentar.',
        icon: Icon(bloqueada ? Icons.lock_clock_outlined : Icons.refresh),
        onPressed: bloqueada
            ? null
            : () => setState(() => _imagen = widget.cache.obtener(widget.foto)),
      ),
    );
  }
}
