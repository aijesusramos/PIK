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
    /// Sube una foto a un rollo Activo: la original (sin filtro) y la revelada por la app.
    /// Si es la última que cabe, el rollo se cierra solo. Reenviar el mismo id devuelve la
    /// foto ya guardada (200) en lugar de duplicarla.
    /// </summary>
    [HttpPost("api/rollos/{rolloId:guid}/fotos")]
    [RequestSizeLimit(2 * TamanoMaximoBytes + 2 * 1024 * 1024)] // dos fotos + campos
    public async Task<ActionResult<FotoSubidaRespuesta>> Subir(Guid rolloId, [FromForm] SubirFotoSolicitud solicitud)
    {
        if (solicitud.Id is not { } fotoId || fotoId == Guid.Empty)
            return BadRequest(new ErrorRespuesta("Falta el id de la foto (campo \"id\")."));

        if (Validar(solicitud.Archivo, "archivo", out var extension) is { } errorOriginal)
            return BadRequest(new ErrorRespuesta(errorOriginal));

        if (Validar(solicitud.Revelada, "revelada", out var extensionRevelada) is { } errorRevelada)
            return BadRequest(new ErrorRespuesta(errorRevelada));

        var archivo = solicitud.Archivo!;
        var revelada = solicitud.Revelada!;

        var usuarioId = User.ObtenerUsuarioId();
        var rollo = await db.Rollos.FirstOrDefaultAsync(r => r.Id == rolloId && r.UsuarioId == usuarioId);
        if (rollo is null) return NotFound(new ErrorRespuesta("Rollo no encontrado."));

        var fechaCaptura = solicitud.FechaCapturaUtc ?? DateTime.UtcNow;
        if (fechaCaptura.Kind != DateTimeKind.Utc) fechaCaptura = fechaCaptura.ToUniversalTime();

        try
        {
            await using var contenido = archivo.OpenReadStream();
            await using var contenidoRevelada = revelada.OpenReadStream();
            var (foto, creada) = await rollos.AgregarFotoAsync(rollo, new NuevaFoto(
                fotoId,
                new ArchivoNuevo(contenido, archivo.ContentType, extension, archivo.Length),
                new ArchivoNuevo(contenidoRevelada, revelada.ContentType, extensionRevelada, revelada.Length),
                solicitud.Ancho ?? 0,
                solicitud.Alto ?? 0,
                fechaCaptura));

            // No se devuelve la URL de la foto: sigue bloqueada hasta que el rollo se revele.
            var fotos = await db.Fotos.CountAsync(f => f.RolloId == rollo.Id);
            var respuesta = new FotoSubidaRespuesta(
                foto.Id,
                foto.NumeroEnRollo,
                RolloRespuesta.Desde(rollo, fotos));

            return creada
                ? Created($"/api/rollos/{rollo.Id}/fotos", respuesta)
                : Ok(respuesta); // reintento: ya estaba guardada
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
                    f.Id, f.NumeroEnRollo, f.Ancho, f.Alto, f.TamanoBytesRevelada ?? f.TamanoBytes,
                    f.FechaCapturaUtc,
                    "/api/fotos/" + f.Id + "/archivo",
                    "/api/fotos/" + f.Id + "/archivo?version=original"))
                .ToListAsync();
        }

        return Ok(new FotosDeRolloRespuesta(
            RolloRespuesta.Desde(dato.Rollo, dato.Fotos),
            Bloqueado: !revelado,
            SegundosRestantes: segundosRestantes,
            Fotos: fotos));
    }

    /// <summary>
    /// Devuelve la imagen revelada (o la original con ?version=original).
    /// 423 (Locked) si el rollo aún no se revela, para las dos versiones.
    /// ?descargar=true la envía como archivo descargable.
    /// </summary>
    [HttpGet("api/fotos/{id:guid}/archivo")]
    public async Task<IActionResult> Archivo(Guid id, [FromQuery] bool descargar = false,
        [FromQuery] string? version = null)
    {
        var original = string.Equals(version, "original", StringComparison.OrdinalIgnoreCase);
        if (version is not null && !original)
            return BadRequest(new ErrorRespuesta("version solo puede ser \"original\"."));

        var usuarioId = User.ObtenerUsuarioId();
        var dato = await db.Fotos
            .Where(f => f.Id == id && f.Rollo.UsuarioId == usuarioId)
            .Select(f => new
            {
                f.RutaArchivo,
                f.TipoContenido,
                f.RutaRevelada,
                f.TipoContenidoRevelada,
                f.NumeroEnRollo,
                f.Rollo.Estado,
                f.Rollo.FechaFinReveladoUtc
            })
            .FirstOrDefaultAsync();

        if (dato is null) return NotFound(new ErrorRespuesta("Foto no encontrada."));

        if (!RolloService.EstaRevelado(dato.Estado, dato.FechaFinReveladoUtc, DateTime.UtcNow))
            return StatusCode(StatusCodes.Status423Locked,
                new ErrorRespuesta("Esta foto aún se está revelando."));

        // Fotos subidas antes del motor de revelado no tienen revelada: se sirve la original.
        var (ruta, tipo) = original || dato.RutaRevelada is null
            ? (dato.RutaArchivo, dato.TipoContenido)
            : (dato.RutaRevelada, dato.TipoContenidoRevelada ?? dato.TipoContenido);

        Stream contenido;
        try
        {
            contenido = almacen.AbrirLectura(ruta);
        }
        catch (IOException)
        {
            return NotFound(new ErrorRespuesta("No se encontró el archivo de la foto."));
        }

        var nombre = $"pik_{dato.NumeroEnRollo:D2}{(original ? "_original" : "")}{Path.GetExtension(ruta)}";
        return descargar
            ? File(contenido, tipo, nombre, enableRangeProcessing: true)
            : File(contenido, tipo, enableRangeProcessing: true);
    }

    /// <summary>Valida un archivo de imagen del formulario. Devuelve el mensaje de error o null.</summary>
    private static string? Validar(IFormFile? archivo, string campo, out string extension)
    {
        extension = string.Empty;
        if (archivo is null || archivo.Length == 0)
            return $"Falta la imagen del campo \"{campo}\".";
        if (archivo.Length > TamanoMaximoBytes)
            return $"La imagen del campo \"{campo}\" supera los 15 MB.";
        if (!TiposPermitidos.TryGetValue(archivo.ContentType, out var ext))
            return $"La imagen del campo \"{campo}\" debe ser JPG o PNG.";
        extension = ext;
        return null;
    }
}