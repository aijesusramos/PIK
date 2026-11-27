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

/// <summary>Un archivo de imagen recibido, ya validado por el controlador.</summary>
public record ArchivoNuevo(Stream Contenido, string TipoContenido, string Extension, long TamanoBytes);

/// <summary>
/// Datos de una foto recibida, ya validados por el controlador.
/// El Id lo genera la app: lo usa como semilla del grano al revelar, antes de subir.
/// </summary>
public record NuevaFoto(
    Guid Id,
    ArchivoNuevo Original,
    ArchivoNuevo Revelada,
    int Ancho,
    int Alto,
    DateTime FechaCapturaUtc);

/// <summary>Resultado de agregar una foto. Creada = false si ya existía (reintento).</summary>
public record ResultadoFoto(Foto Foto, bool Creada);

/// <summary>
/// Reglas de negocio de los rollos. La usan los controladores y la tarea en segundo plano.
/// </summary>
public class RolloService(
    PikDbContext db,
    IAlmacenamientoFotos almacen,
    IOptions<ReveladoOptions> opciones)
{
    // ---------- Crear ----------

    public async Task<Rollo> CrearAsync(
        Guid usuarioId, FiltroRollo filtro, CapacidadRollo capacidad, string? titulo)
    {
        await using var tx = await IniciarTransaccionAsync();

        var activos = await db.Rollos.CountAsync(r =>
            r.UsuarioId == usuarioId && r.Estado == EstadoRollo.Activo);

        if (activos >= ReglasRollo.MaxRollosActivos)
            throw new ReglaNegocioException(
                $"Ya tienes {ReglasRollo.MaxRollosActivos} rollos activos. Termina o cierra uno para crear otro.");

        // Sin título: "Rollo N", contando todos los rollos que el usuario ha creado.
        var tituloFinal = ReglasRollo.LimpiarTitulo(titulo);
        if (tituloFinal is null)
        {
            var creados = await db.Rollos.CountAsync(r => r.UsuarioId == usuarioId);
            tituloFinal = ReglasRollo.TituloPorDefecto(creados);
        }

        var rollo = new Rollo
        {
            UsuarioId = usuarioId,
            Titulo = tituloFinal,
            Filtro = filtro,
            Capacidad = capacidad,
            Estado = EstadoRollo.Activo
        };

        db.Rollos.Add(rollo);
        await db.SaveChangesAsync();
        if (tx is not null) await tx.CommitAsync();
        return rollo;
    }

    // ---------- Renombrar ----------

    /// <summary>Cambia el título. Se permite en cualquier estado: no afecta el revelado.</summary>
    public async Task RenombrarAsync(Rollo rollo, string titulo)
    {
        rollo.Titulo = ReglasRollo.LimpiarTitulo(titulo)
            ?? throw new ReglaNegocioException("El título no puede quedar vacío.");
        await db.SaveChangesAsync();
    }

    // ---------- Agregar foto ----------

    /// <summary>
    /// Agrega una foto (original + revelada) a un rollo Activo. Si con ella se llena, el
    /// rollo se cierra automáticamente (pasa a Revelando o a En cola).
    ///
    /// Es idempotente: si ya existe una foto con ese Id en este rollo (la app reintentó
    /// porque se perdió la respuesta), la devuelve sin duplicarla.
    /// </summary>
    public async Task<ResultadoFoto> AgregarFotoAsync(Rollo rollo, NuevaFoto nueva)
    {
        await using var tx = await IniciarTransaccionAsync();

        // Releer dentro de la transacción: el estado pudo cambiar desde que se cargó.
        await db.Entry(rollo).ReloadAsync();

        // Antes que las reglas del rollo: el reintento de la última foto llega con el
        // rollo ya cerrado y debe responder igual que la primera vez.
        var existente = await db.Fotos.FirstOrDefaultAsync(f => f.Id == nueva.Id);
        if (existente is not null)
        {
            if (existente.RolloId != rollo.Id)
                throw new ReglaNegocioException("Ya existe una foto con ese id.");
            return new ResultadoFoto(existente, Creada: false);
        }

        if (rollo.Estado != EstadoRollo.Activo)
            throw new ReglaNegocioException("Este rollo ya está cerrado. No se pueden agregar más fotos.");

        var tomadas = await db.Fotos.CountAsync(f => f.RolloId == rollo.Id);
        if (tomadas >= (int)rollo.Capacidad)
            throw new ReglaNegocioException("El rollo ya está lleno.");

        var foto = new Foto
        {
            Id = nueva.Id,
            RolloId = rollo.Id,
            NumeroEnRollo = tomadas + 1,
            TipoContenido = nueva.Original.TipoContenido,
            TamanoBytes = nueva.Original.TamanoBytes,
            TipoContenidoRevelada = nueva.Revelada.TipoContenido,
            TamanoBytesRevelada = nueva.Revelada.TamanoBytes,
            Ancho = nueva.Ancho,
            Alto = nueva.Alto,
            FechaCapturaUtc = nueva.FechaCapturaUtc
        };

        // Primero los archivos, luego la base. Si algo falla, se borran los archivos.
        foto.RutaArchivo = await almacen.GuardarAsync(
            rollo.UsuarioId, rollo.Id, foto.Id, nueva.Original.Extension, nueva.Original.Contenido);

        try
        {
            foto.RutaRevelada = await almacen.GuardarAsync(
                rollo.UsuarioId, rollo.Id, foto.Id, nueva.Revelada.Extension,
                nueva.Revelada.Contenido, sufijo: "_revelada");

            db.Fotos.Add(foto);
            await db.SaveChangesAsync();

            if (foto.NumeroEnRollo == (int)rollo.Capacidad)
                await CerrarAsync(rollo); // usa esta misma transacción

            if (tx is not null) await tx.CommitAsync();
        }
        catch
        {
            almacen.Eliminar(foto.RutaArchivo);
            if (foto.RutaRevelada is not null) almacen.Eliminar(foto.RutaRevelada);
            throw;
        }

        return new ResultadoFoto(foto, Creada: true);
    }

    // ---------- Cerrar ----------

    /// <summary>
    /// Cierra un rollo Activo (lleno o cierre manual). Si el usuario tiene menos de 2
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

        // Un rollo cuyo tiempo ya terminó no ocupa lugar, aunque la tarea en segundo plano
        // todavía no lo haya marcado como Revelado (la hora manda, igual que en EstaRevelado).
        var revelando = await db.Rollos.CountAsync(r =>
            r.UsuarioId == rollo.UsuarioId && r.Estado == EstadoRollo.Revelando
            && r.FechaFinReveladoUtc > ahora);

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
    /// 2) Para cada usuario con rollos En cola, inicia los que quepan (máximo 2 revelándose).
    ///
    /// Cada rollo de la cola empieza a revelarse en el momento en que SE LIBERÓ el lugar
    /// (el fin del rollo que terminó), no cuando corre esta tarea. Así, si el servidor
    /// estuvo apagado, la cola no se retrasa: un rollo puede empezar en el pasado e
    /// incluso terminar ya, liberando a su vez su lugar para el siguiente (en cadena).
    ///
    /// Devuelve cuántos rollos se revelaron.
    /// </summary>
    public async Task<int> ProcesarReveladosAsync(DateTime ahoraUtc)
    {
        await using var tx = await IniciarTransaccionAsync();

        var terminados = await db.Rollos
            .Where(r => r.Estado == EstadoRollo.Revelando && r.FechaFinReveladoUtc <= ahoraUtc)
            .ToListAsync();

        foreach (var rollo in terminados)
            MarcarRevelado(rollo);
        await db.SaveChangesAsync();
        var revelados = terminados.Count;

        // Hora en que se liberó cada lugar, por usuario: el fin de cada rollo que terminó.
        var liberados = terminados
            .GroupBy(r => r.UsuarioId)
            .ToDictionary(g => g.Key, g => g.Select(r => r.FechaFinReveladoUtc!.Value).ToList());

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

            // Lugares libres, del que se liberó primero al último. Si hay un lugar libre
            // sin un rollo que lo haya liberado en esta vuelta, se toma como libre "ahora".
            var lugares = new PriorityQueue<DateTime, DateTime>();
            foreach (var hora in (liberados.GetValueOrDefault(usuarioId) ?? []).Order().Take(libres))
                lugares.Enqueue(hora, hora);
            while (lugares.Count < libres)
                lugares.Enqueue(ahoraUtc, ahoraUtc);

            var cola = await db.Rollos
                .Where(r => r.UsuarioId == usuarioId && r.Estado == EstadoRollo.EnCola)
                .OrderBy(r => r.FechaCierreUtc)
                .ToListAsync();

            foreach (var rollo in cola)
            {
                if (!lugares.TryDequeue(out var libreDesde, out _)) break;

                // Empieza cuando se liberó el lugar, pero nunca antes de que se cerrara.
                var inicio = rollo.FechaCierreUtc is { } cierre && cierre > libreDesde ? cierre : libreDesde;
                IniciarRevelado(rollo, inicio);

                // El servidor estuvo apagado lo suficiente: este también ya terminó.
                if (rollo.FechaFinReveladoUtc <= ahoraUtc)
                {
                    MarcarRevelado(rollo);
                    revelados++;
                    var fin = rollo.FechaFinReveladoUtc!.Value;
                    lugares.Enqueue(fin, fin); // su lugar queda libre para el siguiente
                }
            }
        }
        await db.SaveChangesAsync();

        if (tx is not null) await tx.CommitAsync();
        return revelados;
    }

    /// <summary>Marca el rollo como Revelado y crea la notificación para el usuario.</summary>
    private void MarcarRevelado(Rollo rollo)
    {
        rollo.Estado = EstadoRollo.Revelado;
        db.Notificaciones.Add(new Notificacion
        {
            UsuarioId = rollo.UsuarioId,
            RolloId = rollo.Id,
            Tipo = TipoNotificacion.RolloRevelado,
            Titulo = "¡Tu rollo está listo!",
            Mensaje = $"Tu rollo \"{rollo.Titulo}\" ya se reveló."
        });
    }

    /// <summary>Pasa el rollo a Revelando y calcula cuándo termina según su capacidad.</summary>
    /// <param name="inicioUtc">Cuándo empieza el revelado (puede ser en el pasado, ver la cola).</param>
    public void IniciarRevelado(Rollo rollo, DateTime inicioUtc)
    {
        var horas = ReglasRollo.TiempoRevelado(rollo.Capacidad).TotalHours;
        rollo.Estado = EstadoRollo.Revelando;
        rollo.FechaInicioReveladoUtc = inicioUtc;
        rollo.FechaFinReveladoUtc = inicioUtc + TimeSpan.FromMinutes(horas * opciones.Value.MinutosPorHora);
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
    /// dos peticiones simultáneas no pueden saltarse los límites de 1 activo y 2 revelando.
    /// </summary>
    private async Task<IDbContextTransaction?> IniciarTransaccionAsync() =>
        db.Database.CurrentTransaction is null
            ? await db.Database.BeginTransactionAsync()
            : null;
}