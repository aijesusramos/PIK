using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Models;

namespace Pik.Api.Tests;

/// <summary>POST /api/auth/google de punta a punta (con un Google falso).</summary>
public class AuthGoogleTests(FabricaPik fabrica) : IClassFixture<FabricaPik>
{
    private readonly HttpClient _cliente = fabrica.CreateClient();

    private static string Unico() => Guid.NewGuid().ToString("N")[..8];

    private Task<HttpResponseMessage> EntrarAsync(string idToken) =>
        _cliente.PostAsJsonAsync("/api/auth/google", new { idToken });

    private async Task<AuthRespuesta> EntrarOkAsync(string idToken)
    {
        var respuesta = await EntrarAsync(idToken);
        Assert.Equal(HttpStatusCode.OK, respuesta.StatusCode);
        return (await respuesta.Content.ReadFromJsonAsync<AuthRespuesta>())!;
    }

    private T ConBase<T>(Func<PikDbContext, T> accion)
    {
        using var scope = fabrica.Services.CreateScope();
        return accion(scope.ServiceProvider.GetRequiredService<PikDbContext>());
    }

    [Fact]
    public void Usa_una_base_temporal_y_nunca_la_real()
    {
        var fuente = ConBase(db => new SqliteConnectionStringBuilder(
            db.Database.GetConnectionString()).DataSource);
        Assert.Equal(fabrica.RutaBase, fuente);
    }

    [Fact]
    public async Task Token_invalido_responde_401()
    {
        var respuesta = await EntrarAsync("esto-no-es-un-token-de-google");
        Assert.Equal(HttpStatusCode.Unauthorized, respuesta.StatusCode);
    }

    [Fact]
    public async Task Cuenta_nueva_se_crea_y_nuestro_JWT_funciona()
    {
        var u = Unico();
        var auth = await EntrarOkAsync(fabrica.Google.Token($"sub-{u}", $"Nuevo.{u}@Gmail.com"));

        Assert.Equal($"nuevo.{u}@gmail.com", auth.Usuario.Email); // correo normalizado
        Assert.Equal($"nuevo.{u}", auth.Usuario.NombreUsuario);   // nombre automático

        // El JWT que emitimos sirve para el resto de la API.
        var peticion = new HttpRequestMessage(HttpMethod.Get, "/api/auth/yo");
        peticion.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var yo = await _cliente.SendAsync(peticion);
        Assert.Equal(HttpStatusCode.OK, yo.StatusCode);
    }

    [Fact]
    public async Task La_misma_cuenta_de_Google_siempre_es_el_mismo_usuario()
    {
        var u = Unico();
        var primera = await EntrarOkAsync(fabrica.Google.Token($"sub-{u}", $"misma.{u}@gmail.com"));
        // Aunque después cambie el correo de su cuenta de Google, el sub es el mismo.
        var segunda = await EntrarOkAsync(fabrica.Google.Token($"sub-{u}", $"otro.{u}@gmail.com"));

        Assert.Equal(primera.Usuario.Id, segunda.Usuario.Id);
        Assert.Equal($"otro.{u}@gmail.com", segunda.Usuario.Email); // se actualizó el correo
    }

    [Fact]
    public async Task Cuenta_anterior_con_el_mismo_correo_verificado_se_vincula_y_conserva_sus_rollos()
    {
        var u = Unico();
        var (usuarioId, rolloId) = ConBase(db =>
        {
            // Una cuenta de antes de Google (sin GoogleId) con un rollo.
            var viejo = new Usuario { Email = $"vieja.{u}@gmail.com", NombreUsuario = $"vieja{u}" };
            var rollo = new Rollo { Usuario = viejo, Titulo = "Vacaciones", Filtro = FiltroRollo.Original,
                                    Capacidad = CapacidadRollo.Seis };
            db.AddRange(viejo, rollo);
            db.SaveChanges();
            return (viejo.Id, rollo.Id);
        });

        var auth = await EntrarOkAsync(fabrica.Google.Token($"sub-{u}", $"vieja.{u}@gmail.com"));

        Assert.Equal(usuarioId, auth.Usuario.Id);
        Assert.Equal($"vieja{u}", auth.Usuario.NombreUsuario); // conserva su nombre
        Assert.Equal($"sub-{u}", ConBase(db => db.Usuarios.Find(usuarioId)!.GoogleId));
        Assert.Equal(usuarioId, ConBase(db => db.Rollos.Find(rolloId)!.UsuarioId));
    }

    [Fact]
    public async Task Correo_existente_NO_verificado_por_Google_no_se_vincula()
    {
        var u = Unico();
        ConBase(db =>
        {
            db.Usuarios.Add(new Usuario { Email = $"sinverificar.{u}@gmail.com", NombreUsuario = $"sv{u}" });
            return db.SaveChanges();
        });

        var respuesta = await EntrarAsync(
            fabrica.Google.Token($"sub-{u}", $"sinverificar.{u}@gmail.com", verificado: false));

        Assert.Equal(HttpStatusCode.Conflict, respuesta.StatusCode);
        Assert.Null(ConBase(db => db.Usuarios.Single(x => x.Email == $"sinverificar.{u}@gmail.com").GoogleId));
    }

    [Fact]
    public async Task Correo_ya_vinculado_a_otra_cuenta_de_Google_no_se_roba()
    {
        var u = Unico();
        await EntrarOkAsync(fabrica.Google.Token($"sub-a-{u}", $"duena.{u}@gmail.com"));

        // Otra cuenta de Google (otro sub) que dice tener el mismo correo.
        var respuesta = await EntrarAsync(fabrica.Google.Token($"sub-b-{u}", $"duena.{u}@gmail.com"));

        Assert.Equal(HttpStatusCode.Conflict, respuesta.StatusCode);
    }

    [Fact]
    public async Task Si_el_nombre_ya_existe_se_agrega_un_numero()
    {
        var u = Unico();
        var a = await EntrarOkAsync(fabrica.Google.Token($"sub-1-{u}", $"ana{u}@gmail.com"));
        var b = await EntrarOkAsync(fabrica.Google.Token($"sub-2-{u}", $"ana{u}@outlook.com"));
        var c = await EntrarOkAsync(fabrica.Google.Token($"sub-3-{u}", $"ana{u}@yahoo.com"));

        Assert.Equal($"ana{u}", a.Usuario.NombreUsuario);
        Assert.Equal($"ana{u}2", b.Usuario.NombreUsuario);
        Assert.Equal($"ana{u}3", c.Usuario.NombreUsuario);
    }

    [Theory]
    [InlineData("/api/auth/registro")]
    [InlineData("/api/auth/login")]
    public async Task Ya_no_existen_registro_ni_login_con_contrasena(string ruta)
    {
        var respuesta = await _cliente.PostAsJsonAsync(ruta, new { email = "a@b.com", password = "12345678" });
        Assert.Equal(HttpStatusCode.NotFound, respuesta.StatusCode);
    }
}
