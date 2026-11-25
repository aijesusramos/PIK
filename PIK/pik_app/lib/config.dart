/// Configuración de la app.
///
/// La URL de la API se puede cambiar sin tocar el código:
///   flutter run -d chrome --dart-define=API_URL=http://localhost:5292
///   flutter run --dart-define=API_URL=http://192.168.1.50:5292   (teléfono físico)
class Config {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:5292',
  );
}
