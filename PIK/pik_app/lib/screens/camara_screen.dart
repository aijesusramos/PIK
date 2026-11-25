import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../filtros/filtros.dart';
import '../models/modelos.dart';
import '../services/fotos_service.dart';
import '../theme.dart';
import '../widgets/tarjeta_rollo.dart';

/// Cámara de un rollo Activo.
///
/// Como en una cámara de rollo, **la foto no se muestra al tomarla**: solo avanza el
/// contador. Se verá hasta que el rollo se revele.
///
/// Flujo de cada disparo:
///   capturar → aplicar el filtro del rollo → subir a la API → avanzar el contador.
/// Mientras eso pasa el obturador queda bloqueado ("avanzando la película"), así
/// las fotos se suben una por una y en orden.
class CamaraScreen extends StatefulWidget {
  const CamaraScreen({super.key, required this.rollo});

  final Rollo rollo;

  @override
  State<CamaraScreen> createState() => _CamaraScreenState();
}

class _CamaraScreenState extends State<CamaraScreen> with WidgetsBindingObserver {
  late Rollo _rollo;

  List<CameraDescription> _camaras = [];
  int _indiceCamara = 0;
  CameraController? _controlador;
  String? _errorCamara;

  /// Procesando y subiendo la última foto.
  bool _avanzando = false;

  /// Destello blanco al disparar.
  bool _destello = false;

  /// Foto que no se pudo subir (sin red, API apagada...). Se puede reintentar.
  FotoProcesada? _pendiente;
  DateTime? _fechaPendiente;

