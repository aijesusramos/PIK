using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Models;
using Pik.Api.Services;

namespace Pik.Api.Controllers;

/// <summary>
/// Inicio de sesión. PIK no guarda contraseñas: la identidad la confirma Google.
///   1. La app obtiene un ID token de Google (firmado por Google, dura ~1 hora).
///   2. Lo manda aquí; el servidor lo valida CON GOOGLE (firma, emisor, vencimiento y que
///      sea para nuestro Client ID).
///   3. El servidor responde con NUESTRO JWT, que la app usa en el resto de la API.
/// </summary>
[ApiController]
[Route("api/auth")]
public class AuthController(
    PikDbContext db,
    IValidadorGoogle google,
    CuentasService cuentas,
    TokenService tokens,
    ILogger<AuthController> log) : ControllerBase
{
    [HttpPost("google")]
    public async Task<ActionResult<AuthRespuesta>> Google(LoginGoogleSolicitud solicitud)
    {
        DatosGoogle? datos;
        try
        {
            datos = await google.ValidarAsync(solicitud.IdToken);
        }
        catch (InvalidOperationException ex)
        {
            // Falta Google:ClientIds en la configuración: es un error del servidor, no del usuario.
            log.LogError(ex, "Inicio de sesión con Google sin configurar.");
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new ErrorRespuesta("El inicio de sesión con Google no está configurado en el servidor."));
        }
        catch (HttpRequestException ex)
        {
            // No se pudieron descargar las llaves públicas de Google para verificar la firma.
            log.LogError(ex, "No se pudo contactar a Google para validar el token.");
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new ErrorRespuesta("No se pudo verificar tu cuenta con Google. Intenta de nuevo."));
        }

        if (datos is null)
            return Unauthorized(new ErrorRespuesta("No se pudo verificar tu cuenta de Google."));

        try
        {
            var usuario = await cuentas.IniciarConGoogleAsync(datos);
            return Ok(CrearRespuesta(usuario));
        }
        catch (ReglaNegocioException ex)
        {
            return Conflict(new ErrorRespuesta(ex.Message));
        }
    }

    /// <summary>Devuelve el usuario del token. La app lo usa para validar la sesión guardada.</summary>
    [Authorize]
    [HttpGet("yo")]
    public async Task<ActionResult<UsuarioRespuesta>> Yo()
    {
        var id = User.ObtenerUsuarioId();
        var usuario = await db.Usuarios.FindAsync(id);
        if (usuario is null) return Unauthorized();
        return Ok(new UsuarioRespuesta(usuario.Id, usuario.Email, usuario.NombreUsuario));
    }

    private AuthRespuesta CrearRespuesta(Usuario usuario)
    {
        var (token, expira) = tokens.Generar(usuario);
        return new AuthRespuesta(token, expira,
            new UsuarioRespuesta(usuario.Id, usuario.Email, usuario.NombreUsuario));
    }
}
