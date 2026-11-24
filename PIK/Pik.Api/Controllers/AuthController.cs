using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Models;
using Pik.Api.Services;

namespace Pik.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(
    PikDbContext db,
    IPasswordHasher<Usuario> hasher,
    TokenService tokens) : ControllerBase
{
    [HttpPost("registro")]
    public async Task<ActionResult<AuthRespuesta>> Registro(RegistroSolicitud solicitud)
    {
        var email = solicitud.Email.Trim().ToLowerInvariant();
        var nombre = solicitud.NombreUsuario.Trim();

        if (await db.Usuarios.AnyAsync(u => u.Email == email))
            return Conflict(new ErrorRespuesta("Ese correo ya está registrado."));

        if (await db.Usuarios.AnyAsync(u => u.NombreUsuario == nombre))
            return Conflict(new ErrorRespuesta("Ese nombre de usuario ya está en uso."));

        var usuario = new Usuario { Email = email, NombreUsuario = nombre };
        // Nunca se guarda la contraseña: solo su hash (PBKDF2 con sal, de ASP.NET Core Identity).
        usuario.PasswordHash = hasher.HashPassword(usuario, solicitud.Password);

        db.Usuarios.Add(usuario);
        await db.SaveChangesAsync();

        return Ok(CrearRespuesta(usuario));
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthRespuesta>> Login(LoginSolicitud solicitud)
    {
        var email = solicitud.Email.Trim().ToLowerInvariant();
        var usuario = await db.Usuarios.FirstOrDefaultAsync(u => u.Email == email);

        // Mismo mensaje si no existe el correo o si la contraseña es incorrecta,
        // para no revelar qué correos están registrados.
        if (usuario is null)
            return Unauthorized(new ErrorRespuesta("Correo o contraseña incorrectos."));

        var resultado = hasher.VerifyHashedPassword(usuario, usuario.PasswordHash, solicitud.Password);
        if (resultado == PasswordVerificationResult.Failed)
            return Unauthorized(new ErrorRespuesta("Correo o contraseña incorrectos."));

        if (resultado == PasswordVerificationResult.SuccessRehashNeeded)
        {
            usuario.PasswordHash = hasher.HashPassword(usuario, solicitud.Password);
            await db.SaveChangesAsync();
        }

        return Ok(CrearRespuesta(usuario));
    }

    /// <summary>Devuelve el usuario del token. Sirve para probar que el JWT funciona.</summary>
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