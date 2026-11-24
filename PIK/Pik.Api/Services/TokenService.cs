using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Pik.Api.Models;

namespace Pik.Api.Services;

/// <summary>Valores de la sección "Jwt" de appsettings.</summary>
public class JwtOptions
{
    /// <summary>Clave secreta para firmar los tokens. Mínimo 32 caracteres.</summary>
    public string Key { get; set; } = string.Empty;
    public string Issuer { get; set; } = "Pik.Api";
    public string Audience { get; set; } = "Pik.App";
    public int ExpiracionMinutos { get; set; } = 1440; // 24 horas
}

/// <summary>Genera el JWT que la app envía en cada petición (header Authorization: Bearer ...).</summary>
public class TokenService(IOptions<JwtOptions> opciones)
{
    public (string Token, DateTime ExpiraUtc) Generar(Usuario usuario)
    {
        var o = opciones.Value;
        var expira = DateTime.UtcNow.AddMinutes(o.ExpiracionMinutos);

        var credenciales = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(o.Key)),
            SecurityAlgorithms.HmacSha256);

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = o.Issuer,
            Audience = o.Audience,
            Expires = expira,
            SigningCredentials = credenciales,
            Subject = new ClaimsIdentity(new[]
            {
                // "sub" = id del usuario. Los controladores lo leen para saber quién hace la petición.
                new Claim(JwtRegisteredClaimNames.Sub, usuario.Id.ToString()),
                new Claim(JwtRegisteredClaimNames.Email, usuario.Email),
                new Claim("nombre_usuario", usuario.NombreUsuario)
            })
        };

        var token = new JsonWebTokenHandler().CreateToken(descriptor);
        return (token, expira);
    }
}

public static class ClaimsPrincipalExtensions
{
    /// <summary>Id del usuario autenticado, tomado del claim "sub" del JWT.</summary>
    public static Guid ObtenerUsuarioId(this ClaimsPrincipal user)
    {
        var valor = user.FindFirstValue(JwtRegisteredClaimNames.Sub);
        return Guid.TryParse(valor, out var id)
            ? id
            : throw new UnauthorizedAccessException("El token no contiene un id de usuario válido.");
    }
}