/// Modelos de la app. Reflejan los DTOs de la API (Contracts/Dtos.cs).
library;

/// Filtro del rollo. [api] es el texto que usa la API; [nombre], el que ve el usuario.
enum FiltroRollo {
  original('Original', 'Original', 'Colores reales, sin cambios'),
  blancoNegro('BlancoNegro', 'B&W', 'Blanco y negro clásico'),
  redBlue('RedBlue', 'Red&Blue', 'Tonos rojos y azules');

  const FiltroRollo(this.api, this.nombre, this.descripcion);

  final String api;
  final String nombre;
  final String descripcion;

  static FiltroRollo desdeApi(String valor) =>
      values.firstWhere((f) => f.api == valor);
}

enum EstadoRollo {
  activo('Activo', 'Activo'),
  enCola('EnCola', 'En cola'),
  revelando('Revelando', 'Revelando'),
  revelado('Revelado', 'Revelado');

  const EstadoRollo(this.api, this.nombre);

  final String api;
  final String nombre;

  static EstadoRollo desdeApi(String valor) =>
      values.firstWhere((e) => e.api == valor);
}

/// Capacidades permitidas y sus horas de revelado (igual que ReglasRollo.cs).
const Map<int, int> horasPorCapacidad = {6: 3, 12: 6, 24: 12};

/// Largo máximo del título de un rollo (ReglasRollo.MaxLargoTitulo).
const maxLargoTitulo = 40;

class Usuario {
  Usuario({required this.id, required this.email, required this.nombreUsuario});

  final String id;
  final String email;
  final String nombreUsuario;

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: j['id'] as String,
        email: j['email'] as String,
        nombreUsuario: j['nombreUsuario'] as String,
      );
}

class Rollo {
  Rollo({
    required this.id,
    required this.titulo,
    required this.filtro,
    required this.capacidad,
    required this.estado,
    required this.fotosTomadas,
    required this.fotosRestantes,
    required this.horasRevelado,
    required this.fechaCreacion,
    this.fechaCierre,
    this.fechaInicioRevelado,
    this.fechaFinRevelado,
  });

  final String id;

  /// Nombre que le dio el usuario (o "Rollo N" si no escribió uno).
  final String titulo;
  final FiltroRollo filtro;
  final int capacidad;
  final EstadoRollo estado;
  final int fotosTomadas;
  final int fotosRestantes;
  final int horasRevelado;
  final DateTime fechaCreacion;
  final DateTime? fechaCierre;
  final DateTime? fechaInicioRevelado;
  final DateTime? fechaFinRevelado;

  /// Tiempo que falta para terminar el revelado (null si no se está revelando).
  Duration? get tiempoRestante {
    if (estado != EstadoRollo.revelando || fechaFinRevelado == null) return null;
    final restante = fechaFinRevelado!.difference(DateTime.now());
    return restante.isNegative ? Duration.zero : restante;
  }

  factory Rollo.fromJson(Map<String, dynamic> j) => Rollo(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        filtro: FiltroRollo.desdeApi(j['filtro'] as String),
        capacidad: j['capacidad'] as int,
        estado: EstadoRollo.desdeApi(j['estado'] as String),
        fotosTomadas: j['fotosTomadas'] as int,
        fotosRestantes: j['fotosRestantes'] as int,
        horasRevelado: j['horasRevelado'] as int,
        fechaCreacion: DateTime.parse(j['fechaCreacionUtc'] as String),
        fechaCierre: _fecha(j['fechaCierreUtc']),
        fechaInicioRevelado: _fecha(j['fechaInicioReveladoUtc']),
        fechaFinRevelado: _fecha(j['fechaFinReveladoUtc']),
      );

  static DateTime? _fecha(Object? valor) =>
      valor == null ? null : DateTime.parse(valor as String);
}

/// Respuesta de la API al subir una foto (FotoSubidaRespuesta).
/// No trae la URL de la foto: sigue bloqueada hasta que el rollo se revele.
class FotoSubida {
  FotoSubida({required this.fotoId, required this.numeroEnRollo, required this.rollo});

  final String fotoId;
  final int numeroEnRollo;

  /// El rollo actualizado. Si era la última foto, ya viene en Revelando o En cola.
  final Rollo rollo;

  factory FotoSubida.fromJson(Map<String, dynamic> j) => FotoSubida(
        fotoId: j['fotoId'] as String,
        numeroEnRollo: j['numeroEnRollo'] as int,
        rollo: Rollo.fromJson(j['rollo'] as Map<String, dynamic>),
      );
}

/// Una foto revelada (FotoRespuesta).
class FotoInfo {
  FotoInfo({
    required this.id,
    required this.numeroEnRollo,
    required this.ancho,
    required this.alto,
    required this.fechaCaptura,
    required this.urlArchivo,
    required this.urlOriginal,
  });

  final String id;
  final int numeroEnRollo;
  final int ancho;
  final int alto;
  final DateTime fechaCaptura;

  /// Ruta relativa de la imagen REVELADA en la API ("/api/fotos/{id}/archivo"). Requiere el JWT.
  final String urlArchivo;

  /// Ruta de la foto original, sin filtro ("...archivo?version=original").
  final String urlOriginal;

  /// Nombre (sin extensión) al descargar: pik_01, pik_02... (igual que la API).
  String get nombreArchivo => 'pik_${numeroEnRollo.toString().padLeft(2, '0')}';

  factory FotoInfo.fromJson(Map<String, dynamic> j) => FotoInfo(
        id: j['id'] as String,
        numeroEnRollo: j['numeroEnRollo'] as int,
        ancho: j['ancho'] as int,
        alto: j['alto'] as int,
        fechaCaptura: DateTime.parse(j['fechaCapturaUtc'] as String),
        urlArchivo: j['urlArchivo'] as String,
        urlOriginal: j['urlOriginal'] as String,
      );
}

/// Fotos de un rollo (FotosDeRolloRespuesta). Si [bloqueado] es true el rollo
/// aún no se revela y [fotos] viene vacía.
class FotosDeRollo {
  FotosDeRollo({
    required this.rollo,
    required this.bloqueado,
    required this.segundosRestantes,
    required this.fotos,
  });

  final Rollo rollo;
  final bool bloqueado;
  final int? segundosRestantes;
  final List<FotoInfo> fotos;

  factory FotosDeRollo.fromJson(Map<String, dynamic> j) => FotosDeRollo(
        rollo: Rollo.fromJson(j['rollo'] as Map<String, dynamic>),
        bloqueado: j['bloqueado'] as bool,
        segundosRestantes: j['segundosRestantes'] as int?,
        fotos: (j['fotos'] as List<dynamic>)
            .map((f) => FotoInfo.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}
