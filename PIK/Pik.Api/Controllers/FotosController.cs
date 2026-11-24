using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Services;

namespace Pik.Api.Controllers;

[ApiController]
[Authorize]
public class FotosController(
    PikDbContext db,
    RolloService rollos,
    IAlmacenamientoFotos almacen) : ControllerBase
{
    private const long TamanoMaximoBytes = 15 * 1024 * 1024; // 15 MB

    private static readonly Dictionary<string, string> TiposPermitidos =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["image/jpeg"] = ".jpg",
            ["image/png"] = ".png"
        };

    /// <summary>
    /// Sube una foto (ya con el filtro aplicado por la app) a un rollo Activo.
    /// Si es la última que cabe, el rollo se cierra solo.
    /// </summary>
    [HttpPost("api/rollos/{rolloId:guid}/fotos")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    public async Task<ActionResult<FotoSubidaRespuesta>> Subir(Guid rolloId, [FromForm] SubirFotoSolicitud solicitud)
    {
        var archivo = solicitud.Archivo;
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new ErrorRespuesta("Falta el archivo de la foto (campo \"archivo\")."));

        if (archivo.Length > TamanoMaximoBytes)
            return BadRequest(new ErrorRespuesta("La foto supera los 15 MB."));

        if (!TiposPermitidos.TryGetValue(archivo.ContentType, out var extension))
            return BadRequest(new ErrorRespuesta("Solo se aceptan fotos JPG o PNG."));

        var usuarioId = User.ObtenerUsuarioId();
        var rollo = await db.Rollos.FirstOrDefaultAsync(r => r.Id == rolloId && r.UsuarioId == usuarioId);
        if (rollo is null) return NotFound(new ErrorRespuesta("Rollo no encontrado."));

        var fechaCaptura = solicitud.FechaCapturaUtc ?? DateTime.UtcNow;
        if (fechaCaptura.Kind != DateTimeKind.Utc) fechaCaptura = fechaCaptura.ToUniversalTime();

        try
        {
            await using var contenido = archivo.OpenReadStream();
            var foto = await rollos.AgregarFotoAsync(rollo, new NuevaFoto(
                contenido,
                archivo.ContentType,
                extension,
                archivo.Length,
                solicitud.Ancho ?? 0,
                solicitud.Alto ?? 0,
                fechaCaptura));

            // No se devuelve la URL de la foto: sigue bloqueada hasta que el rollo se revele.
            return Created($"/api/rollos/{rollo.Id}/fotos", new FotoSubidaRespuesta(
                foto.Id,
                foto.NumeroEnRollo,
                RolloRespuesta.Desde(rollo, foto.NumeroEnRollo)));
        }
        catch (ReglaNegocioException ex)
        {
            return Conflict(new ErrorRespuesta(ex.Message));
        }
    }

    /// <summary>
    /// Fotos de un rollo. Antes del revelado solo devuelve el conteo y el tiempo restante;
    /// la lista de fotos va vacía.
    /// </summary>
    [HttpGet("api/rollos/{rolloId:guid}/fotos")]
    public async Task<ActionResult<FotosDeRolloRespuesta>> Listar(Guid rolloId)
    {
        var usuarioId = User.ObtenerUsuarioId();
        var dato = await db.Rollos
            .Where(r => r.Id == rolloId && r.UsuarioId == usuarioId)
            .Select(r => new { Rollo = r, Fotos = r.Fotos.Count })
            .FirstOrDefaultAsync();

        if (dato is null) return NotFound(new ErrorRespuesta("Rollo no encontrado."));

        var ahora = DateTime.UtcNow;
        var revelado = RolloService.EstaRevelado(dato.Rollo.Estado, dato.Rollo.FechaFinReveladoUtc, ahora);

        int? segundosRestantes = null;
        if (!revelado && dato.Rollo.FechaFinReveladoUtc is { } fin)
            segundosRestantes = (int)Math.Ceiling((fin - ahora).TotalSeconds);

        var fotos = new List<FotoRespuesta>();
        if (revelado)
        {
            fotos = await db.Fotos
                .Where(f => f.RolloId == rolloId)
                .OrderBy(f => f.NumeroEnRollo)
                .Select(f => new FotoRespuesta(
                    f.Id, f.NumeroEnRollo, f.Ancho, f.Alto, f.TamanoBytes,
                    f.FechaCapturaUtc, "/api/fotos/" + f.Id + "/archivo"))
                .ToListAsync();
        }

        return Ok(new FotosDeRolloRespuesta(
            RolloRespuesta.Desde(dato.Rollo, dato.Fotos),
            Bloqueado: !revelado,
            SegundosRestantes: segundosRestantes,
            Fotos: fotos));
    }

    /// <summary>
    /// Devuelve la imagen. 423 (Locked) si el rollo aún no se revela.
    /// ?descargar=true la envía como archivo descargable.
    /// </summary>
    [HttpGet("api/fotos/{id:guid}/archivo")]
    public async Task<IActionResult> Archivo(Guid id, [FromQuery] bool descargar = false)
    {
        var usuarioId = User.ObtenerUsuarioId();
        var dato = await db.Fotos
            .Where(f => f.Id == id && f.Rollo.UsuarioId == usuarioId)
            .Select(f => new
            {
                f.RutaArchivo,
                f.TipoContenido,
                f.NumeroEnRollo,
                f.Rollo.Estado,
                f.Rollo.FechaFinReveladoUtc
            })
            .FirstOrDefaultAsync();

        if (dato is null) return NotFound(new ErrorRespuesta("Foto no encontrada."));

        if (!RolloService.EstaRevelado(dato.Estado, dato.FechaFinReveladoUtc, DateTime.UtcNow))
            return StatusCode(StatusCodes.Status423Locked,
                new ErrorRespuesta("Esta foto aún se está revelando."));

        Stream contenido;
        try
        {
            contenido = almacen.AbrirLectura(dato.RutaArchivo);
        }
        catch (IOException)
        {
            return NotFound(new ErrorRespuesta("No se encontró el archivo de la foto."));
        }

        var nombre = $"pik_{dato.NumeroEnRollo:D2}{Path.GetExtension(dato.RutaArchivo)}";
        return descargar
            ? File(contenido, dato.TipoContenido, nombre, enableRangeProcessing: true)
            : File(contenido, dato.TipoContenido, enableRangeProcessing: true);
    }
}