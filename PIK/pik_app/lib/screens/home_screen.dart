import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/rollos_service.dart';
import '../widgets/tarjeta_rollo.dart';
import 'camara_screen.dart';
import 'nuevo_rollo_screen.dart';

/// Pantalla principal: los rollos del usuario agrupados por estado.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Rollo> _rollos = [];
  bool _cargando = true;
  String? _error;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Cada 30 s: redibuja las cuentas regresivas y, si algún revelado ya
    // terminó, vuelve a pedir la lista para mostrar el nuevo estado.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      final terminoAlguno = _rollos.any((r) => r.tiempoRestante == Duration.zero);
      if (terminoAlguno) {
        _cargar(silencioso: true);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final rollos = await context.read<RollosService>().listar();
      if (mounted) setState(() => _rollos = rollos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoRollo() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NuevoRolloScreen()),
    );
    if (creado == true) _cargar();
  }

  Future<void> _cerrarRollo(Rollo rollo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar el rollo?'),
        content: Text(
          'Tiene ${rollo.fotosTomadas} de ${rollo.capacidad} fotos. '
          'Ya no podrás agregar más y empezará a revelarse '
          '(${rollo.horasRevelado} h).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar rollo')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await context.read<RollosService>().cerrar(rollo.id);
      _cargar();
    } on ApiException catch (e) {
      _mostrarMensaje(e.mensaje);
    }
  }

  Future<void> _abrirCamara(Rollo rollo) async {
    final huboCambios = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CamaraScreen(rollo: rollo)),
    );
    if (huboCambios == true) _cargar(silencioso: true);
  }

  void _abrirRollo(Rollo rollo) {
    switch (rollo.estado) {
      case EstadoRollo.activo:
        _abrirCamara(rollo);
      case EstadoRollo.revelado:
        _mostrarMensaje('La galería llega en un paso posterior.');
      case EstadoRollo.enCola:
      case EstadoRollo.revelando:
        _mostrarMensaje('Las fotos se podrán ver cuando termine el revelado.');
    }
  }

  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final activos = _rollos.where((r) => r.estado == EstadoRollo.activo).toList();
    final enProceso = _rollos
        .where((r) => r.estado == EstadoRollo.revelando || r.estado == EstadoRollo.enCola)
        .toList();
    final revelados = _rollos.where((r) => r.estado == EstadoRollo.revelado).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${auth.usuario?.nombreUsuario ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().cerrarSesion(),
          ),
        ],
      ),
      floatingActionButton: activos.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _nuevoRollo,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo rollo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _construirCuerpo(activos, enProceso, revelados),
      ),
    );
  }

  Widget _construirCuerpo(List<Rollo> activos, List<Rollo> enProceso, List<Rollo> revelados) {
    if (_cargando && _rollos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _rollos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      );
    }

    if (_rollos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.camera_roll_outlined, size: 64),
          SizedBox(height: 16),
          Text(
            'Aún no tienes rollos.\nCrea uno para empezar a tomar fotos.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (activos.isNotEmpty) ...[
          const _Seccion('Tomando fotos'),
          for (final r in activos)
            TarjetaRollo(rollo: r, onTap: () => _abrirRollo(r), onCerrar: () => _cerrarRollo(r)),
        ],
        if (enProceso.isNotEmpty) ...[
          const _Seccion('En el cuarto oscuro'),
          for (final r in enProceso) TarjetaRollo(rollo: r, onTap: () => _abrirRollo(r)),
        ],
        if (revelados.isNotEmpty) ...[
          const _Seccion('Revelados'),
          for (final r in revelados) TarjetaRollo(rollo: r, onTap: () => _abrirRollo(r)),
        ],
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
