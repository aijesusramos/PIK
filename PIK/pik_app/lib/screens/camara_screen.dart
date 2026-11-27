import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../engine/semilla.dart';
import '../fotos/borrar_captura.dart';
import '../fotos/preparar_foto.dart';
import '../models/modelos.dart';
import '../services/fotos_service.dart';
import '../services/mis_rollos.dart';
import '../services/revelador.dart';
import '../theme.dart';
import '../widgets/cuerpo_camara.dart';
import '../widgets/panel_rollo.dart';
import '../widgets/tarjeta_rollo.dart';
import 'nuevo_rollo_screen.dart';

/// Pantalla principal: la cámara.
///
///   ┌──────────────────────────────┐
///   │        Título · 07/12    [▦] │  ← ▦ abre la galería (también deslizando)
///   │           (visor)            │
///   │ [⚡][⟲]     ( ◉ )      [rollo]│  ← rollo activo, o + para crear uno
///   └──────────────────────────────┘
///
/// Como en una cámara de rollo, **la foto no se muestra al tomarla** ni el visor muestra
/// el filtro: solo avanza el contador. Cada disparo:
///   capturar → preparar la original → revelarla (PikEngine) → subir las dos → avanzar.
/// Mientras eso pasa el obturador queda bloqueado ("avanzando la película").
/// La API guarda las dos bloqueadas hasta que se cumple el tiempo de revelado.
class CamaraScreen extends StatefulWidget {
  const CamaraScreen({super.key, required this.visible, required this.onAbrirGaleria});

  /// false cuando el usuario está en la galería: la cámara se apaga.
  final bool visible;
  final VoidCallback onAbrirGaleria;

  @override
  State<CamaraScreen> createState() => _CamaraScreenState();
}

