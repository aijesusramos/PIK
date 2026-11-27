using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Pik.Api.Services;

namespace Pik.Api.Tests;

/// <summary>El validador REAL (con la librería de Google) y la generación de nombres.</summary>
public class ValidadorGoogleTests
{
    private const string ClientId = "123-pik.apps.googleusercontent.com";

    private static ValidadorGoogle Validador(params string[] clientIds) =>
        new(Options.Create(new GoogleOptions { ClientIds = clientIds }), NullLogger<ValidadorGoogle>.Instance);

    [Fact]
    public async Task Rechaza_algo_que_no_es_un_JWT()
    {
        Assert.Null(await Validador(ClientId).ValidarAsync("hola"));
    }

    /// <summary>
    /// Un token con el formato y los datos correctos (emisor de Google, nuestro Client ID,
    /// vigente) pero firmado con una llave que NO es de Google. Es el ataque importante:
    /// fabricar un token "de Google". Necesita internet (descarga las llaves de Google).
    /// </summary>
    [Fact]
    public async Task Rechaza_un_token_falsificado_con_otra_llave()
    {
        using var rsa = RSA.Create(2048);
        var llave = new RsaSecurityKey(rsa) { KeyId = "llave-falsa" };
        var falso = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = "https://accounts.google.com",
            Audience = ClientId,
            Subject = new ClaimsIdentity([
                new Claim("sub", "1234567890"),
                new Claim("email", "atacante@gmail.com"),
                new Claim("email_verified", "true", ClaimValueTypes.Boolean)
            ]),
            IssuedAt = DateTime.UtcNow,
            Expires = DateTime.UtcNow.AddMinutes(30),
            SigningCredentials = new SigningCredentials(llave, SecurityAlgorithms.RsaSha256)
        });

        Assert.Null(await Validador(ClientId).ValidarAsync(falso));
    }

    [Fact]
    public async Task Sin_Client_IDs_configurados_es_un_error_del_servidor()
    {
        await Assert.ThrowsAsync<InvalidOperationException>(() => Validador().ValidarAsync("x"));
    }

    [Theory]
    [InlineData("jesus.ramos@gmail.com", "jesus.ramos")]
    [InlineData("Jesús.Ramos+pik@Gmail.com", "jesus.ramos_pik")]
    [InlineData("ab@gmail.com", "usuarioab")]
    [InlineData("...@gmail.com", "usuario")]
    [InlineData("ñandú-2026@gmail.com", "nandu_2026")]
    public void NombreBase_genera_nombres_validos(string email, string esperado)
    {
        var nombre = CuentasService.NombreBase(email);
        Assert.Equal(esperado, nombre);
        Assert.InRange(nombre.Length, 3, 44);
    }
}
