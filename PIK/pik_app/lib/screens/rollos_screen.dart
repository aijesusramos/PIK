import 'dart:async';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/mis_rollos.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../widgets/cuerpo_camara.dart';
import '../widgets/panel_rollo.dart';
import '../widgets/tarjeta_rollo.dart';
import 'galeria_screen.dart';

/// Segunda página de la app: los rollos del usuario. Se llega deslizando desde la cámara.
///
/// Mismo cuerpo metálico que la cámara, con dos "contenedores" hundidos:
///  - **En el cuarto oscuro** (lista): los que se están revelando, con el tiempo que les
///    falta, y los que esperan en cola.
///  - **Revelados** (cuadrícula): como una mochila con compartimentos, uno por rollo.
/// El rollo activo no aparece aquí: se ve y se maneja desde la cámara.
class RollosScreen extends StatefulWidget {
  const RollosScreen({super.key, required this.onVolverACamara});

  final VoidCallback onVolverACamara;

  @override
  State<RollosScreen> createState() => _RollosScreenState();
}

class _RollosScreenState extends State<RollosScreen> {
  /// Redibuja cada 30 s para que la cuenta regresiva avance (la lista de MisRollos solo
  /// cambia cuando llega algo nuevo de la API).
  late final Timer _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  /// Revelado, o Revelando con la hora ya cumplida aunque la API aún no cambie el estado
  /// (ReveladoWorker revisa cada 30 s). El servidor valida por la hora.
  static bool _listo(Rollo r) =>
      r.estado == EstadoRollo.revelado ||
      (r.estado == EstadoRollo.revelando && r.tiempoRestante == Duration.zero);

