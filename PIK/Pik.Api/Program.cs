using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pik.Api.Data;
using Pik.Api.Models;
using Pik.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// ---------- Base de datos (SQLite) ----------
// "Data Source=pik.db" es relativo. SQLite lo resolvería contra la carpeta desde donde se
// lanzó el proceso, mientras que la configuración y las fotos usan la carpeta del proyecto
// (ContentRootPath). Si no coinciden (p. ej. con --contentRoot), se crearía un pik.db vacío
// y parecería que se perdieron los rollos. Por eso se resuelve contra ContentRootPath.
var cadenaSqlite = new SqliteConnectionStringBuilder(
    builder.Configuration.GetConnectionString("Pik")
    ?? throw new InvalidOperationException("Falta ConnectionStrings:Pik en appsettings."));
if (!Path.IsPathRooted(cadenaSqlite.DataSource) && cadenaSqlite.DataSource != ":memory:")
    cadenaSqlite.DataSource = Path.Combine(builder.Environment.ContentRootPath, cadenaSqlite.DataSource);

builder.Services.AddDbContext<PikDbContext>(options =>
    options.UseSqlite(cadenaSqlite.ToString()));

// ---------- JWT ----------
var seccionJwt = builder.Configuration.GetSection("Jwt");
builder.Services.Configure<JwtOptions>(seccionJwt);
var jwt = seccionJwt.Get<JwtOptions>()
    ?? throw new InvalidOperationException("Falta la sección \"Jwt\" en appsettings.");

if (Encoding.UTF8.GetByteCount(jwt.Key) < 32)
    throw new InvalidOperationException("Jwt:Key debe tener al menos 32 caracteres.");

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // Conserva los nombres originales de los claims ("sub", "email"...).
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization();

// ---------- Servicios de PIK ----------
builder.Services.AddScoped<CuentasService>();

// Inicio de sesión con Google: validar el ID token que manda la app.
builder.Services.Configure<GoogleOptions>(builder.Configuration.GetSection("Google"));
builder.Services.AddSingleton<IValidadorGoogle, ValidadorGoogle>();
builder.Services.AddSingleton<TokenService>();
builder.Services.AddScoped<RolloService>();

// Fotos en carpeta privada del servidor, cifradas con AES-256-GCM.
// La clave se valida aquí: si falta o no mide 32 bytes, la API no arranca.
var seccionAlmacen = builder.Configuration.GetSection("Almacenamiento");
builder.Services.Configure<AlmacenamientoOptions>(seccionAlmacen);
var claveFotos = ClaveFotos.Desde(seccionAlmacen["ClaveCifrado"]);
builder.Services.AddSingleton<AlmacenamientoLocal>();
builder.Services.AddSingleton<IAlmacenamientoFotos>(sp =>
    new AlmacenamientoCifrado(sp.GetRequiredService<AlmacenamientoLocal>(), claveFotos));

// Revelado: tiempos y tarea en segundo plano
builder.Services.Configure<ReveladoOptions>(builder.Configuration.GetSection("Revelado"));
builder.Services.AddHostedService<ReveladoWorker>();

// ---------- CORS ----------
// Permite que la app de Flutter en el navegador (Chrome) llame a la API.
// Las apps nativas (Android/iOS) no necesitan CORS.
builder.Services.AddCors(options =>
{
    options.AddPolicy("PikApp", politica => politica
        .AllowAnyOrigin()
        .AllowAnyHeader()
        .AllowAnyMethod());
});

// ---------- Controladores ----------
builder.Services
    .AddControllers()
    // Enums como texto en JSON: "BlancoNegro", "Revelando"...
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));

builder.Services.AddOpenApi();

var app = builder.Build();

// Aplica las migraciones pendientes antes de aceptar peticiones (y antes de que arranque
// ReveladoWorker). Así una base nueva o desactualizada nunca deja la API sin tablas.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<PikDbContext>();
    var pendientes = db.Database.GetPendingMigrations().ToList();
    db.Database.Migrate();
    app.Logger.LogInformation("Base de datos: {Ruta} (migraciones aplicadas ahora: {Cantidad})",
        cadenaSqlite.DataSource, pendientes.Count);
}

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.UseCors("PikApp");

app.UseAuthentication(); // ¿quién eres? (lee el JWT)
app.UseAuthorization();  // ¿puedes hacer esto? ([Authorize])

app.MapControllers();

app.Run();

// Para las pruebas de integración (WebApplicationFactory<Program> en Pik.Api.Tests).
public partial class Program;
