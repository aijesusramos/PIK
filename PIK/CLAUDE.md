# PIK — Proyecto de estadía

App móvil que simula una cámara analógica con **revelado diferido**: el usuario toma fotos en un
rollo y no puede verlas hasta que el rollo se "revela" tras un tiempo.

- `Pik.Api/` — backend ASP.NET Core 10 Web API + EF Core 10 + SQLite (funciona y está probado).
- `pik_app/` — app Flutter (Android, iOS y web para pruebas en Chrome).

El autor es estudiante de Ingeniería de Software: **responder y explicar en español**, diciendo qué
se hace y por qué.

## Reglas de negocio

- **Cuentas solo con Google** (no hay contraseñas ni registro propio). La app obtiene un ID token
  de Google, el backend lo valida CON GOOGLE y emite nuestro JWT. El usuario se identifica por el
  `sub` de Google (`Usuario.GoogleId`), no por el correo. Primera vez → se crea la cuenta con un
  nombre de usuario automático del correo ("jesus.ramos", "jesus.ramos2"...). Si ya existe una
  cuenta con ese correo: se vincula **solo si Google verificó el correo** (`email_verified`); si
  no, 409. Un correo ya vinculado a otra cuenta de Google tampoco se puede tomar (409).

- Un rollo se crea eligiendo **primero el filtro** (`Original`, `BlancoNegro`, `RedBlue`) y
  **después la capacidad** (6, 12 o 24 fotos). Filtro y capacidad no cambian después.
- Cada rollo tiene un **título** (máx. 40). Opcional al crear: vacío → "Rollo N" (N = rollos que
  el usuario ha creado + 1). Es lo **único** que se puede cambiar después (en cualquier estado).
- Tiempo de revelado según la **capacidad** (no las fotos tomadas): 6 = 3 h, 12 = 6 h, 24 = 12 h.
- Estados: `Activo → EnCola → Revelando → Revelado`.
- Máximo **1 rollo Activo** por usuario y máximo **2 Revelando** a la vez; los demás esperan
  `EnCola` y avanzan solos (por orden de `FechaCierreUtc`). Un rollo de la cola empieza a
  revelarse cuando **se liberó el lugar** (fin del rollo que terminó), no cuando corre el worker:
  tras un apagón del servidor la cola no se retrasa y puede revelarse en cadena. Un rollo cuyo
  tiempo ya pasó no ocupa lugar aunque el worker aún no lo marque (también al cerrar). Constantes en
  `ReglasRollo.MaxRollosActivos` (1) y `ReglasRollo.MaxRollosRevelando` (2).
- El rollo se cierra al llenarse (automático al subir la última foto) o manualmente (mínimo 1 foto).
- Cada foto se guarda **dos veces**: la **original** (sin filtro, se conserva siempre) y la
  **revelada** (con el look del rollo). La app la revela **al capturar** con PikEngine y sube las
  dos; el servidor las guarda bloqueadas. Así no importa si la app está cerrada cuando se cumple
  el tiempo: el "revelado" del servidor solo cambia el estado y desbloquea por la hora.
- Las fotos están bloqueadas hasta el revelado; el servidor lo valida con la hora
  (`FechaFinReveladoUtc`), no solo con el estado (`RolloService.EstaRevelado`).
- Fechas siempre en **UTC con `DateTime`** (no `DateTimeOffset`: el proveedor SQLite de EF Core no
  puede compararlas/ordenarlas en consultas). `PikDbContext` aplica convertidores que marcan
  `Kind = Utc` al leer.
- Las reglas se validan **siempre en el servidor**; la app solo las refleja.

## Backend (Pik.Api)

- `Program.cs`: SQLite (la ruta relativa `Data Source=pik.db` se resuelve contra
  `ContentRootPath`, igual que las fotos; si no, con `--contentRoot` se creaba un pik.db vacío en
  otra carpeta), **migraciones automáticas al arrancar** (`Database.Migrate()`, registra la ruta de
  la base en el log), JWT Bearer (`MapInboundClaims = false`, claims `sub`, `email`,
  `nombre_usuario`), enums como texto en JSON (`JsonStringEnumConverter`), CORS (política
  `PikApp`, abierta, para la app web), OpenAPI en desarrollo.
