import 'package:google_sign_in_web/web_only.dart' as google_web;
import 'package:material_ui/material_ui.dart';

/// Web: el botón OFICIAL de Google. Google Identity Services no permite iniciar sesión
/// desde un botón propio; al tocarlo, el resultado llega por InicioGoogle.idTokens.
class BotonGoogle extends StatelessWidget {
  const BotonGoogle({super.key, required this.onPressed});

  /// Se ignora en web (el botón de Google maneja el toque). Si es null (deshabilitado),
  /// el botón se muestra atenuado y no recibe toques.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IgnorePointer(
        ignoring: onPressed == null,
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1,
          child: google_web.renderButton(
            configuration: google_web.GSIButtonConfiguration(
              theme: google_web.GSIButtonTheme.filledBlack,
              size: google_web.GSIButtonSize.large,
              text: google_web.GSIButtonText.continueWith,
              shape: google_web.GSIButtonShape.pill,
              locale: 'es',
              minimumWidth: 280,
            ),
          ),
        ),
      ),
    );
  }
}
