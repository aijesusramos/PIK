import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/mis_rollos.dart';
import '../widgets/panel_rollo.dart';
import '../widgets/tarjeta_rollo.dart';
import 'galeria_screen.dart';

/// Segunda página de la app: todos los rollos del usuario agrupados por estado.
/// Se llega deslizando desde la cámara hacia la izquierda.
class RollosScreen extends StatelessWidget {
  const RollosScreen({super.key, required this.onVolverACamara});

  final VoidCallback onVolverACamara;

  void _abrir(BuildContext context, MisRollos misRollos, Rollo rollo) {
    final listo = rollo.estado == EstadoRollo.revelado ||
        // Ya pasó la hora de fin aunque la API aún no actualice el estado
        // (ReveladoWorker revisa cada 30 s). El servidor valida por la hora.
        (rollo.estado == EstadoRollo.revelando && rollo.tiempoRestante == Duration.zero);

    if (listo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GaleriaScreen(rollo: rollo, misRollos: misRollos),
      ));
    } else if (rollo.estado == EstadoRollo.activo) {
      onVolverACamara();
    } else {
      mostrarPanelRollo(context, misRollos, rollo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final misRollos = context.watch<MisRollos>();
    final usuario = context.watch<AuthService>().usuario;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver a la cámara',
          icon: const Icon(Icons.photo_camera_outlined),
          onPressed: onVolverACamara,
        ),
        title: const Text('Mis rollos'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: misRollos.cargar,
        child: _cuerpo(context, misRollos),
      ),
    );
  }

  Widget _cuerpo(BuildContext context, MisRollos misRollos) {
    final rollos = misRollos.rollos;

    if (misRollos.cargando && rollos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (misRollos.error != null && rollos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 16),
          Text(misRollos.error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: misRollos.cargar, child: const Text('Reintentar')),
        ],
      );
    }

    if (rollos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.camera_roll_outlined, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Aún no tienes rollos.\nVuelve a la cámara y toca + para crear el primero.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onVolverACamara,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Ir a la cámara'),
          ),
        ],
      );
    }

    final activo = misRollos.activo;
    final enProceso = misRollos.enProceso;
    final revelados = misRollos.revelados;

    Widget tarjeta(Rollo r) => GestureDetector(
          // Mantener presionado: abre el panel (p. ej. para cambiar el título).
          onLongPress: () => mostrarPanelRollo(context, misRollos, r),
          child: TarjetaRollo(rollo: r, onTap: () => _abrir(context, misRollos, r)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (activo != null) ...[
          const _Seccion('Tomando fotos'),
          tarjeta(activo),
        ],
        if (enProceso.isNotEmpty) ...[
          const _Seccion('En el cuarto oscuro'),
          for (final r in enProceso) tarjeta(r),
        ],
        if (revelados.isNotEmpty) ...[
          const _Seccion('Revelados'),
          for (final r in revelados) tarjeta(r),
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