- `Controllers/`
  - `AuthController` — `POST /api/auth/google` (`{ "idToken" }` → `AuthRespuesta` con nuestro JWT;
    401 token inválido, 409 regla de vinculación, 503 sin configurar o sin conexión con Google),
    `GET /api/auth/yo`. (Ya no existen `/registro` ni `/login`; se eliminó `PasswordHash`.)
  - `RollosController` (`[Authorize]`) — `POST /api/rollos`, `GET /api/rollos[?estado=]`,
    `GET /api/rollos/{id}`, `PATCH /api/rollos/{id}` (renombrar: `{ "titulo" }`),
    `POST /api/rollos/{id}/cerrar`.
  - `FotosController` (`[Authorize]`) — `POST /api/rollos/{id}/fotos` (multipart: `id` (GUID
    generado por la app; reenviar el mismo id → 200 sin duplicar), `archivo` (original),
    `revelada`, `ancho`, `alto`, `fechaCapturaUtc`; JPG/PNG ≤ 15 MB cada una),
    `GET /api/rollos/{id}/fotos` (`urlArchivo` = revelada, `urlOriginal`; lista vacía
    + `bloqueado` + `segundosRestantes` antes del revelado), `GET /api/fotos/{id}/archivo`
    (revelada; `?version=original` para la original; **423 Locked** las dos si no está revelada;
    `?descargar=true` para descarga). Fotos viejas sin revelada → se sirve la original.
- `Services/`
  - `RolloService` — concentra las reglas (crear, renombrar, agregar foto, cerrar, procesar revelados).
    Usa transacciones (sin anidar, SQLite no lo permite). Errores de regla →
    `ReglaNegocioException` → el controlador responde **409** con `{ "mensaje": "..." }`.
  - `ReveladoWorker` (`BackgroundService`) — cada `IntervaloRevisionSegundos` termina revelados
    vencidos, crea la `Notificacion` y avanza la cola.
  - `TokenService` (JWT), `AlmacenamientoLocal` (`IAlmacenamientoFotos`).
  - `ValidadorGoogle` (`IValidadorGoogle`): `GoogleJsonWebSignature.ValidateAsync` (paquete
    `Google.Apis.Auth`) valida firma con las llaves de Google, emisor, vencimiento y que `aud`
    sea uno de `Google:ClientIds` (appsettings.json; el Client ID **web**, no es secreto).
  - `CuentasService`: buscar por `GoogleId` → vincular por correo verificado → crear
    (`NombreBase`: parte del correo antes de @, sin acentos, a-z 0-9 . _, mín. 3).
- `Models/` — `Entidades.cs` (Usuario, Rollo, Foto, Dispositivo, Notificacion), `Enums.cs`,
  `ReglasRollo.cs` (constantes y tiempos de revelado).
- `Contracts/Dtos.cs` — DTOs (records). Nunca se exponen entidades. Errores: `ErrorRespuesta(Mensaje)`.
- Fotos en `almacenamiento/fotos/{usuarioId}/{rolloId}/{fotoId}.jpg` (original) y
  `{fotoId}_revelada.jpg` (`Foto.RutaArchivo` / `Foto.RutaRevelada`), **fuera de wwwroot**
  (solo accesibles por el endpoint que valida el revelado; responde `Cache-Control: no-store`).
