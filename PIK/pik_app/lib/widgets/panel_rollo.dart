import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/mis_rollos.dart';
import '../utils/formato.dart';
import 'tarjeta_rollo.dart';

/// Abre el panel inferior con la información de un rollo y sus acciones
/// (terminar si está activo, cambiar el título).
///
/// Recibe [misRollos] como parámetro porque el panel es una ruta nueva y no
/// hereda los providers de la pantalla que lo abre.
Future<void> mostrarPanelRollo(BuildContext context, MisRollos misRollos, Rollo rollo) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PanelRollo(misRollos: misRollos, rolloId: rollo.id, inicial: rollo),
  );
}

class PanelRollo extends StatefulWidget {
  const PanelRollo({super.key, required this.misRollos, required this.rolloId, required this.inicial});

  final MisRollos misRollos;
  final String rolloId;

  /// Se usa si el rollo ya no está en la lista (no debería pasar).
  final Rollo inicial;

  @override
  State<PanelRollo> createState() => _PanelRolloState();
}

class _PanelRolloState extends State<PanelRollo> {
  bool _cerrando = false;

  Rollo get _rollo {
    for (final r in widget.misRollos.rollos) {
      if (r.id == widget.rolloId) return r;
    }
    return widget.inicial;
  }

  Future<void> _terminar() async {
    final rollo = _rollo;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Terminar el rollo?'),
        content: Text(
          'Tiene ${rollo.fotosTomadas} de ${rollo.capacidad} fotos. Ya no podrás agregar más '
          'y empezará a revelarse (${rollo.horasRevelado} h, aunque no esté lleno).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Terminar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    // Se toman antes del await: después el panel ya estará cerrado.
    final navegador = Navigator.of(context);
    final mensajes = ScaffoldMessenger.of(context);
    setState(() => _cerrando = true);
    try {
      final cerrado = await widget.misRollos.cerrar(rollo);
      navegador.pop();
      mensajes.showSnackBar(SnackBar(
        content: Text(cerrado.estado == EstadoRollo.enCola
            ? '"${cerrado.titulo}" quedó en cola: ya tienes 2 rollos revelándose.'
            : '"${cerrado.titulo}" entró al cuarto oscuro. Listo en ${cerrado.horasRevelado} h.'),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _cerrando = false);
      mensajes.showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder: se redibuja cuando MisRollos avisa (p. ej. tras renombrar).
    return ListenableBuilder(
      listenable: widget.misRollos,
      builder: (context, _) {
        final rollo = _rollo;
        final tema = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconoRollo(filtro: rollo.filtro, tamano: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rollo.titulo, style: tema.textTheme.titleLarge),
                          Text('${rollo.filtro.nombre} · ${rollo.capacidad} fotos',
                              style: tema.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cambiar título',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => renombrarRollo(context, widget.misRollos, rollo),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ..._estado(rollo, tema),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _estado(Rollo rollo, ThemeData tema) {
    switch (rollo.estado) {
      case EstadoRollo.activo:
        return [
          LinearProgressIndicator(value: rollo.fotosTomadas / rollo.capacidad),
          const SizedBox(height: 8),
          Text('${rollo.fotosTomadas} de ${rollo.capacidad} fotos · '
              '${rollo.fotosRestantes == 1 ? 'queda 1' : 'quedan ${rollo.fotosRestantes}'}'),
          const SizedBox(height: 4),
          Text('Al terminarlo se revela en ${rollo.horasRevelado} h.', style: tema.textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: rollo.fotosTomadas > 0 && !_cerrando ? _terminar : null,
            icon: _cerrando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline),
            label: const Text('Terminar rollo'),
          ),
          if (rollo.fotosTomadas == 0) ...[
            const SizedBox(height: 8),
            Text('Toma al menos 1 foto para poder terminarlo.',
                textAlign: TextAlign.center, style: tema.textTheme.bodySmall),
          ],
        ];
      case EstadoRollo.revelando:
        return [
          Text('Se está revelando · listo en ${formatearDuracion(rollo.tiempoRestante ?? Duration.zero)}.'),
        ];
      case EstadoRollo.enCola:
        return [
          Text('En cola: empezará a revelarse cuando termine otro rollo '
              '(tardará ${rollo.horasRevelado} h).'),
        ];
      case EstadoRollo.revelado:
        return [
          Text(rollo.fechaFinRevelado == null
              ? 'Revelado.'
              : 'Revelado el ${formatearFecha(rollo.fechaFinRevelado!)}.'),
        ];
    }
  }
}

/// Diálogo para cambiar el título de un rollo.
Future<void> renombrarRollo(BuildContext context, MisRollos misRollos, Rollo rollo) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoRenombrar(misRollos: misRollos, rollo: rollo),
  );
}

class _DialogoRenombrar extends StatefulWidget {
  const _DialogoRenombrar({required this.misRollos, required this.rollo});

  final MisRollos misRollos;
  final Rollo rollo;

  @override
  State<_DialogoRenombrar> createState() => _DialogoRenombrarState();
}

class _DialogoRenombrarState extends State<_DialogoRenombrar> {
  late final _texto = TextEditingController(text: widget.rollo.titulo);
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final titulo = _texto.text.trim();
    if (titulo.isEmpty) {
      setState(() => _error = 'Escribe un título.');
      return;
    }
    if (titulo == widget.rollo.titulo) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.misRollos.renombrar(widget.rollo, titulo);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e.mensaje;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar título'),
      content: TextField(
        controller: _texto,
        autofocus: true,
        maxLength: maxLargoTitulo,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Título del rollo', errorText: _error),
        onSubmitted: (_) => _guardar(),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
