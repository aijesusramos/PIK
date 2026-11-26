import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/mis_rollos.dart';
import '../services/rollos_service.dart';
import 'camara_screen.dart';
import 'rollos_screen.dart';

/// Lo que se ve con la sesión iniciada: dos páginas una al lado de la otra.
///
///   [ Cámara ]  ← deslizar →  [ Mis rollos ]
///
/// Aquí se crea [MisRollos]: vive mientras haya sesión. Al cerrar sesión,
/// main.dart muestra el login, este widget se destruye y con él los rollos.
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  static const _paginaCamara = 0;
  static const _paginaRollos = 1;

  final _paginas = PageController();
  int _pagina = _paginaCamara;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _irA(int pagina) {
    _paginas.animateToPage(pagina, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MisRollos(context.read<RollosService>()),
      // PopScope: en Android, el botón "atrás" desde la galería regresa a la cámara
      // en lugar de salir de la app.
      child: PopScope(
        canPop: _pagina == _paginaCamara,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _irA(_paginaCamara);
        },
        child: PageView(
          controller: _paginas,
          onPageChanged: (p) => setState(() => _pagina = p),
          children: [
            CamaraScreen(
              visible: _pagina == _paginaCamara,
              onAbrirGaleria: () => _irA(_paginaRollos),
            ),
            RollosScreen(onVolverACamara: () => _irA(_paginaCamara)),
          ],
        ),
      ),
    );
  }
}
