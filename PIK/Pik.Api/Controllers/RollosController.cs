using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Models;
using Pik.Api.Services;

namespace Pik.Api.Controllers;

[ApiController]
[Authorize] // Todas las rutas requieren el JWT
[Route("api/rollos")]
public class RollosController(PikDbContext db, RolloService rollos) : ControllerBase
{
    /// <summary>Crea un rollo: primero el filtro, luego la capacidad. Después ya no cambian.</summary>
    [HttpPost]
    public async Task<ActionResult<RolloRespuesta>> Crear(CrearRolloSolicitud solicitud)
    {
        if (!Enum.IsDefined(typeof(CapacidadRollo), solicitud.Capacidad))
            return BadRequest(new ErrorRespuesta("La capacidad debe ser 6, 12 o 24."));

        if (!Enum.IsDefined(solicitud.Filtro))
            return BadRequest(new ErrorRespuesta("Filtro no válido. Usa Original, BlancoNegro o RedBlue."));

        try
        {
            var rollo = await rollos.CrearAsync(
                User.ObtenerUsuarioId(),
                solicitud.Filtro,
                (CapacidadRollo)solicitud.Capacidad);

            return CreatedAtAction(nameof(Obtener), new { id = rollo.Id }, RolloRespuesta.Desde(rollo, 0));
        }
        catch (ReglaNegocioException ex)
        {
            return Conflict(new ErrorRespuesta(ex.Message));
        }
    }

    /// <summary>Lista los rollos del usuario. Opcional: ?estado=Activo|EnCola|Revelando|Revelado</summary>
    [HttpGet]
    public async Task<ActionResult<List<RolloRespuesta>>> Listar([FromQuery] EstadoRollo? estado)
    {
        var usuarioId = User.ObtenerUsuarioId();

        var consulta = db.Rollos.Where(r => r.UsuarioId == usuarioId);
        if (estado is not null)
            consulta = consulta.Where(r => r.Estado == estado);

        var datos = await consulta
            .OrderByDescending(r => r.FechaCreacionUtc)
            .Select(r => new { Rollo = r, Fotos = r.Fotos.Count })
            .ToListAsync();

        return Ok(datos.Select(d => RolloRespuesta.Desde(d.Rollo, d.Fotos)).ToList());
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<RolloRespuesta>> Obtener(Guid id)
    {
        var usuarioId = User.ObtenerUsuarioId();

        var dato = await db.Rollos
            .Where(r => r.Id == id && r.UsuarioId == usuarioId)
            .Select(r => new { Rollo = r, Fotos = r.Fotos.Count })
            .FirstOrDefaultAsync();

        // 404 también si el rollo es de otro usuario: no se revela que existe.
        if (dato is null) return NotFound(new ErrorRespuesta("Rollo no encontrado."));

        return Ok(RolloRespuesta.Desde(dato.Rollo, dato.Fotos));
    }

    /// <summary>Cierre manual: el rollo pasa a Revelando, o a En cola si ya hay 3 revelándose.</summary>
    [HttpPost("{id:guid}/cerrar")]
    public async Task<ActionResult<RolloRespuesta>> Cerrar(Guid id)
    {
        var usuarioId = User.ObtenerUsuarioId();
        var rollo = await db.Rollos.FirstOrDefaultAsync(r => r.Id == id && r.UsuarioId == usuarioId);
        if (rollo is null) return NotFound(new ErrorRespuesta("Rollo no encontrado."));

        try
        {
            await rollos.CerrarAsync(rollo);
        }
        catch (ReglaNegocioException ex)
        {
            return Conflict(new ErrorRespuesta(ex.Message));
        }

        var fotos = await db.Fotos.CountAsync(f => f.RolloId == rollo.Id);
        return Ok(RolloRespuesta.Desde(rollo, fotos));
    }
}