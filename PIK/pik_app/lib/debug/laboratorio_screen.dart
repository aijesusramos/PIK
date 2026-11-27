import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../engine/film_preset.dart';
import '../engine/pik_engine.dart';
import '../services/guardar_foto.dart';

/// TEMPORAL — Laboratorio para validar el look del motor de revelado.
///
/// No está conectada a los rollos ni a la API. Se abre con su propio punto de entrada:
///   flutter run -d chrome -t lib/main_lab.dart
///
/// Revela con el filtro elegido (FilmPreset.of) y seed = 1 (el shader recibe 1.5; para el mismo
/// grano en tools/preview.py usar --seed 1.5).
class LaboratorioScreen extends StatefulWidget {
  const LaboratorioScreen({super.key});

  @override
  State<LaboratorioScreen> createState() => _LaboratorioScreenState();
}

enum _Vista { antes, despues, comparar }

class _LaboratorioScreenState extends State<LaboratorioScreen> {
  static const _seed = 1;

  /// Filtros que ya tienen LUT y preset.
  static const _filtrosDisponibles = [FilmFilter.original, FilmFilter.redBlue, FilmFilter.bw];

  FilmFilter _filtro = FilmFilter.original;

  /// Cada revelado lleva un número. Si cambias de filtro mientras otro revelado sigue
  /// en curso, solo se muestra el resultado del último que se pidió.
  int _ultimoRevelado = 0;

  PikEngine? _engine;
  String? _error;

  Uint8List? _original;
  Uint8List? _revelada;
  String _nombre = 'foto';
  bool _revelando = false;
  Duration? _tiempo;
  (int, int)? _medidas;

  _Vista _vista = _Vista.comparar;
  double _division = 0.5;

  @override
  void initState() {
    super.initState();
    _cargarMotor();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _cargarMotor() async {
    try {
      final engine = await PikEngine.load();
      if (mounted) setState(() => _engine = engine);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el shader: $e');
    }
  }

  Future<void> _elegirFoto() async {
    final archivo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() {
      _original = bytes;
      _revelada = null;
      _nombre = archivo.name.split('.').first;
    });
    await _revelar();
  }

  void _cambiarFiltro(FilmFilter filtro) {
    if (filtro == _filtro) return;
    setState(() => _filtro = filtro);
    _revelar(); // vuelve a revelar la foto actual con el nuevo filtro
  }

  Future<void> _revelar() async {
    final engine = _engine;
    final original = _original;
    if (engine == null || original == null) return;

    final numero = ++_ultimoRevelado;
    final filtro = _filtro;
    setState(() {
      _revelando = true;
      _error = null;
    });
    final reloj = Stopwatch()..start();
    try {
      final jpg = await engine.developBytes(original, FilmPreset.of(filtro), seed: _seed);
      reloj.stop();
      final codec = await ui.instantiateImageCodec(jpg);
      final frame = await codec.getNextFrame();
      final medidas = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      if (!mounted || numero != _ultimoRevelado) return; // llegó otro más nuevo
      setState(() {
        _revelada = jpg;
        _tiempo = reloj.elapsed;
        _medidas = medidas;
      });
    } catch (e) {
      if (mounted && numero == _ultimoRevelado) setState(() => _error = 'Error al revelar: $e');
    } finally {
      if (mounted && numero == _ultimoRevelado) setState(() => _revelando = false);
    }
  }

