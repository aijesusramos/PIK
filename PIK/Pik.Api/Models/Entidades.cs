namespace Pik.Api.Models;

// Todas las fechas se guardan en UTC con DateTime (no DateTimeOffset),
// porque el proveedor de SQLite de EF Core no puede comparar ni ordenar
// DateTimeOffset dentro de las consultas.

public class Usuario
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Email { get; set; } = string.Empty;
    public string NombreUsuario { get; set; } = string.Empty;

    /// <summary>
    /// Id de la cuenta de Google ("sub" del ID token). Es lo que identifica al usuario al
    /// iniciar sesión: el correo de Google puede cambiar, el sub no. Null solo en cuentas
    /// de antes de Google que todavía no se han vinculado.
    /// </summary>
    public string? GoogleId { get; set; }
    public DateTime FechaRegistroUtc { get; set; } = DateTime.UtcNow;

    public List<Rollo> Rollos { get; set; } = new();
    public List<Dispositivo> Dispositivos { get; set; } = new();
    public List<Notificacion> Notificaciones { get; set; } = new();
}

public class Rollo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UsuarioId { get; set; }
    public Usuario Usuario { get; set; } = null!;

    /// <summary>Nombre que el usuario le da al rollo. Es lo único que se puede cambiar después.</summary>
    public string Titulo { get; set; } = string.Empty;

    // Se fijan al crear el rollo y no cambian.
    public FiltroRollo Filtro { get; set; }
    public CapacidadRollo Capacidad { get; set; }

    public EstadoRollo Estado { get; set; } = EstadoRollo.Activo;

    public DateTime FechaCreacionUtc { get; set; } = DateTime.UtcNow;

    /// <summary>Cuándo se llenó o el usuario lo cerró. Define el orden en la cola.</summary>
    public DateTime? FechaCierreUtc { get; set; }

    /// <summary>Cuándo empezó a correr el revelado (pasó a Revelando).</summary>
    public DateTime? FechaInicioReveladoUtc { get; set; }

    /// <summary>Cuándo termina el revelado. Antes de esta fecha las fotos están bloqueadas.</summary>
    public DateTime? FechaFinReveladoUtc { get; set; }

    public List<Foto> Fotos { get; set; } = new();
}

public class Foto
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RolloId { get; set; }
    public Rollo Rollo { get; set; } = null!;

    /// <summary>Posición dentro del rollo: de 1 a la capacidad.</summary>
    public int NumeroEnRollo { get; set; }

    // ---- Original: la foto tal como se tomó (sin filtro). Se conserva siempre. ----

    /// <summary>Ruta relativa dentro de la carpeta privada de almacenamiento (fuera de wwwroot).</summary>
    public string RutaArchivo { get; set; } = string.Empty;
    public string TipoContenido { get; set; } = "image/jpeg";
    public long TamanoBytes { get; set; }

    // ---- Revelada: la original pasada por el motor de revelado de la app (filtro del rollo). ----
    // La app la revela al capturar y la sube junto con la original; queda bloqueada igual que
    // la original hasta FechaFinReveladoUtc. Es null en fotos subidas antes de existir el motor.

    public string? RutaRevelada { get; set; }
    public string? TipoContenidoRevelada { get; set; }
    public long? TamanoBytesRevelada { get; set; }
    public int Ancho { get; set; }
    public int Alto { get; set; }

    public DateTime FechaCapturaUtc { get; set; }
    public DateTime FechaSubidaUtc { get; set; } = DateTime.UtcNow;

    // El filtro no se repite aquí: se toma del rollo.
}

public class Dispositivo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UsuarioId { get; set; }
    public Usuario Usuario { get; set; } = null!;

    /// <summary>Token de Firebase Cloud Messaging para enviar notificaciones.</summary>
    public string TokenFcm { get; set; } = string.Empty;
    public PlataformaDispositivo Plataforma { get; set; }
    public DateTime FechaRegistroUtc { get; set; } = DateTime.UtcNow;
    public DateTime UltimaActividadUtc { get; set; } = DateTime.UtcNow;
}

public class Notificacion
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UsuarioId { get; set; }
    public Usuario Usuario { get; set; } = null!;

    public Guid? RolloId { get; set; }
    public Rollo? Rollo { get; set; }

    public TipoNotificacion Tipo { get; set; }
    public string Titulo { get; set; } = string.Empty;
    public string Mensaje { get; set; } = string.Empty;

    public DateTime FechaCreacionUtc { get; set; } = DateTime.UtcNow;
    public bool Enviada { get; set; }
    public DateTime? FechaEnvioUtc { get; set; }
    public bool Leida { get; set; }
}