class _CamaraScreenState extends State<CamaraScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  // AutomaticKeepAlive: al deslizar a la galería, esta página no se destruye
  // (se conserva, por ejemplo, una foto pendiente de subir).
  @override
  bool get wantKeepAlive => true;

  List<CameraDescription> _camaras = [];
  int _indiceCamara = 0;
  CameraController? _controlador;
  String? _errorCamara;
  bool _appEnPrimerPlano = true;

  FlashMode _flash = FlashMode.off;

  /// En web las webcams no tienen flash, y activarlo puede hacer fallar la foto.
  final bool _flashDisponible = !kIsWeb;

  bool _avanzando = false;
  bool _destello = false;

  /// Foto ya revelada que no se pudo subir (sin red, API apagada...). Se reintenta
  /// con el mismo id, así la API no la duplica si la primera vez sí llegó.
  FotoParaSubir? _pendiente;

  bool get _debeEstarAbierta => widget.visible && _appEnPrimerPlano;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Carga el shader de revelado desde ahora, para que la primera foto no espere.
    context.read<Revelador>().precargar();
    // Borra capturas que hayan quedado en el teléfono si la app se cerró a medio disparo.
    limpiarCapturasViejas();
    if (_debeEstarAbierta) _iniciarCamaras();
  }

  @override
  void didUpdateWidget(CamaraScreen anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.visible != widget.visible) _sincronizarCamara();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlador?.dispose();
    super.dispose();
  }

  /// En el teléfono, al salir de la app se libera la cámara y al volver se abre de nuevo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return; // en web cambia de estado solo con cambiar de pestaña o ventana
    if (state == AppLifecycleState.inactive) {
      _appEnPrimerPlano = false;
    } else if (state == AppLifecycleState.resumed) {
      _appEnPrimerPlano = true;
    } else {
      return;
    }
    _sincronizarCamara();
  }

  /// Abre o cierra la cámara según si se está viendo.
  void _sincronizarCamara() {
    if (_debeEstarAbierta) {
      if (_controlador == null) {
        _camaras.isEmpty ? _iniciarCamaras() : _abrirCamara();
      }
    } else {
      final c = _controlador;
      if (c == null) return;
      setState(() => _controlador = null);
      c.dispose();
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
    final trasera = _camaras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _indiceCamara = trasera >= 0 ? trasera : 0;
    await _abrirCamara();
  }

  Future<void> _abrirCamara() async {
    final anterior = _controlador;
    if (mounted) setState(() => _controlador = null);
    await anterior?.dispose();
    if (!_debeEstarAbierta) return; // se cambió de página mientras tanto

    final c = CameraController(
      _camaras[_indiceCamara],
      ResolutionPreset.veryHigh, // 1080p; prepararOriginal reduce si llega algo más grande
      enableAudio: false, // solo fotos: así no se pide permiso de micrófono
    );
    try {
      await c.initialize();
    } on CameraException catch (e) {
      await c.dispose();
      if (mounted) setState(() => _errorCamara = _mensajeCamara(e));
      return;
    }
    if (!mounted || !_debeEstarAbierta) {
      await c.dispose();
      return;
    }
    // Android empieza con el flash en automático: se fija el modo elegido.
    if (_flashDisponible) await _aplicarFlash(c, _flash, avisar: false);
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

  /// Apagado → automático → siempre → apagado...
  Future<void> _cambiarFlash() async {
    final c = _controlador;
    if (c == null) return;
    final siguiente = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await _aplicarFlash(c, siguiente, avisar: true);
  }

  Future<void> _aplicarFlash(CameraController c, FlashMode modo, {required bool avisar}) async {
    try {
      await c.setFlashMode(modo);
      if (mounted) setState(() => _flash = modo);
    } on Exception {
      // Por ejemplo, la cámara frontal de muchos teléfonos no tiene flash.
      if (mounted) setState(() => _flash = FlashMode.off);
      if (avisar) _mostrarMensaje('Esta cámara no tiene flash.');
    }
  }

  String _mensajeCamara(CameraException e) => switch (e.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
      kIsWeb
          ? 'PIK necesita permiso para usar la cámara. Permítelo en el ícono '
                'de la cámara de la barra de direcciones y toca Reintentar.'
          : 'PIK necesita permiso para usar la cámara. Actívalo en la '
                'configuración del teléfono y toca Reintentar.',
    'cameraNotFound' => 'No se encontró ninguna cámara.',
    'cameraNotReadable' => 'La cámara está en uso por otra aplicación.',
    _ => 'No se pudo abrir la cámara (${e.description ?? e.code}).',
  };

  // ---------- Rollo ----------

  Future<void> _tocarRollo(MisRollos misRollos) async {
    final activo = misRollos.activo;
    if (activo != null) {
      await mostrarPanelRollo(context, misRollos, activo);
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => NuevoRolloScreen(misRollos: misRollos)));
    }
  }

  // ---------- Disparo ----------

  bool _listaParaDisparar(Rollo? rollo) {
    final c = _controlador;
    return rollo != null &&
        rollo.fotosRestantes > 0 &&
        c != null &&
        c.value.isInitialized &&
        !c.value.isTakingPicture &&
        !_avanzando &&
        _pendiente == null;
  }

  Future<void> _disparar() async {
    final misRollos = context.read<MisRollos>();
    final fotos = context.read<FotosService>();
    final revelador = context.read<Revelador>();
    final rollo = misRollos.activo;

    if (rollo == null) {
      _mostrarMensaje('Primero crea un rollo: toca el botón + de la derecha.');
      return;
    }
    if (!_listaParaDisparar(rollo)) return;
    final c = _controlador!;

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
      final Uint8List bytes;
      try {
        bytes = await archivo.readAsBytes();
      } finally {
        // El plugin dejó la captura en bruto (con EXIF y GPS) en un archivo temporal:
        // se borra ya, para que no quede ninguna copia en el teléfono antes del revelado.
        await borrarCaptura(archivo);
      }

      // 1. La original: enderezada, reducida y sin EXIF. En el teléfono, compute lo hace
      //    en otro hilo (isolate) para que la interfaz no se congele; en web, en el mismo.
      final original = await compute(prepararOriginal, bytes);

      // 2. El id se genera aquí porque es la semilla del grano al revelar.
      final id = nuevoIdFoto();
      final revelada = await revelador.revelar(original.bytes, rollo.filtro, id);

      // 3. Se suben las dos.
      await _subir(
        misRollos,
        fotos,
        FotoParaSubir(id: id, rolloId: rollo.id, original: original, revelada: revelada, fechaCaptura: fecha),
      );
    } on CameraException catch (e) {
      _mostrarMensaje('No se pudo tomar la foto (${e.description ?? e.code}).');
    } on FormatException catch (e) {
      _mostrarMensaje(e.message);
    } catch (e) {
      // _subir ya maneja los errores de la API; lo que llega aquí es del revelado
      // (por ejemplo, el shader no cargó). No se sube una foto sin revelar.
      _mostrarMensaje('No se pudo revelar la foto: $e');
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  Future<void> _reintentar() async {
    final misRollos = context.read<MisRollos>();
    final fotos = context.read<FotosService>();
    final foto = _pendiente;
    final rollo = misRollos.activo;
    if (foto == null || _avanzando) return;
    if (rollo == null || rollo.id != foto.rolloId) {
      // El rollo ya no está activo: la foto ya no tiene dónde guardarse.
      _descartarPendiente();
      _mostrarMensaje('El rollo de esa foto ya se cerró.');
      return;
    }
    setState(() => _avanzando = true);
    try {
      await _subir(misRollos, fotos, foto);
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  void _descartarPendiente() => setState(() => _pendiente = null);

  Future<void> _subir(MisRollos misRollos, FotosService fotos, FotoParaSubir foto) async {
    try {
      final subida = await fotos.subir(foto);
      misRollos.actualizar(subida.rollo); // la galería también se entera
      if (!mounted) return;
      _descartarPendiente();
      // Era la última foto: la API ya cerró el rollo.
      if (subida.rollo.estado != EstadoRollo.activo) await _rolloCompleto(subida.rollo);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // El rollo ya no acepta fotos (se cerró o se llenó desde otro lado).
        _descartarPendiente();
        misRollos.cargar();
        _mostrarMensaje('No se guardó la foto: ${e.mensaje}');
        return;
      }
      setState(() => _pendiente = foto);
      _mostrarMensaje('No se pudo guardar la foto: ${e.mensaje}');
    }
  }

  Future<void> _rolloCompleto(Rollo rollo) {
    final mensaje = rollo.estado == EstadoRollo.enCola
        ? 'Ya tienes 2 rollos revelándose, así que "${rollo.titulo}" quedó en cola. '
              'Empezará a revelarse solo cuando termine uno (tardará ${rollo.horasRevelado} h).'
        : '"${rollo.titulo}" ya está en el cuarto oscuro. Tus fotos estarán listas en '
              '${rollo.horasRevelado} h.';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¡Rollo completo!'),
        content: Text(mensaje),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  void _mostrarMensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    super.build(context); // requerido por AutomaticKeepAliveClientMixin
    final misRollos = context.watch<MisRollos>();
    final activo = misRollos.activo;

    // Fondo claro: los iconos de la barra de estado (hora, batería) van oscuros.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colorMetal,
        body: CuerpoMetalico(
          child: SafeArea(
            child: Column(
              children: [
                _barraSuperior(activo),
                // La "ventana" del visor: un panel hundido en el cuerpo de la cámara.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: PanelHundido(
                      radio: 18,
                      padding: const EdgeInsets.all(6),
                      fondo: const Color(0xFF0C0D0E),
                      child: SizedBox.expand(child: Center(child: _visor())),
                    ),
                  ),
                ),
                if (_pendiente != null) _avisoPendiente(),
                _barraInferior(misRollos, activo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barraSuperior(Rollo? activo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Row(
        children: [
          // Marca grabada en el metal; mide lo mismo que el botón de la derecha, así el
          // contador queda centrado.
          const SizedBox(
            width: 64,
            child: Align(alignment: Alignment.centerLeft, child: TextoGrabado('PIK', tamano: 16)),
          ),
          Expanded(
            child: Center(
              child: PanelHundido(
                radio: 10,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: _ContadorFotos(rollo: activo),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: _BotonGaleria(onPressed: widget.onAbrirGaleria),
            ),
          ),
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
            Text(
              _errorCamara!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
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

    // El visor muestra la escena sin filtro, como una cámara de rollo real:
    // el look del filtro solo se descubre al revelar.
    final vista = CameraPreview(c);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          vista,
          // Retícula del visor (fija: RepaintBoundary evita redibujarla con cada cuadro).
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: ReticulaVisor())),
            ),
          ),
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
    );
  }

  Widget _avisoPendiente() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: PanelHundido(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
      ),
    );
  }

  Widget _barraInferior(MisRollos misRollos, Rollo? activo) {
    final hayCamara = _controlador?.value.isInitialized ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        children: [
          // Izquierda: controles de la cámara.
          Expanded(
            child: Row(
              children: [
                if (_flashDisponible)
                  IconButton(
                    tooltip: switch (_flash) {
                      FlashMode.auto => 'Flash automático',
                      FlashMode.always => 'Flash encendido',
                      _ => 'Flash apagado',
                    },
                    color: colorGrafito,
                    onPressed: hayCamara && !_avanzando ? _cambiarFlash : null,
                    icon: Icon(switch (_flash) {
                      FlashMode.auto => Icons.flash_auto,
                      FlashMode.always => Icons.flash_on,
                      _ => Icons.flash_off,
                    }),
                  ),
                if (_camaras.length > 1)
                  IconButton(
                    tooltip: 'Cambiar cámara',
                    color: colorGrafito,
                    onPressed: _avanzando ? null : _cambiarCamara,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
              ],
            ),
          ),
          _Obturador(habilitado: _listaParaDisparar(activo), avanzando: _avanzando, onPressed: _disparar),
          // Derecha: el rollo activo, o + para crear uno.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _BotonRollo(
                rollo: activo,
                cargando: misRollos.cargando,
                onPressed: _avanzando ? null : () => _tocarRollo(misRollos),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título del rollo y contador de fotos al estilo de una cámara de rollo: "07 / 12".
/// Va dentro de un panel hundido, como la ventanita del contador de una cámara.
class _ContadorFotos extends StatelessWidget {
  const _ContadorFotos({required this.rollo});

  final Rollo? rollo;

  static const _estiloTitulo = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w700,
    fontSize: 10.5,
    letterSpacing: 1.6,
    color: Colors.white60,
  );

  static const _estiloContador = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w800,
    fontSize: 24,
    height: 1.15,
    letterSpacing: 1.5,
    color: colorAcento,
    // Los números ocupan lo mismo (07 → 08 no "brinca") y brillan un poco, como un LED.
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [Shadow(color: Color(0x66E8A33D), blurRadius: 8)],
  );

  @override
  Widget build(BuildContext context) {
    final r = rollo;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (r?.titulo ?? 'Sin rollo').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _estiloTitulo,
          ),
          Text(
            r == null ? '-- / --' : '${r.fotosTomadas.toString().padLeft(2, '0')} / ${r.capacidad}',
            style: r == null ? _estiloContador.copyWith(color: Colors.white24, shadows: []) : _estiloContador,
          ),
        ],
      ),
    );
  }
}

