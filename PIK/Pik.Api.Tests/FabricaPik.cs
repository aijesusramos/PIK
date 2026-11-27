using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Pik.Api.Services;

namespace Pik.Api.Tests;

/// <summary>
/// Levanta la API completa en memoria para las pruebas, con:
///  - una base SQLite TEMPORAL (nunca toca Pik.Api/pik.db),
///  - un validador de Google falso (no se pueden generar ID tokens reales en una prueba).
/// </summary>
public class FabricaPik : WebApplicationFactory<Program>
{
    public ValidadorGoogleFalso Google { get; } = new();

    public string RutaBase { get; } =
        Path.Combine(Path.GetTempPath(), $"pik_test_{Guid.NewGuid():N}.db");

    public FabricaPik()
    {
        // Program.cs lee la configuración al crear el builder, antes de que la fábrica pueda
        // cambiarla; las variables de entorno sí se leen en ese momento.
        Environment.SetEnvironmentVariable("ConnectionStrings__Pik", $"Data Source={RutaBase}");
        Environment.SetEnvironmentVariable("Jwt__Key", "clave-solo-para-pruebas-de-integracion-0123456789");
        Environment.SetEnvironmentVariable("Revelado__IntervaloRevisionSegundos", "3600");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureTestServices(servicios =>
        {
            servicios.RemoveAll<IValidadorGoogle>();
            servicios.AddSingleton<IValidadorGoogle>(Google);
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        SqliteConnection.ClearAllPools(); // suelta el archivo para poder borrarlo
        try { File.Delete(RutaBase); } catch (IOException) { }
    }
}

/// <summary>Google de mentira: cada "token" es una clave en un diccionario.</summary>
public class ValidadorGoogleFalso : IValidadorGoogle
{
    private readonly Dictionary<string, DatosGoogle> _tokens = new();

    /// <summary>Registra una cuenta de Google y devuelve un token que la representa.</summary>
    public string Token(string sub, string? email, bool verificado = true)
    {
        var token = $"token-{Guid.NewGuid():N}";
        _tokens[token] = new DatosGoogle(sub, email, verificado, Nombre: null);
        return token;
    }

    public Task<DatosGoogle?> ValidarAsync(string idToken) =>
        Task.FromResult(_tokens.GetValueOrDefault(idToken));
}
