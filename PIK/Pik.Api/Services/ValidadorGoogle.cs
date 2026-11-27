using Google.Apis.Auth;
using Microsoft.Extensions.Options;

namespace Pik.Api.Services;

public class GoogleOptions
{
    /// <summary>
    /// Client IDs de OAuth de PIK en Google Cloud (terminan en .apps.googleusercontent.com).
    /// El ID token solo se acepta si su "aud" (para quién se emitió) es uno de estos.
    /// En Android/iOS la app pide el token con serverClientId = el Client ID web, así que
    /// normalmente basta con el Client ID de tipo "Aplicación web".
    /// No son secretos: van dentro de la app.
    /// </summary>
    public string[] ClientIds { get; set; } = [];
}

/// <summary>Lo que nos importa de una cuenta de Google, ya verificado.</summary>
/// <param name="Sub">Id permanente de la cuenta en Google. Identifica al usuario (el correo puede cambiar).</param>
public record DatosGoogle(string Sub, string? Email, bool EmailVerificado, string? Nombre);

/// <summary>
/// Valida un ID token de Google. Es una interfaz para que las pruebas usen un validador
/// falso (no se pueden generar tokens reales de Google en una prueba).
/// </summary>
public interface IValidadorGoogle
{
    /// <summary>Devuelve los datos de la cuenta, o null si el token no es válido.</summary>
    Task<DatosGoogle?> ValidarAsync(string idToken);
}

public class ValidadorGoogle(IOptions<GoogleOptions> opciones, ILogger<ValidadorGoogle> log) : IValidadorGoogle
{
    public async Task<DatosGoogle?> ValidarAsync(string idToken)
    {
        var clientIds = opciones.Value.ClientIds.Where(c => !string.IsNullOrWhiteSpace(c)).ToArray();
        if (clientIds.Length == 0)
            throw new InvalidOperationException(
                "Falta configurar Google:ClientIds en appsettings.json (Client ID web de Google Cloud).");

        try
        {
            // La librería oficial de Google comprueba:
            //  - la firma, con las llaves públicas de Google (las descarga y las guarda en caché),
            //  - que el emisor sea accounts.google.com,
            //  - que no esté vencido (exp),
            //  - y que "aud" sea uno de NUESTROS Client IDs: un token emitido para otra
            //    app no sirve aquí aunque sea auténtico.
            var datos = await GoogleJsonWebSignature.ValidateAsync(idToken,
                new GoogleJsonWebSignature.ValidationSettings
                {
                    Audience = clientIds,
                    IssuedAtClockTolerance = TimeSpan.FromMinutes(1),
                    ExpirationTimeClockTolerance = TimeSpan.FromMinutes(1)
                });

            return new DatosGoogle(datos.Subject, datos.Email, datos.EmailVerified, datos.Name);
        }
        catch (InvalidJwtException ex)
        {
            // Token falso, vencido o de otra app. No se registra el token (es una credencial).
            log.LogWarning("ID token de Google rechazado: {Motivo}", ex.Message);
            return null;
        }
    }
}
