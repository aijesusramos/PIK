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

  /// Client ID de OAuth de tipo "Aplicación web" (Google Cloud → Credenciales).
  /// Lo usan las tres plataformas:
  ///  - web: es el clientId del botón de Google.
  ///  - Android/iOS: es el serverClientId, así el ID token sale emitido para ESTE id
  ///    (su "aud"), que es el que valida el backend (Google:ClientIds en appsettings.json).
  /// No es secreto: va dentro de la app. Pégalo en defaultValue o usa --dart-define.
  static const googleClientIdWeb = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_WEB',
    defaultValue: '927237498082-hj00b2snaesb58rabhs4a4ap9qop77dt.apps.googleusercontent.com',
  );

  /// Client ID de OAuth de tipo "iOS". Solo hace falta para correr en iPhone.
  static const googleClientIdIos = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_IOS',
    defaultValue: '',
  );
}
