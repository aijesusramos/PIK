using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Http;
using Pik.Api.Models;

namespace Pik.Api.Contracts;

// DTOs: lo que la app envía y recibe. Nunca se exponen las entidades directamente
// (por ejemplo, para no devolver nunca el PasswordHash).

// ---------- Autenticación ----------

public record RegistroSolicitud(
    [Required, EmailAddress, MaxLength(256)] string Email,
    [Required, MinLength(3), MaxLength(50)] string NombreUsuario,
    [Required, MinLength(8), MaxLength(100)] string Password);

public record LoginSolicitud(
    [Required, EmailAddress] string Email,
    [Required] string Password);

public record AuthRespuesta(
    string Token,
    DateTime ExpiraUtc,
    UsuarioRespuesta Usuario);

public record UsuarioRespuesta(Guid Id, string Email, string NombreUsuario);

// ---------- Rollos ----------

public record CrearRolloSolicitud(
    [Required] FiltroRollo Filtro,
    [Required] int Capacidad);

public record RolloRespuesta(
    Guid Id,
    FiltroRollo Filtro,
    int Capacidad,
    EstadoRollo Estado,
    int FotosTomadas,
    int FotosRestantes,
    int HorasRevelado,
    DateTime FechaCreacionUtc,
    DateTime? FechaCierreUtc,
    DateTime? FechaInicioReveladoUtc,
    DateTime? FechaFinReveladoUtc)
{
    public static RolloRespuesta Desde(Rollo r, int fotosTomadas) => new(
        r.Id,
        r.Filtro,
        (int)r.Capacidad,
        r.Estado,
        fotosTomadas,
        (int)r.Capacidad - fotosTomadas,
        (int)ReglasRollo.TiempoRevelado(r.Capacidad).TotalHours,
        r.FechaCreacionUtc,
        r.FechaCierreUtc,
        r.FechaInicioReveladoUtc,
        r.FechaFinReveladoUtc);
}

// ---------- Fotos ----------

/// <summary>Formulario multipart para subir una foto. Es clase (no record) para el binding de [FromForm].</summary>
public class SubirFotoSolicitud
{
    /// <summary>La imagen ya con el filtro del rollo aplicado (JPG o PNG).</summary>
    public IFormFile? Archivo { get; set; }
    public int? Ancho { get; set; }
    public int? Alto { get; set; }
    /// <summary>Cuándo se tomó la foto, en UTC. Si no se envía, se usa la hora de subida.</summary>
    public DateTime? FechaCapturaUtc { get; set; }
}

public record FotoSubidaRespuesta(
    Guid FotoId,
    int NumeroEnRollo,
    RolloRespuesta Rollo);

public record FotoRespuesta(
    Guid Id,
    int NumeroEnRollo,
    int Ancho,
    int Alto,
    long TamanoBytes,
    DateTime FechaCapturaUtc,
    string UrlArchivo);

public record FotosDeRolloRespuesta(
    RolloRespuesta Rollo,
    bool Bloqueado,
    int? SegundosRestantes,
    List<FotoRespuesta> Fotos);

// ---------- Errores ----------

public record ErrorRespuesta(string Mensaje);