  Future<void> _descargar() async {
    final revelada = _revelada;
    if (revelada == null) return;
    final mensaje = await guardarFoto(revelada, '${_nombre}_pik_${_filtro.name}_seed$_seed');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laboratorio de revelado'),
        actions: [
          IconButton(
            tooltip: 'Descargar revelada',
            onPressed: _revelada == null ? null : _descargar,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _engine == null || _revelando ? null : _elegirFoto,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Elegir foto'),
      ),
      body: Column(
        children: [
          _barraInfo(),
          // Filtro: siempre visible, para poder elegirlo antes de escoger la foto.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<FilmFilter>(
              segments: [
                for (final f in _filtrosDisponibles)
                  ButtonSegment(value: f, label: Text(_nombreFiltro(f))),
              ],
              selected: {_filtro},
              onSelectionChanged: (s) => _cambiarFiltro(s.first),
            ),
          ),
          if (_original != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SegmentedButton<_Vista>(
                segments: const [
                  ButtonSegment(value: _Vista.antes, label: Text('Antes')),
                  ButtonSegment(value: _Vista.comparar, label: Text('Comparar')),
                  ButtonSegment(value: _Vista.despues, label: Text('Después')),
                ],
                selected: {_vista},
                onSelectionChanged: (s) => setState(() => _vista = s.first),
              ),
            ),
          Expanded(child: _imagen()),
          if (_vista == _Vista.comparar && _revelada != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              child: Slider(
                value: _division,
                onChanged: (v) => setState(() => _division = v),
                semanticFormatterCallback: (v) => 'Antes ${(v * 100).round()} %',
              ),
            ),
        ],
      ),
    );
  }

  static String _nombreFiltro(FilmFilter f) => switch (f) {
        FilmFilter.original => 'Original',
        FilmFilter.redBlue => 'Red&Blue',
        FilmFilter.bw => 'B&W',
      };

  Widget _barraInfo() {
    final tema = Theme.of(context);
    final String texto;
    if (_error != null) {
      texto = _error!;
    } else if (_engine == null) {
      texto = 'Cargando shader…';
    } else if (_revelando) {
      texto = 'Revelando…';
    } else if (_tiempo != null && _medidas != null) {
      texto = '${_nombreFiltro(_filtro)} · seed $_seed · ${_medidas!.$1}×${_medidas!.$2} px · '
          '${_tiempo!.inMilliseconds} ms · ${(_revelada!.length / 1024).round()} KB';
    } else {
      texto = 'Elige una foto para revelarla con ${_nombreFiltro(_filtro)} (seed $_seed).';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: _error != null ? tema.colorScheme.errorContainer : tema.colorScheme.surfaceContainerHigh,
      child: Text(texto, style: tema.textTheme.bodySmall),
    );
  }

  Widget _imagen() {
    final original = _original;
    final revelada = _revelada;
    if (original == null) {
      return const Center(child: Icon(Icons.science_outlined, size: 64));
    }

    final antes = Image.memory(original, fit: BoxFit.contain, gaplessPlayback: true);
    if (revelada == null) {
      return Stack(
        fit: StackFit.expand,
        children: [antes, if (_revelando) const Center(child: CircularProgressIndicator())],
      );
    }
    final despues = Image.memory(revelada, fit: BoxFit.contain, gaplessPlayback: true);

    return switch (_vista) {
      _Vista.antes => antes,
      _Vista.despues => despues,
      // "Después" completo debajo y "Antes" recortado encima, hasta la división.
      // Las dos usan BoxFit.contain en la misma caja, así que coinciden píxel a píxel.
      _Vista.comparar => LayoutBuilder(
          builder: (context, caja) => GestureDetector(
            onHorizontalDragUpdate: (d) => setState(
              () => _division = (d.localPosition.dx / caja.maxWidth).clamp(0.0, 1.0),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                despues,
                ClipRect(clipper: _RecorteIzquierdo(_division), child: antes),
                Positioned(
                  left: caja.maxWidth * _division - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white70),
                ),
                const Positioned(left: 8, top: 8, child: _Etiqueta('Antes')),
                const Positioned(right: 8, top: 8, child: _Etiqueta('Después')),
              ],
            ),
          ),
        ),
    };
  }
}

class _RecorteIzquierdo extends CustomClipper<Rect> {
  const _RecorteIzquierdo(this.fraccion);

  final double fraccion;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraccion, size.height);

  @override
  bool shouldReclip(_RecorteIzquierdo anterior) => anterior.fraccion != fraccion;
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
      child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