  void _abrir(MisRollos misRollos, Rollo rollo) {
    if (_listo(rollo)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GaleriaScreen(rollo: rollo, misRollos: misRollos),
      ));
    } else {
      mostrarPanelRollo(context, misRollos, rollo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final misRollos = context.watch<MisRollos>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colorMetal,
        body: CuerpoMetalico(
          child: SafeArea(
            child: Column(
              children: [
                _barraSuperior(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: misRollos.cargar,
                    child: _cuerpo(misRollos),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barraSuperior() {
    final usuario = context.watch<AuthService>().usuario;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: IconButton(
              tooltip: 'Volver a la cámara',
              onPressed: widget.onVolverACamara,
              icon: Image.asset(
                'assets/iconos/camara.png',
                width: 36,
                height: 36,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.photo_camera_outlined, color: colorGrafito, size: 28),
              ),
            ),
          ),
          const Expanded(child: Center(child: TextoGrabado('MIS ROLLOS', tamano: 17))),
          SizedBox(
            width: 56,
            child: PopupMenuButton<String>(
              tooltip: 'Más opciones',
              icon: const Icon(Icons.more_vert, color: colorGrafito),
              onSelected: (opcion) {
                if (opcion == 'salir') context.read<AuthService>().cerrarSesion();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(usuario == null ? '' : '@${usuario.nombreUsuario}'),
                ),
                const PopupMenuItem(
                  value: 'salir',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout),
                    title: Text('Cerrar sesión'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo(MisRollos misRollos) {
    final rollos = misRollos.rollos;

    if (misRollos.cargando && rollos.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: colorGrafito));
    }

    if (misRollos.error != null && rollos.isEmpty) {
      return _Aviso(
        icono: Icons.cloud_off,
        texto: misRollos.error!,
        boton: OutlinedButton(onPressed: misRollos.cargar, child: const Text('Reintentar')),
      );
    }

    // Cuarto oscuro: primero los que se revelan (el que termina antes, arriba), luego la cola
    // en el orden en que avanzará (por fecha de cierre, igual que la API).
    final enCuarto = rollos.where((r) => !_listo(r) && r.estado != EstadoRollo.activo).toList()
      ..sort((a, b) {
        if (a.estado != b.estado) return a.estado == EstadoRollo.revelando ? -1 : 1;
        final fa = a.fechaFinRevelado ?? a.fechaCierre ?? a.fechaCreacion;
        final fb = b.fechaFinRevelado ?? b.fechaCierre ?? b.fechaCreacion;
        return fa.compareTo(fb);
      });

    // Revelados: el más reciente primero.
    final revelados = rollos.where(_listo).toList()
      ..sort((a, b) => (b.fechaFinRevelado ?? b.fechaCreacion).compareTo(a.fechaFinRevelado ?? a.fechaCreacion));

    if (enCuarto.isEmpty && revelados.isEmpty) {
      return _Aviso(
        icono: Icons.camera_roll_outlined,
        texto: 'Aún no tienes rollos revelados ni en el cuarto oscuro.\n'
            'Toma fotos en la cámara: al terminar un rollo, aparecerá aquí.',
        boton: OutlinedButton.icon(
          onPressed: widget.onVolverACamara,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Ir a la cámara'),
        ),
      );
    }

    return ListView(
      // Siempre desplazable: así "jalar para actualizar" funciona aunque quepa todo.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        const _Rotulo('EN EL CUARTO OSCURO'),
        PanelHundido(
          radio: 16,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: enCuarto.isEmpty
              ? const _Vacio('Ningún rollo revelándose.')
              : Column(
                  children: [
                    for (var i = 0; i < enCuarto.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12, color: Colors.white10),
                      _FilaRevelando(
                        rollo: enCuarto[i],
                        onTap: () => _abrir(misRollos, enCuarto[i]),
                        onLongPress: () => mostrarPanelRollo(context, misRollos, enCuarto[i]),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 20),
        const _Rotulo('REVELADOS'),
        PanelHundido(
          radio: 16,
          padding: const EdgeInsets.all(10),
          child: revelados.isEmpty
              ? const _Vacio('Cuando un rollo termine de revelarse, aparecerá aquí.')
              : GridView.builder(
                  shrinkWrap: true, // va dentro del ListView: mide lo que ocupan sus celdas
                  physics: const NeverScrollableScrollPhysics(),
                  // Celdas de hasta 190 px: 2 columnas en un teléfono, más en pantallas anchas.
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: revelados.length,
                  itemBuilder: (_, i) => _Compartimento(
                    rollo: revelados[i],
                    onTap: () => _abrir(misRollos, revelados[i]),
                    onLongPress: () => mostrarPanelRollo(context, misRollos, revelados[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Rótulo de sección grabado en el metal.
class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: TextoGrabado(texto, tamano: 11),
    );
  }
}

/// Texto para un contenedor vacío.
class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}

/// Mensaje centrado sobre el metal (sin rollos, error de red).
class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, required this.boton});

  final IconData icono;
  final String texto;
  final Widget boton;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        PanelHundido(
          radio: 16,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icono, size: 48, color: Colors.white54),
              const SizedBox(height: 16),
              Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              boton,
            ],
          ),
        ),
      ],
    );
  }
}

/// Un rollo en el cuarto oscuro: icono, título, info y cuánto le falta.
class _FilaRevelando extends StatelessWidget {
  const _FilaRevelando({required this.rollo, required this.onTap, required this.onLongPress});

  final Rollo rollo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final enCola = rollo.estado == EstadoRollo.enCola;
    final restante = rollo.tiempoRestante ?? Duration.zero;

    // Avance del revelado (0 → 1) entre el inicio y el fin.
    double? avance;
    final inicio = rollo.fechaInicioRevelado;
    final fin = rollo.fechaFinRevelado;
    if (!enCola && inicio != null && fin != null) {
      final total = fin.difference(inicio).inSeconds;
      if (total > 0) avance = (1 - restante.inSeconds / total).clamp(0.0, 1.0);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        child: Row(
          children: [
            IconoRollo(filtro: rollo.filtro, tamano: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rollo.titulo.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _Estilos.titulo,
                  ),
                  const SizedBox(height: 2),
                  Text('${rollo.filtro.nombre} · ${rollo.fotosTomadas} fotos', style: _Estilos.info),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: avance, // null en la cola: barra "en espera" animada
                      minHeight: 3,
                      color: colorAcento,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Tiempo que falta, a la derecha, como en el contador de la cámara.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(enCola ? 'EN COLA' : 'FALTAN', style: _Estilos.etiqueta),
                const SizedBox(height: 2),
                Text(
                  enCola ? '--' : _corto(restante),
                  style: enCola ? _Estilos.tiempo.copyWith(color: Colors.white30, shadows: []) : _Estilos.tiempo,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "2h 15m", "40m", "<1m": corto, para que quepa a la derecha.
  static String _corto(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m';
    return '<1m';
  }
}

/// Un compartimento de la "mochila" de revelados.
class _Compartimento extends StatelessWidget {
  const _Compartimento({required this.rollo, required this.onTap, required this.onLongPress});

  final Rollo rollo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final fecha = rollo.fechaFinRevelado;
    return Material(
      // Bolsillo un poco más claro que el fondo del contenedor, con un filo de luz arriba.
      color: const Color(0xFF2A2C30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Center(child: IconoRollo(filtro: rollo.filtro, tamano: 96))),
              Text(
                rollo.titulo.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _Estilos.titulo,
              ),
              const SizedBox(height: 3),
              Text('${rollo.filtro.nombre} · ${rollo.fotosTomadas} fotos', style: _Estilos.info),
              const SizedBox(height: 6),
              // En dos líneas: la letra expandida no cabe en media pantalla en una sola.
              const Text('REVELADO', style: _Estilos.etiqueta),
              if (fecha != null)
                Text(formatearDia(fecha), maxLines: 1, overflow: TextOverflow.ellipsis, style: _Estilos.fecha),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estilos de texto dentro de los contenedores oscuros (mismos que el contador de la cámara).
abstract final class _Estilos {
  static const titulo = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w700,
    fontSize: 11.5,
    height: 1.25,
    letterSpacing: 1.1,
    color: Colors.white,
  );

  static const info = TextStyle(fontSize: 12.5, color: Colors.white60);

  static const etiqueta = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w700,
    fontSize: 8.5,
    letterSpacing: 1.4,
    color: Colors.white38,
  );

  static const tiempo = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: colorAcento,
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [Shadow(color: Color(0x66E8A33D), blurRadius: 8)],
  );

  /// La fecha en ámbar, como la que imprimían las cámaras en la esquina de la foto.
  static const fecha = TextStyle(
    fontFamily: fuenteRotulos,
    fontWeight: FontWeight.w800,
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1,
    color: colorAcento,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