- **Fotos cifradas en reposo con AES-256-GCM** (`Services/AlmacenamientoCifrado.cs`): decorador
  de `IAlmacenamientoFotos` sobre `AlmacenamientoLocal` (RolloService y controladores no lo
  notan). Archivo = `"PIK1"` | versión de clave (1) | nonce aleatorio (12) | cifrado | tag (16);
  AAD = encabezado + ruta relativa (`RutasFotos.Relativa`), así un archivo movido o alterado no
  se descifra (`InvalidDataException` → 500). No se aceptan archivos en claro.
  Clave: `Almacenamiento:ClaveCifrado` (32 bytes Base64) **nunca en appsettings ni en el repo**:
  desarrollo con `dotnet user-secrets` (`UserSecretsId` en el csproj; se guarda en
  `%APPDATA%\Microsoft\UserSecrets\`), producción con la variable de entorno
  `Almacenamiento__ClaveCifrado`. Sin clave válida la API **no arranca** (`ClaveFotos.Desde`).
  Si se pierde la clave, se pierden las fotos: respaldarla aparte.
- Configuración: `Revelado:MinutosPorHora` = 60 en producción, **1 en desarrollo** (cada "hora"
  dura 1 minuto: un rollo de 6 se revela en 3 min). `Jwt:Key` está en
  `appsettings.Development.json` (ignorado por git).
- Corre en **http://localhost:5292** (perfil `http`). Pruebas manuales en `Pik.Api.http`.
- Migraciones EF en `Migrations/` (`Initial`, `TituloRollo`: agrega `Titulo` y numera los rollos
  existentes con SQL). La app no aplica migraciones sola: `dotnet ef database update`.
  Si la API está corriendo (exe bloqueado), usar `--configuration Release`.
  Ignorados por git: `pik.db*`, `almacenamiento/`.

Comandos:

```powershell
cd Pik.Api
dotnet build
dotnet run --launch-profile http
dotnet ef migrations add <Nombre>   # tras cambiar entidades
dotnet ef database update            # opcional: la API también migra al arrancar
dotnet user-secrets list             # debe mostrar Almacenamiento:ClaveCifrado (en otra PC: crearla)
cd ../Pik.Api.Tests
dotnet test                          # -c Release si la API está corriendo (exe bloqueado)
```

Pruebas del backend: `Pik.Api.Tests/` (xUnit + `WebApplicationFactory<Program>`). `FabricaPik`
levanta la API con una base SQLite y una carpeta de fotos **temporales** + clave de prueba
(variables de entorno, nunca toca `pik.db` ni `almacenamiento/`) y un `ValidadorGoogleFalso`.
Como las variables de entorno son globales, las clases de prueba **no corren en paralelo**
(`Configuracion.cs`). `ValidadorGoogleTests` prueba el validador real (rechaza un token
falsificado con otra llave; necesita internet). `CifradoFotosTests`: en disco no hay JPEG,
byte alterado o archivo movido → falla, clave inválida → no arranca, endpoint descifra.

## App (pik_app)

- Paquetes: `http`, `http_parser`, `provider`, `flutter_secure_storage`, `camera`, `image`, `gal`, `web`,
  `path_provider`, `image_picker` (laboratorio), `google_sign_in`, `google_sign_in_web`.
- En Flutter 3.50 la plantilla usa `package:material_ui/material_ui.dart` (Material separado del
  framework).
- `lib/config.dart` — URL de la API con `--dart-define=API_URL=...` (por defecto
  `http://localhost:5292`). En emulador Android sería `http://10.0.2.2:5292`; en teléfono físico,
  la IP de la PC.
- `lib/api/api_client.dart` — agrega el JWT, convierte errores en `ApiException(statusCode, mensaje)`.
- **Inicio de sesión con Google** (`screens/login_screen.dart`, no hay pantalla de registro; mismo
  cuerpo metálico: rollo OG, "PIK" grabado y el botón de Google dentro de un `PanelHundido`):
  `services/inicio_google.dart` envuelve `google_sign_in` 7 (`initialize` una vez; el ID token
  llega por `authenticationEvents`). Web: Google **solo permite su botón oficial**
  (`renderButton`, `widgets/boton_google_web.dart`); Android/iOS: botón propio que llama a
  `authenticate()` (`boton_google_movil.dart`); export condicional en `widgets/boton_google.dart`.
  Client IDs en `lib/config.dart` (`GOOGLE_CLIENT_ID_WEB`; en móvil se usa como `serverClientId`
  para que el `aud` sea el web; `GOOGLE_CLIENT_ID_IOS` solo para iPhone). En web la app debe
  correr en un **puerto fijo** registrado en Google: `flutter run -d chrome --web-port 7357`.
  Al cerrar sesión también se hace `signOut` en Google.
- `lib/services/` — `AuthService` (ChangeNotifier; `entrarConGoogle(idToken)`; guarda NUESTRO JWT
  en `flutter_secure_storage`, nunca el token de Google),
  `RollosService`, `FotosService`, y **`MisRollos`** (ChangeNotifier con la lista de rollos y el
  `activo`, compartido por la cámara y la galería; refresca cada 30 s). `MisRollos` se crea en
  `InicioScreen` (vive mientras hay sesión), así que las **rutas** que se abren encima
  (`NuevoRolloScreen`, `GaleriaScreen`, panel, diálogos) no lo heredan: se les pasa por parámetro.
- `lib/models/modelos.dart` — espejo de los DTOs (enums con su texto `api`).
- Navegación (con sesión): `InicioScreen` = `PageView` de 2 páginas →
  **[cámara (`camara_screen.dart`)] ⇄ deslizar ⇄ [Mis rollos (`rollos_screen.dart`)]**; también
  hay botones para ir y volver, y "atrás" en Android regresa a la cámara.
  - Cámara (pantalla principal): arriba título + contador "07 / 12" y botón a la galería; abajo
    izquierda flash (solo móvil) y cambiar cámara, centro obturador, derecha **botón del rollo**
    (muestra el filtro y fotos restantes; sin rollo es "+" → `NuevoRolloScreen`). Tocar el rollo
    abre `widgets/panel_rollo.dart`: info, **Terminar rollo** (cierre manual, ≥1 foto) y cambiar
    título. La cámara se apaga cuando no se ve (`visible`) y la página se conserva (keep-alive).
  - Mis rollos (`rollos_screen.dart`): mismo cuerpo metálico que la cámara, botón
    `assets/iconos/camara.png` para volver, "MIS ROLLOS" grabado, cerrar sesión en el menú ⋮.
    Dos `PanelHundido`: **En el cuarto oscuro** (lista: Revelando por fin más próximo con barra
    de avance y "FALTAN 2h 05m", luego EnCola) y **Revelados** (cuadrícula tipo mochila,
    `SliverGridDelegateWithMaxCrossAxisExtent` 190 px: icono, título, filtro · fotos y
    "REVELADO 24 NOV 2026" = `fechaFinRevelado`, el más reciente primero). El rollo **Activo no
    aparece** (se maneja desde la cámara). Un Revelando con la hora cumplida cuenta como
    revelado (el servidor valida por la hora). Un `Timer` de 30 s redibuja la cuenta regresiva.
    Tocar un revelado abre `galeria_screen.dart` (cuadrícula) → `visor_foto_screen.dart`
    (PageView + zoom + descargar); tocar uno del cuarto oscuro o mantener presionado abre el panel.
    `TarjetaRollo` ya no existe (`tarjeta_rollo.dart` solo tiene `IconoRollo`).
- `NuevoRolloScreen`: filtro → capacidad + título opcional (el hint muestra el "Rollo N").
- Cámara: la foto **no se muestra** al tomarla y el **visor no muestra filtro** (como una cámara
  de rollo). Una foto a la vez, con el obturador bloqueado ("Avanzando…"):
  capturar → `prepararOriginal` (`lib/fotos/preparar_foto.dart`, en `compute`: endereza por EXIF,
  reduce a 1920 px, JPEG q90 sin EXIF/GPS, **sin tocar colores**) → `id = nuevoIdFoto()` →
  `Revelador.revelar` (`services/revelador.dart`: PikEngine cargado una vez, provisto en
  `main.dart`; `Revelador.presetDe` es el único mapeo `FiltroRollo → FilmFilter`) → `FotosService.subir`
  (`FotoParaSubir`: original + revelada + id). Si falla la red, la foto queda pendiente y se
  reintenta con el **mismo id**; un 409 recarga los rollos. Si el revelado falla, no se sube nada.
  Al llenarse, la API cierra el rollo y la app avisa (Revelando o EnCola).
- **Ninguna copia en el teléfono antes del revelado:** `takePicture()` deja la captura en bruto
  (con EXIF/GPS) en un archivo temporal que el plugin nunca borra (Android `getCacheDir()/CAP*.jpg`,
  iOS `tmp/camera/pictures/CAP_*`). `fotos/borrar_captura.dart` (export condicional) la borra justo
  después de leerla (en web libera la URL `blob:`), y `limpiarCapturasViejas()` borra restos al
  abrir la cámara. No hay base local ni caché en disco; la foto pendiente de subir vive solo en
  memoria (se pierde si se cierra la app: decisión consciente para no dejar copias).
- **Diseño de la cámara** (`widgets/cuerpo_camara.dart`): `CuerpoMetalico` (metal cepillado gris
  claro: `assets/texturas/metal.png`, repetible, generada con numpy/scipy + degradado de brillo),
  `PanelHundido` (panel oscuro con bisel y sombra interior dibujada con degradados DEBAJO del
  contenido: visor, contador, compartimento del rollo, aviso de foto pendiente), `TextoGrabado`
  ("PIK" grabado) y `ReticulaVisor` (CustomPainter: esquinas de marco, marcas de tercios y centro,
  círculo de imagen partida + anillo de microprismas, ~50 % de opacidad con sombra tenue).
  Colores en `theme.dart` (`colorMetal`, `colorPanel`, `colorGrafito`). Barra de estado oscura
  (`SystemUiOverlayStyle.dark`). Botón de galería: `assets/iconos/galeria.png` (36 px; respaldo
  al icono de Material si faltara). Nombres de assets **en minúsculas** (Android y web
  distinguen mayúsculas: `galeria.PNG` no se encontraría).
- **Tipografía**: Archivo (OFL, `assets/fuentes/`), instancias fijas generadas de la variable con
  fontTools (un archivo por peso, para que el peso se respete en todas las plataformas).
  `fuenteTexto` = Archivo (toda la app, `ThemeData.fontFamily`); `fuenteRotulos` = ArchivoExpanded
  (ancho 125, 700/800) para los rótulos de la cámara.
- `IconoRollo` (`widgets/tarjeta_rollo.dart`): icono PNG del rollo de cada filtro en
  `assets/rollos/` (`original`, `blanco_negro`, `red_blue`; `filtro: null` = `vacio.png`, el botón
  de la cámara sin rollo). 450×450, fondo transparente, mismos márgenes. Se usa en la cámara
  (64), tarjetas (56), panel (72) y al crear un rollo. `IconoRollo.rutaDe` es el único mapeo.
- Flash oculto en web: las webcams no tienen "torch" y activarlo puede hacer fallar la foto.
- Permisos: Android lo declara el plugin `camera`; iOS `NSCameraUsageDescription` en Info.plist.
  `enableAudio: false` para no pedir micrófono.
- Galería: las imágenes requieren JWT, así que **no usar `Image.network`**; se bajan con
  `ApiClient.getBytes` y se muestran con `ImagenProtegida` (`Image.memory`). `CacheImagenes`
  (en `fotos_service.dart`) guarda los Future por foto mientras la galería está abierta.
- Descargar: `services/guardar_foto.dart` con export condicional → web: enlace `<a download>`
  con un Blob (paquete `web`); móvil: `Gal.putImageBytes` (nombre sin extensión). Permisos: Android
  `WRITE_EXTERNAL_STORAGE` maxSdk 29 + `requestLegacyExternalStorage`; iOS
  `NSPhotoLibrary(Add)UsageDescription`. La versión móvil aún no se ha probado en un teléfono.
- Pruebas en `test/` (`flutter test`): modelos, subida (2 archivos + id) y descarga con
  `MockClient`, caché de imágenes, `MisRollos`, login y `entrarConGoogle` (`auth_google_test.dart`),
  motor (`pik_engine_test.dart`) y revelado de
  rollos (`revelado_rollos_test.dart`: id/semilla, `prepararOriginal`, `Revelador` con el motor real).
- **Motor de revelado analógico** (conectado a los rollos: se revela al capturar, ver arriba):
  - `shaders/pik_develop.frag` (registrado en `flutter: shaders:`): LUT 3D como strip 2D →
    halation (screen) → grano gaussiano. `lib/engine/pik_engine.dart` (`PikEngine.load()`,
    `developBytes`, `develop`) y `lib/engine/film_preset.dart` (`FilmPreset.original`).
  - Reglas: el orden de los uniforms del `.frag` debe coincidir con los índices de
    `setFloat`/`setImageSampler`; los valores de `FilmPreset.original` deben ser iguales a
    `PRESET_ORIGINAL` en `tools/preview.py`.
  - LUTs en `assets/luts/` (strip PNG 1089×33 de un cubo 33³ + `.cube`), generados con
    `tools/generate_lut.py`. `tools/` son herramientas Python (numpy, Pillow, scipy), no parte de la app.
  - Web: `_decode` usa `instantiateImageCodecWithSize` (en web `ImageDescriptor` no da medidas) y
    `_encodeJpg` usa `compute` (en web no hay isolates; `Isolate.run` falla).
  - Semilla: `semillaDeFoto(id)` (`lib/engine/semilla.dart`) = primeros 8 dígitos hex del GUID
    (estable en web y móvil; no `hashCode`). El shader recibe `(seed % 997) + 0.5`; para el mismo
    grano en preview.py: `--seed` = `(semillaDeFoto(id) % 997) + 0.5` (con `seed = 1`, `1.5`).
    Validado: Flutter vs preview.py difieren en media ~0.26/255 en los tres filtros.
  - Laboratorio temporal: `flutter run -d chrome -t lib/main_lab.dart` (`lib/debug/`).
  - Pruebas: `test/pik_engine_test.dart` (el shader sí corre en `flutter test`).
    `PIK_EXPORT=<carpeta>` exporta entrada/salida para comparar con preview.py.
- Pendiente: compartir fotos, notificaciones FCM, quitar el laboratorio cuando ya no haga falta.

## Entorno

- Windows 11, .NET 10, VS Code. Proyecto en `D:\dev\PM\PIK`, repositorio en GitHub (rama `main`).
- Flutter 3.50.1 está en `D:\dev\flutter` (hay otro SDK más viejo, 3.47, en `D:\src\flutter`; no
  usarlo). Si `flutter` no está en el PATH de la terminal, usar `D:\dev\flutter\bin\flutter.bat`.
- Si Windows bloquea `Pik.Api.exe` ("Una directiva de Control de aplicaciones bloqueó este
  archivo"), correr la API con `dotnet bin/Debug/net10.0/Pik.Api.dll` (con
  `ASPNETCORE_ENVIRONMENT=Development` y `ASPNETCORE_URLS=http://localhost:5292`).
- Aún no hay teléfono Android conectado: se prueba en Chrome con
  `flutter run -d chrome --web-port 7357` (puerto fijo: es el origen autorizado en Google Cloud).
- Google Cloud (OAuth): Client ID **web** con orígenes JS `http://localhost` y
  `http://localhost:7357`; Client ID **Android** con paquete `com.example.pik_app` + SHA-1 del
  keystore de debug; Client ID **iOS** con bundle `com.example.pikApp` (+ URL scheme invertido
  en Info.plist cuando se pruebe en iPhone).

## Motor de revelado (lib/engine/)

PIK revela fotos con un motor propio en GPU. Pipeline por foto:
LUT 3D (color) → halation (resplandor) → grano gaussiano.

Archivos:
- shaders/pik_develop.frag — shader único: LUT (strip 2D 1089x33) + screen(halation) + grano
- lib/engine/pik_engine.dart — PikEngine: decodifica, arma halation en 2 pases (umbral a
  resolución completa → reducir 1/4 + blur), corre el shader, codifica JPEG con compute()
- lib/engine/film_preset.dart — FilmFilter {original, bw, redBlue} y sus FilmPreset
- assets/luts/*.png|.cube — LUTs generados (no editar a mano)
- tools/generate_lut.py — define cada look como función y genera los LUTs
- tools/preview.py — réplica en Python del shader para ajustar en la compu

Filtros (ya validados, no cambiar el look sin que lo pida):
- original: exposición baja, contraste alto, altas luces cálidas, sombras verde/azul
- redBlue: inspirado en Cinestill 800T, sombras azules, mucho resplandor rojo
- bw: inspirado en Kodak Tri-X 400, altas luces cremosas, sombras profundas

Reglas:
- El orden de uniforms en pik_develop.frag debe coincidir con los índices de
  setFloat/setImageSampler en pik_engine.dart.
- Los valores de cada FilmPreset deben ser iguales a los de tools/preview.py.
- Para cambiar el color de un filtro: editar su look_* en generate_lut.py y
  regenerar con `cd tools && python3 generate_lut.py --out ../assets/luts`.
- La app debe compilar en Android, iOS y web: no usar dart:isolate ni
  ImageDescriptor (usar compute() e instantiateImageCodecWithSize).
- Usar engine.developBytes(bytes, FilmPreset.of(filtro), seed: semillaDeFoto(foto.id));
  el seed estable hace que el grano sea igual si se revela de nuevo. En la app esto lo
  hace `Revelador.revelar` (services/revelador.dart).

Reglas de rollos: 1 rollo activo para tomar fotos, 2 revelando a la vez;
capacidad 6/12/24 fotos con revelado de 3/6/12 h; el filtro se elige al
crear el rollo y es único para todas sus fotos.