/// Botón de la galería ("Mis rollos"). Usa assets/iconos/galeria.png si existe; si no,
/// el icono de Material.
class _BotonGaleria extends StatelessWidget {
  const _BotonGaleria({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Mis rollos',
      onPressed: onPressed,
      icon: Image.asset(
        'assets/iconos/galeria.png',
        width: 36,
        height: 36,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const Icon(Icons.photo_library_outlined, color: colorGrafito, size: 28),
      ),
    );
  }
}

/// Botón del rollo (abajo a la derecha): muestra el filtro del rollo activo y
/// cuántas fotos quedan; sin rollo es un "+" para crear uno.
class _BotonRollo extends StatelessWidget {
  const _BotonRollo({required this.rollo, required this.cargando, required this.onPressed});

  final Rollo? rollo;
  final bool cargando;
  final VoidCallback? onPressed;

  /// El rollo es más ancho que alto y el PNG trae margen: se dibuja un poco más grande que
  /// el resto de los botones (flash, cambiar cámara) para que se vea del mismo peso.
  static const _tamanoIcono = 64.0;

  @override
  Widget build(BuildContext context) {
    final r = rollo;
    final Widget icono = r == null && cargando
        ? const SizedBox(
            width: _tamanoIcono,
            height: _tamanoIcono,
            child: Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        // Sin rollo: el rollo vacío (con un "+" dibujado), toca para crear uno.
        : IconoRollo(filtro: r?.filtro, tamano: _tamanoIcono);

    // El rollo va en un "compartimento" hundido en el cuerpo, como la ventanita de la tapa
    // trasera de una cámara por la que se ve qué rollo está cargado.
    final contenido = Stack(
      clipBehavior: Clip.none,
      children: [
        PanelHundido(
          radio: 14,
          padding: const EdgeInsets.all(2),
          fondo: const Color(0xFF2A2C2F),
          child: icono,
        ),
        if (r != null)
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorAcento,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: Text(
                '${r.fotosRestantes}',
                style: const TextStyle(
                  fontFamily: fuenteRotulos,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: Colors.black,
                ),
              ),
            ),
          ),
      ],
    );

    return Tooltip(
      message: r == null ? 'Nuevo rollo' : '${r.titulo}: quedan ${r.fotosRestantes}',
      child: Semantics(
        button: true,
        label: r == null ? 'Crear un rollo nuevo' : 'Rollo ${r.titulo}',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.all(6), child: contenido),
        ),
      ),
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
        // Se llama aunque esté deshabilitado: así puede explicar por qué (p. ej. sin rollo).
        onTap: onPressed,
        // Anillo de grafito con un botón cromado al centro, como el disparador de una cámara.
        child: Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(7),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF45484C), Color(0xFF1A1B1D)],
            ),
            boxShadow: [
              BoxShadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(0, 3)),
              BoxShadow(color: Color(0x99FFFFFF), offset: Offset(0, -1)), // filo con luz
            ],
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x66000000)),
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4), // brillo arriba a la izquierda
                radius: 1.1,
                colors: habilitado
                    ? const [Color(0xFFFFFFFF), Color(0xFFD5D7DA), Color(0xFFA2A5A9)]
                    : const [Color(0xFF8C8F93), Color(0xFF6E7175), Color(0xFF55585C)],
              ),
            ),
            child: avanzando
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3, color: colorGrafito),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
