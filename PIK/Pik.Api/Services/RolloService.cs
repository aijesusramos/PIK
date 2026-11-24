using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Options;
using Pik.Api.Data;
using Pik.Api.Models;

namespace Pik.Api.Services;

/// <summary>Se lanza cuando una operación rompe una regla de PIK. El controlador la convierte en 409.</summary>
public class ReglaNegocioException(string mensaje) : Exception(mensaje);

public class ReveladoOptions
{
    /// <summary>
    /// Minutos reales que dura cada "hora" de revelado. 60 = tiempo real.
    /// En desarrollo se pone en 1 para probar: un rollo de 6 fotos (3 h) se revela en 3 minutos.
    /// </summary>
    public double MinutosPorHora { get; set; } = 60;

    /// <summary>Cada cuántos segundos la tarea en segundo plano revisa los revelados.</summary>
    public int IntervaloRevisionSegundos { get; set; } = 30;
}

/// <summary>Datos de una foto recibida, ya validados por el controlador.</summary>
public record NuevaFoto(
    Stream Contenido,
    string TipoContenido,
    string Extension,
    long TamanoBytes,
    int Ancho,
    int Alto,
    DateTime FechaCapturaUtc);

/// <summary>
/// Reglas de negocio de los rollos. La usan los controladores y la tarea en segundo plano.
/// </summary>
public class RolloService(
    PikDbContext db,
    IAlmacenamientoFotos almacen,
    IOptions<ReveladoOptions> opciones)
{
    // ---------- Crear ----------

    public async Task<Rollo> CrearAsync(Guid usuarioId, FiltroRollo filtro, CapacidadRollo capacidad)
    {
        await using var tx = await IniciarTransaccionAsync();

        var activos = await db.Rollos.CountAsync(r =>
            r.UsuarioId == usuarioId && r.Estado == EstadoRollo.Activo);

        if (activos >= ReglasRollo.MaxRollosActivos)
            throw new ReglaNegocioException(
                $"Ya tienes {ReglasRollo.MaxRollosActivos} rollos activos. Termina o cierra uno para crear otro.");

        var rollo = new Rollo
        {
            UsuarioId = usuarioId,
            Filtro = filtro,
            Capacidad = capacidad,
            Estado = EstadoRollo.Activo
        };

        db.Rollos.Add(rollo);
        await db.SaveChangesAsync();
        if (tx is not null) await tx.CommitAsync();
        return rollo;
    }

    // ---------- Agregar foto ----------

    /// <summary>
    /// Agrega una foto a un rollo Activo. Si con ella se llena, el rollo se cierra
    /// automáticamente (pasa a Revelando o a En cola).
    /// </summary>
    public async Task<Foto> AgregarFotoAsync(Rollo rollo, NuevaFoto nueva)
    {
        await using var tx = await IniciarTransaccionAsync();

        // Releer dentro de la transacción: el estado pudo cambiar desde que se cargó.
        await db.Entry(rollo).ReloadAsync();

        if (rollo.Estado != EstadoRollo.Activo)
            throw new ReglaNegocioException("Este rollo ya está cerrado. No se pueden agregar más fotos.");

        var tomadas = await db.Fotos.CountAsync(f => f.RolloId == rollo.Id);
        if (tomadas >= (int)rollo.Capacidad)
            throw new ReglaNegocioException("El rollo ya está lleno.");

        var foto = new Foto
        {
            RolloId = rollo.Id,
            NumeroEnRollo = tomadas + 1,
            TipoContenido = nueva.TipoContenido,
            TamanoBytes = nueva.TamanoBytes,
            Ancho = nueva.Ancho,
            Alto = nueva.Alto,
            FechaCapturaUtc = nueva.FechaCapturaUtc
        };

        // Primero el archivo, luego la base. Si la base falla, se borra el archivo.
        foto.RutaArchivo = await almacen.GuardarAsync(
            rollo.UsuarioId, rollo.Id, foto.Id, nueva.Extension, nueva.Contenido);

        try
        {
            db.Fotos.Add(foto);
            await db.SaveChangesAsync();

            if (foto.NumeroEnRollo == (int)rollo.Capacidad)
                await CerrarAsync(rollo); // usa esta misma transacción

            if (tx is not null) await tx.CommitAsync();
        }
        catch
        {
            almacen.Eliminar(foto.RutaArchivo);
            throw;
        }

        return foto;
    }

    // ---------- Cerrar ----------

    /// <summary>
    /// Cierra un rollo Activo (lleno o cierre manual). Si el usuario tiene menos de 3
    /// rollos revelándose, empieza a revelarse; si no, queda En cola.
    /// </summary>
    public async Task CerrarAsync(Rollo rollo)
    {
        await using var tx = await IniciarTransaccionAsync();

        if (rollo.Estado != EstadoRollo.Activo)
            throw new ReglaNegocioException("Solo se puede cerrar un rollo activo.");

        var fotos = await db.Fotos.CountAsync(f => f.RolloId == rollo.Id);
        if (fotos == 0)
            throw new ReglaNegocioException("El rollo no tiene fotos. Toma al menos una antes de cerrarlo.");

        var ahora = DateTime.UtcNow;
        rollo.FechaCierreUtc = ahora;

        var revelando = await db.Rollos.CountAsync(r =>
            r.UsuarioId == rollo.UsuarioId && r.Estado == EstadoRollo.Revelando);

        if (revelando < ReglasRollo.MaxRollosRevelando)
            IniciarRevelado(rollo, ahora);
        else
            rollo.Estado = EstadoRollo.EnCola;

        await db.SaveChangesAsync();
        if (tx is not null) await tx.CommitAsync();
    }

    // ---------- Revelado (lo llama la tarea en segundo plano) ----------

    /// <summary>
    /// 1) Marca como Revelado todo rollo cuyo tiempo ya terminó y crea su notificación.
    /// 2) Para cada usuario con rollos En cola, inicia los que quepan (máximo 3 revelándose).
    /// Devuelve cuántos rollos se revelaron.
    /// </summary>
    public async Task<int> ProcesarReveladosAsync(DateTime ahoraUtc)
    {
        await using var tx = await IniciarTransaccionAsync();

        var terminados = await db.Rollos
            .Where(r => r.Estado == EstadoRollo.Revelando && r.FechaFinReveladoUtc <= ahoraUtc)
            .ToListAsync();

        foreach (var rollo in terminados)
        {
            rollo.Estado = EstadoRollo.Revelado;
            db.Notificaciones.Add(new Notificacion
            {
                UsuarioId = rollo.UsuarioId,
                RolloId = rollo.Id,
                Tipo = TipoNotificacion.RolloRevelado,
                Titulo = "¡Tu rollo está listo!",
                Mensaje = $"Tu rollo de {(int)rollo.Capacidad} fotos ya se reveló."
            });
        }
        await db.SaveChangesAsync();

        var usuariosConCola = await db.Rollos
            .Where(r => r.Estado == EstadoRollo.EnCola)
            .Select(r => r.UsuarioId)
            .Distinct()
            .ToListAsync();

        foreach (var usuarioId in usuariosConCola)
        {
            var revelando = await db.Rollos.CountAsync(r =>
                r.UsuarioId == usuarioId && r.Estado == EstadoRollo.Revelando);

            var libres = ReglasRollo.MaxRollosRevelando - revelando;
            if (libres <= 0) continue;

            var siguientes = await db.Rollos
                .Where(r => r.UsuarioId == usuarioId && r.Estado == EstadoRollo.EnCola)
                .OrderBy(r => r.FechaCierreUtc)
                .Take(libres)
                .ToListAsync();

            foreach (var rollo in siguientes)
                IniciarRevelado(rollo, ahoraUtc);
        }
        await db.SaveChangesAsync();

        if (tx is not null) await tx.CommitAsync();
        return terminados.Count;
    }

    /// <summary>Pasa el rollo a Revelando y calcula cuándo termina según su capacidad.</summary>
    public void IniciarRevelado(Rollo rollo, DateTime ahoraUtc)
    {
        var horas = ReglasRollo.TiempoRevelado(rollo.Capacidad).TotalHours;
        rollo.Estado = EstadoRollo.Revelando;
        rollo.FechaInicioReveladoUtc = ahoraUtc;
        rollo.FechaFinReveladoUtc = ahoraUtc + TimeSpan.FromMinutes(horas * opciones.Value.MinutosPorHora);
    }

    /// <summary>
    /// Regla de bloqueo de las fotos. La hora manda: si ya pasó FechaFinRevelado la foto
    /// está disponible aunque la tarea en segundo plano no haya corrido todavía.
    /// </summary>
    public static bool EstaRevelado(EstadoRollo estado, DateTime? finReveladoUtc, DateTime ahoraUtc) =>
        estado == EstadoRollo.Revelado ||
        (estado == EstadoRollo.Revelando && finReveladoUtc.HasValue && finReveladoUtc.Value <= ahoraUtc);

    /// <summary>
    /// Abre una transacción solo si no hay una en curso. Así CerrarAsync puede llamarse sola
    /// o desde AgregarFotoAsync sin anidar transacciones (SQLite no lo permite).
    /// En SQLite la transacción toma el bloqueo de escritura desde el inicio, por eso
    /// dos peticiones simultáneas no pueden saltarse los límites de 2 y 3.
    /// </summary>
    private async Task<IDbContextTransaction?> IniciarTransaccionAsync() =>
        db.Database.CurrentTransaction is null
            ? await db.Database.BeginTransactionAsync()
            : null;
}