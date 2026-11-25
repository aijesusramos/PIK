# PIK — Proyecto de estadía

App móvil que simula una cámara analógica con **revelado diferido**: el usuario toma fotos en un
rollo y no puede verlas hasta que el rollo se "revela" tras un tiempo.

- `Pik.Api/` — backend ASP.NET Core 10 Web API + EF Core 10 + SQLite (funciona y está probado).
- `pik_app/` — app Flutter (Android, iOS y web para pruebas en Chrome).

El autor es estudiante de Ingeniería de Software: **responder y explicar en español**, diciendo qué
se hace y por qué.

## Reglas de negocio

- Un rollo se crea eligiendo **primero el filtro** (`Original`, `BlancoNegro`, `RedBlue`) y
  **después la capacidad** (6, 12 o 24 fotos). Una vez creado, no cambia.
- Tiempo de revelado según la **capacidad** (no las fotos tomadas): 6 = 3 h, 12 = 6 h, 24 = 12 h.
- Estados: `Activo → EnCola → Revelando → Revelado`.
- Máximo **1 rollo Activo** por usuario y máximo **2 Revelando** a la vez; los demás esperan
  `EnCola` y avanzan solos (por orden de `FechaCierreUtc`). Constantes en
  `ReglasRollo.MaxRollosActivos` (1) y `ReglasRollo.MaxRollosRevelando` (2).
- El rollo se cierra al llenarse (automático al subir la última foto) o manualmente (mínimo 1 foto).
- Las fotos están bloqueadas hasta el revelado; el servidor lo valida con la hora
  (`FechaFinReveladoUtc`), no solo con el estado (`RolloService.EstaRevelado`).
- Fechas siempre en **UTC con `DateTime`** (no `DateTimeOffset`: el proveedor SQLite de EF Core no
  puede compararlas/ordenarlas en consultas). `PikDbContext` aplica convertidores que marcan
  `Kind = Utc` al leer.
- Las reglas se validan **siempre en el servidor**; la app solo las refleja.

## Backend (Pik.Api)

- `Program.cs`: SQLite, JWT Bearer (`MapInboundClaims = false`, claims `sub`, `email`,
  `nombre_usuario`), enums como texto en JSON (`JsonStringEnumConverter`), CORS (política
  `PikApp`, abierta, para la app web), OpenAPI en desarrollo.
- `Controllers/`
  - `AuthController` — `POST /api/auth/registro`, `POST /api/auth/login`, `GET /api/auth/yo`.
    Contraseñas con `PasswordHasher<Usuario>`. Mismo mensaje si el correo no existe o la
    contraseña es incorrecta.
  - `RollosController` (`[Authorize]`) — `POST /api/rollos`, `GET /api/rollos[?estado=]`,
    `GET /api/rollos/{id}`, `POST /api/rollos/{id}/cerrar`.
  - `FotosController` (`[Authorize]`) — `POST /api/rollos/{id}/fotos` (multipart: `archivo`,
    `ancho`, `alto`, `fechaCapturaUtc`; JPG/PNG ≤ 15 MB), `GET /api/rollos/{id}/fotos` (lista vacía
    + `bloqueado` + `segundosRestantes` antes del revelado), `GET /api/fotos/{id}/archivo`
    (**423 Locked** si no está revelada; `?descargar=true` para descarga).
- `Services/`
  - `RolloService` — concentra las reglas (crear, agregar foto, cerrar, procesar revelados).
    Usa transacciones (sin anidar, SQLite no lo permite). Errores de regla →
    `ReglaNegocioException` → el controlador responde **409** con `{ "mensaje": "..." }`.
  - `ReveladoWorker` (`BackgroundService`) — cada `IntervaloRevisionSegundos` termina revelados
    vencidos, crea la `Notificacion` y avanza la cola.
  - `TokenService` (JWT), `AlmacenamientoLocal` (`IAlmacenamientoFotos`).
- `Models/` — `Entidades.cs` (Usuario, Rollo, Foto, Dispositivo, Notificacion), `Enums.cs`,
  `ReglasRollo.cs` (constantes y tiempos de revelado).
- `Contracts/Dtos.cs` — DTOs (records). Nunca se exponen entidades. Errores: `ErrorRespuesta(Mensaje)`.
- Fotos en `almacenamiento/fotos/{usuarioId}/{rolloId}/{fotoId}.jpg`, **fuera de wwwroot**
  (solo accesibles por el endpoint que valida el revelado).
- Configuración: `Revelado:MinutosPorHora` = 60 en producción, **1 en desarrollo** (cada "hora"
  dura 1 minuto: un rollo de 6 se revela en 3 min). `Jwt:Key` está en
  `appsettings.Development.json` (ignorado por git).
- Corre en **http://localhost:5292** (perfil `http`). Pruebas manuales en `Pik.Api.http`.
- Migraciones EF en `Migrations/`. Ignorados por git: `pik.db*`, `almacenamiento/`.

Comandos:

```powershell
cd Pik.Api
dotnet build
dotnet run --launch-profile http
dotnet ef migrations add <Nombre>   # tras cambiar entidades
dotnet ef database update
```

## App (pik_app)

- Paquetes: `http`, `provider`, `flutter_secure_storage`.
- En Flutter 3.50 la plantilla usa `package:material_ui/material_ui.dart` (Material separado del
  framework).
- `lib/config.dart` — URL de la API con `--dart-define=API_URL=...` (por defecto
  `http://localhost:5292`). En emulador Android sería `http://10.0.2.2:5292`; en teléfono físico,
  la IP de la PC.
- `lib/api/api_client.dart` — agrega el JWT, convierte errores en `ApiException(statusCode, mensaje)`.
- `lib/services/` — `AuthService` (ChangeNotifier; guarda el token en `flutter_secure_storage`),
  `RollosService`.
- `lib/models/modelos.dart` — espejo de los DTOs (enums con su texto `api`).
- `lib/screens/` — login, registro, home (rollos por estado), nuevo rollo (filtro → capacidad).
- Pendiente: cámara (rollo Activo), galería (Revelado), filtros reales, notificaciones FCM.

## Entorno

- Windows 11, .NET 10, VS Code. Proyecto en `D:\dev\PM\PIK`, repositorio en GitHub (rama `main`).
- Flutter 3.50.1 está en `D:\dev\flutter` (hay otro SDK más viejo, 3.47, en `D:\src\flutter`; no
  usarlo). Si `flutter` no está en el PATH de la terminal, usar `D:\dev\flutter\bin\flutter.bat`.
- Si Windows bloquea `Pik.Api.exe` ("Una directiva de Control de aplicaciones bloqueó este
  archivo"), correr la API con `dotnet bin/Debug/net10.0/Pik.Api.dll` (con
  `ASPNETCORE_ENVIRONMENT=Development` y `ASPNETCORE_URLS=http://localhost:5292`).
- Aún no hay teléfono Android conectado: se prueba en Chrome con `flutter run -d chrome`.