  /// Se tomó al menos una foto: al volver, la pantalla de inicio debe recargar.
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _rollo = widget.rollo;
    WidgetsBinding.instance.addObserver(this);
    _iniciarCamaras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlador?.dispose();
    super.dispose();
  }

  /// En el teléfono, al salir de la app se libera la cámara (otras apps la pueden
  /// necesitar) y al volver se abre de nuevo. En web no hace falta.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.inactive) {
      final c = _controlador;
      if (c == null) return;
      setState(() => _controlador = null);
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controlador == null && _camaras.isNotEmpty) _abrirCamara();
    }
  }

  // ---------- Cámara ----------

  Future<void> _iniciarCamaras() async {
    setState(() => _errorCamara = null);
    try {
      _camaras = await availableCameras();
    } on CameraException catch (e) {
      if (mounted) setState(() => _errorCamara = _mensajeCamara(e));
      return;
    }
    if (_camaras.isEmpty) {
      if (mounted) setState(() => _errorCamara = 'No se encontró ninguna cámara en este dispositivo.');
      return;
    }
    // Se prefiere la cámara trasera.
    final trasera = _camaras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _indiceCamara = trasera >= 0 ? trasera : 0;
    await _abrirCamara();
  }

  Future<void> _abrirCamara() async {
    final anterior = _controlador;
    if (mounted) setState(() => _controlador = null);
    await anterior?.dispose();

    final c = CameraController(
      _camaras[_indiceCamara],
      ResolutionPreset.veryHigh, // 1080p; procesarFoto reduce si llega algo más grande
      enableAudio: false, // solo fotos: así no se pide permiso de micrófono
    );
    try {
      await c.initialize();
    } on CameraException catch (e) {
      await c.dispose();
      if (mounted) setState(() => _errorCamara = _mensajeCamara(e));
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _controlador = c;
      _errorCamara = null;
    });
  }

  Future<void> _cambiarCamara() async {
    if (_camaras.length < 2 || _avanzando) return;
    _indiceCamara = (_indiceCamara + 1) % _camaras.length;
    await _abrirCamara();
  }

  String _mensajeCamara(CameraException e) => switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          kIsWeb
              ? 'PIK necesita permiso para usar la cámara. Permítelo en el ícono '
                  'de la cámara de la barra de direcciones y toca Reintentar.'
              : 'PIK necesita permiso para usar la cámara. Actívalo en la '
                  'configuración del teléfono y toca Reintentar.',
        'cameraNotFound' => 'No se encontró ninguna cámara.',
        'cameraNotReadable' => 'La cámara está en uso por otra aplicación.',
        _ => 'No se pudo abrir la cámara (${e.description ?? e.code}).',
      };

  // ---------- Disparo ----------

  bool get _puedeDisparar {
    final c = _controlador;
    return c != null &&
        c.value.isInitialized &&
        !c.value.isTakingPicture &&
        !_avanzando &&
        _pendiente == null &&
        _rollo.estado == EstadoRollo.activo &&
        _rollo.fotosRestantes > 0;
  }

  Future<void> _disparar() async {
    if (!_puedeDisparar) return;
    final c = _controlador!;
    final fotos = context.read<FotosService>(); // antes de cualquier await

    setState(() {
      _avanzando = true;
      _destello = true;
    });
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _destello = false);
    });

    try {
      final archivo = await c.takePicture();
      final fecha = DateTime.now().toUtc();
      final bytes = await archivo.readAsBytes();

      // En el teléfono, compute procesa la foto en otro hilo (isolate) para que
      // la interfaz no se congele. En web corre en el mismo hilo.
      final foto = await compute(procesarFoto, (bytes, _rollo.filtro));

      await _subir(fotos, foto, fecha);
    } on CameraException catch (e) {
      _mostrarMensaje('No se pudo tomar la foto (${e.description ?? e.code}).');
    } on FormatException catch (e) {
      _mostrarMensaje(e.message);
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  Future<void> _reintentar() async {
    final foto = _pendiente;
    final fecha = _fechaPendiente;
    if (foto == null || fecha == null || _avanzando) return;
    final fotos = context.read<FotosService>();
    setState(() => _avanzando = true);
    try {
      await _subir(fotos, foto, fecha);
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  void _descartarPendiente() => setState(() {
        _pendiente = null;
        _fechaPendiente = null;
      });

  Future<void> _subir(FotosService fotos, FotoProcesada foto, DateTime fecha) async {
    try {
      final subida = await fotos.subir(_rollo.id, foto, fecha);
      if (!mounted) return;
      setState(() {
        _rollo = subida.rollo;
        _pendiente = null;
        _fechaPendiente = null;
        _huboCambios = true;
      });
      // Era la última foto: la API ya cerró el rollo.
      if (subida.rollo.estado != EstadoRollo.activo) await _rolloCompleto();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // El rollo ya no acepta fotos (se cerró o se llenó desde otro lado).
        _descartarPendiente();
        await _avisar('No se guardó la foto', e.mensaje);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      // Error de red o del servidor: se guarda para reintentar.
      setState(() {
        _pendiente = foto;
        _fechaPendiente = fecha;
      });
      _mostrarMensaje('No se pudo guardar la foto: ${e.mensaje}');
    }
  }

  Future<void> _rolloCompleto() async {
    final mensaje = _rollo.estado == EstadoRollo.enCola
        ? 'Ya tienes 2 rollos revelándose, así que este quedó en cola. '
            'Empezará a revelarse solo cuando termine uno '
            '(tardará ${_rollo.horasRevelado} h).'
        : 'Ya está en el cuarto oscuro. Tus fotos estarán listas en '
            '${_rollo.horasRevelado} h.';
    await _avisar('¡Rollo completo!', mensaje);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _avisar(String titulo, String mensaje) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(titulo),
          content: Text(mensaje),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
          ],
        ),
      );

  void _mostrarMensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_avanzando, // no salir a media subida
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _avanzando) _mostrarMensaje('Espera a que se guarde la foto.');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _barraSuperior(),
              Expanded(child: Center(child: _visor())),
              if (_pendiente != null) _avisoPendiente(),
              _barraInferior(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraSuperior() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Salir',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: _avanzando ? null : () => Navigator.of(context).pop(_huboCambios),
          ),
          const Spacer(),
          _ContadorFotos(rollo: _rollo),
          const Spacer(),
          if (_camaras.length > 1)
            IconButton(
              tooltip: 'Cambiar cámara',
              color: Colors.white,
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: _avanzando ? null : _cambiarCamara,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _visor() {
    if (_errorCamara != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48, color: Colors.white70),
            const SizedBox(height: 16),
            Text(_errorCamara!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _iniciarCamaras, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    final c = _controlador;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator();
    }

    // La vista previa ya muestra el filtro del rollo, con la misma matriz que se
    // aplicará a la foto final.
    final matriz = matrizDeFiltro(_rollo.filtro);
    Widget vista = CameraPreview(c);
    if (matriz != null) {
      vista = ColorFiltered(colorFilter: ColorFilter.matrix(matriz), child: vista);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            vista,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _destello ? 1 : 0,
                  duration: const Duration(milliseconds: 90),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avisoPendiente() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('La última foto no se guardó.', style: TextStyle(color: Colors.white)),
          ),
          TextButton(onPressed: _avanzando ? null : _descartarPendiente, child: const Text('Descartar')),
          TextButton(onPressed: _avanzando ? null : _reintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _barraInferior() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                MuestraFiltro(filtro: _rollo.filtro, tamano: 28),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _rollo.filtro.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          _Obturador(
            habilitado: _puedeDisparar,
            avanzando: _avanzando,
            onPressed: _disparar,
          ),
          Expanded(
            child: Text(
              _avanzando ? 'Avanzando…' : '',
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contador de fotos al estilo de una cámara de rollo: "07 / 12".
class _ContadorFotos extends StatelessWidget {
  const _ContadorFotos({required this.rollo});

  final Rollo rollo;

  @override
  Widget build(BuildContext context) {
    final tomadas = rollo.fotosTomadas.toString().padLeft(2, '0');
    return Column(
      children: [
        Text(
          '$tomadas / ${rollo.capacidad}',
          style: const TextStyle(
            color: colorAcento,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
            letterSpacing: 2,
          ),
        ),
        Text(
          rollo.fotosRestantes == 1 ? 'queda 1' : 'quedan ${rollo.fotosRestantes}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

/// Botón redondo del obturador. Mientras se guarda la foto muestra un indicador.
class _Obturador extends StatelessWidget {
  const _Obturador({required this.habilitado, required this.avanzando, required this.onPressed});

  final bool habilitado;
  final bool avanzando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tomar foto',
      enabled: habilitado,
      child: GestureDetector(
        onTap: habilitado ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: habilitado ? Colors.white : Colors.white38, width: 4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: habilitado ? Colors.white : Colors.white24,
            ),
            child: avanzando
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black54),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
