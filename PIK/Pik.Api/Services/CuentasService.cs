using System.Text;
using Microsoft.EntityFrameworkCore;
using Pik.Api.Data;
using Pik.Api.Models;

namespace Pik.Api.Services;

/// <summary>Inicio de sesión con Google: encontrar, vincular o crear la cuenta de PIK.</summary>
public class CuentasService(PikDbContext db)
{
    private const int LargoMinimoUsuario = 3;
    private const int LargoMaximoUsuario = 50;

    /// <summary>
    /// Devuelve el usuario de PIK para una cuenta de Google ya validada:
    ///  1. Si ya entró antes con Google → por su id de Google (sub), que nunca cambia.
    ///  2. Si existe una cuenta con ese correo (de antes de Google) y Google VERIFICÓ el
    ///     correo → se vincula: conserva sus rollos.
    ///  3. Si no existe → se crea, con un nombre de usuario generado del correo.
    /// Lanza ReglaNegocioException si el correo ya tiene cuenta pero Google no lo verificó
    /// (vincular sin verificar permitiría quedarse con la cuenta de otra persona).
    /// </summary>
    public async Task<Usuario> IniciarConGoogleAsync(DatosGoogle google)
    {
        var porGoogle = await db.Usuarios.FirstOrDefaultAsync(u => u.GoogleId == google.Sub);
        if (porGoogle is not null)
        {
            // El correo de la cuenta de Google pudo cambiar: se actualiza si no lo usa otra cuenta.
            await ActualizarEmailAsync(porGoogle, google);
            return porGoogle;
        }

        if (string.IsNullOrWhiteSpace(google.Email))
            throw new ReglaNegocioException("Tu cuenta de Google no compartió un correo. Intenta con otra cuenta.");

        var email = google.Email.Trim().ToLowerInvariant();
        var porEmail = await db.Usuarios.FirstOrDefaultAsync(u => u.Email == email);
        if (porEmail is not null)
        {
            if (!google.EmailVerificado)
                throw new ReglaNegocioException(
                    "Ese correo ya tiene una cuenta en PIK y Google no lo ha verificado.");

            if (porEmail.GoogleId is not null)
                throw new ReglaNegocioException("Ese correo ya está vinculado a otra cuenta de Google.");

            porEmail.GoogleId = google.Sub;
            await db.SaveChangesAsync();
            return porEmail;
        }

        var usuario = new Usuario
        {
            GoogleId = google.Sub,
            Email = email,
            NombreUsuario = await NombreDisponibleAsync(email)
        };
        db.Usuarios.Add(usuario);

        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Dos peticiones a la vez con la misma cuenta nueva (doble toque, reintento):
            // el índice único de GoogleId deja pasar solo una. Se devuelve la que quedó.
            db.Entry(usuario).State = EntityState.Detached;
            return await db.Usuarios.FirstAsync(u => u.GoogleId == google.Sub);
        }
        return usuario;
    }

    private async Task ActualizarEmailAsync(Usuario usuario, DatosGoogle google)
    {
        var email = google.Email?.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(email) || !google.EmailVerificado || email == usuario.Email) return;
        if (await db.Usuarios.AnyAsync(u => u.Email == email && u.Id != usuario.Id)) return;
        usuario.Email = email;
        await db.SaveChangesAsync();
    }

    /// <summary>
    /// Genera un nombre de usuario único a partir del correo: "Jesús.Ramos@gmail.com" →
    /// "jesus.ramos"; si ya existe, "jesus.ramos2", "jesus.ramos3"...
    /// </summary>
    public async Task<string> NombreDisponibleAsync(string email)
    {
        var baseNombre = NombreBase(email);
        var existentes = await db.Usuarios
            .Where(u => u.NombreUsuario.StartsWith(baseNombre))
            .Select(u => u.NombreUsuario)
            .ToListAsync();
        var ocupados = existentes.ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (!ocupados.Contains(baseNombre)) return baseNombre;
        for (var n = 2; ; n++)
        {
            var candidato = baseNombre + n;
            if (!ocupados.Contains(candidato)) return candidato;
        }
    }

    /// <summary>Parte del correo antes de la @, en minúsculas, sin acentos y solo con a-z, 0-9, "." y "_".</summary>
    public static string NombreBase(string email)
    {
        var local = email.Split('@')[0].Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var c in local.ToLowerInvariant())
        {
            if (c is >= 'a' and <= 'z' or >= '0' and <= '9' or '.' or '_') sb.Append(c);
            else if (c == '-' || c == '+') sb.Append('_');
            // Las marcas de acento (de la normalización FormD) y otros símbolos se descartan.
        }

        var nombre = sb.ToString().Trim('.', '_');
        if (nombre.Length < LargoMinimoUsuario) nombre = "usuario" + nombre;
        // Se deja espacio para el número que se agrega si el nombre ya existe.
        return nombre.Length > LargoMaximoUsuario - 6 ? nombre[..(LargoMaximoUsuario - 6)] : nombre;
    }
}
