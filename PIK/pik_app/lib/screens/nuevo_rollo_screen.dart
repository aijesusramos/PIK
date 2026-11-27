import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import '../services/mis_rollos.dart';
import '../widgets/tarjeta_rollo.dart';

/// Crear un rollo: primero el filtro, después la capacidad (y un título opcional).
/// El filtro y la capacidad ya no cambian; el título sí se puede cambiar después.
class NuevoRolloScreen extends StatefulWidget {
  const NuevoRolloScreen({super.key, required this.misRollos});

  /// Se pasa como parámetro: esta pantalla es una ruta nueva y no hereda el provider.
  final MisRollos misRollos;

  @override
  State<NuevoRolloScreen> createState() => _NuevoRolloScreenState();
}

class _NuevoRolloScreenState extends State<NuevoRolloScreen> {
  FiltroRollo? _filtro;
  int? _capacidad;
  bool _creando = false;
  final _titulo = TextEditingController();

  /// El nombre que pondrá la API si no se escribe título ("Rollo N").
  String get _tituloPorDefecto => 'Rollo ${widget.misRollos.rollos.length + 1}';

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final filtro = _filtro;
    final capacidad = _capacidad;
    if (filtro == null || capacidad == null) return;

    setState(() => _creando = true);
    try {
      await widget.misRollos.crear(filtro, capacidad, titulo: _titulo.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_filtro == null ? '1. Elige tu rollo' : '2. Elige la capacidad'),
        leading: _filtro == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _filtro = null;
                  _capacidad = null;
                }),
              ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _filtro == null ? _pasoFiltro(tema) : _pasoCapacidad(tema),
        ),
      ),
    );
  }

  List<Widget> _pasoFiltro(ThemeData tema) => [
        Text(
          'Todas las fotos del rollo tendrán este estilo.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final filtro in FiltroRollo.values)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: IconoRollo(filtro: filtro),
              title: Text(filtro.nombre, style: tema.textTheme.titleMedium),
              subtitle: Text(filtro.descripcion),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _filtro = filtro),
            ),
          ),
      ];

  List<Widget> _pasoCapacidad(ThemeData tema) => [
        Row(
          children: [
            IconoRollo(filtro: _filtro!, tamano: 40),
            const SizedBox(width: 12),
            Text('Rollo ${_filtro!.nombre}', style: tema.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Más fotos, más tiempo de revelado.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final entrada in horasPorCapacidad.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _capacidad == entrada.key ? tema.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              selected: _capacidad == entrada.key,
              onTap: _creando ? null : () => setState(() => _capacidad = entrada.key),
              title: Text('${entrada.key} fotos', style: tema.textTheme.titleMedium),
              subtitle: Text(
                'Revelado en ${entrada.value} horas'
                '${entrada.key == 6 ? ' · express' : ''}',
              ),
              trailing: Icon(
                _capacidad == entrada.key ? Icons.check_circle : Icons.circle_outlined,
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _titulo,
          enabled: !_creando,
          maxLength: maxLargoTitulo,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Título (opcional)',
            hintText: 'Ej. Vacaciones en la playa',
            helperText: 'Si lo dejas vacío se llamará "$_tituloPorDefecto". Puedes cambiarlo después.',
          ),
          onSubmitted: (_) {
            if (_capacidad != null && !_creando) _crear();
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (_capacidad == null || _creando) ? null : _crear,
          child: _creando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Crear rollo'),
        ),
        const SizedBox(height: 8),
        Text(
          'Después de crearlo, el filtro y la capacidad ya no se pueden cambiar.',
          textAlign: TextAlign.center,
          style: tema.textTheme.bodySmall,
        ),
      ];
}
