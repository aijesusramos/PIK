import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'screens/inicio_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/fotos_service.dart';
import 'services/rollos_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final api = ApiClient();
  final auth = AuthService(api)..iniciar();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        Provider<RollosService>(create: (_) => RollosService(api)),
        Provider<FotosService>(create: (_) => FotosService(api)),
      ],
      child: const PikApp(),
    ),
  );
}

class PikApp extends StatelessWidget {
  const PikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIK',
      debugShowCheckedModeBanner: false,
      theme: temaPik,
      // La pantalla inicial depende de la sesión: cargando, login o la cámara.
      home: Consumer<AuthService>(
        builder: (context, auth, _) {
          if (auth.cargando) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return auth.autenticado ? const InicioScreen() : const LoginScreen();
        },
      ),
    );
  }
}
