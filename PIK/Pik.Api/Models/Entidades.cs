namespace Pik.Api.Models;

// Todas las fechas se guardan en UTC con DateTime (no DateTimeOffset),
// porque el proveedor de SQLite de EF Core no puede comparar ni ordenar
// DateTimeOffset dentro de las consultas.

public class Usuario
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Email { get; set; } = string.Empty;
    public string NombreUsuario { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
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

    /// <summary>Ruta relativa dentro de la carpeta privada de almacenamiento (fuera de wwwroot).</summary>
    public string RutaArchivo { get; set; } = string.Empty;
    public string TipoContenido { get; set; } = "image/jpeg";
    public long TamanoBytes { get; set; }
    public int Ancho { get; set; }
    public int Alto { get; set; }

    public DateTime FechaCapturaUtc { get; set; }
    public DateTime FechaSubidaUtc { get; set; } = DateTime.UtcNow;

    // El filtro no se repite aquí: se toma del rollo.
    // La app aplica el filtro antes de subir; el servidor guarda la imagen final.
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
