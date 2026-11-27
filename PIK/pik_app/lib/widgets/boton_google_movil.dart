import 'package:material_ui/material_ui.dart';

/// Android/iOS: botón propio que abre el selector de cuentas de Google.
class BotonGoogle extends StatelessWidget {
  const BotonGoogle({super.key, required this.onPressed});

  /// null = deshabilitado (por ejemplo, mientras se inicia sesión).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.account_circle_outlined),
      label: const Text('Continuar con Google'),
    );
  }
}
