using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pik.Api.Data;
using Pik.Api.Models;
using Pik.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// ---------- Base de datos (SQLite) ----------
builder.Services.AddDbContext<PikDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("Pik")));

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
builder.Services.AddScoped<IPasswordHasher<Usuario>, PasswordHasher<Usuario>>();
builder.Services.AddSingleton<TokenService>();
builder.Services.AddScoped<RolloService>();

// Fotos en carpeta privada del servidor
builder.Services.Configure<AlmacenamientoOptions>(builder.Configuration.GetSection("Almacenamiento"));
builder.Services.AddSingleton<IAlmacenamientoFotos, AlmacenamientoLocal>();

// Revelado: tiempos y tarea en segundo plano
builder.Services.Configure<ReveladoOptions>(builder.Configuration.GetSection("Revelado"));
builder.Services.AddHostedService<ReveladoWorker>();

// ---------- Controladores ----------
builder.Services
    .AddControllers()
    // Enums como texto en JSON: "BlancoNegro", "Revelando"...
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));

builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.UseAuthentication(); // ¿quién eres? (lee el JWT)
app.UseAuthorization();  // ¿puedes hacer esto? ([Authorize])

app.MapControllers();

app.Run();