using Microsoft.Extensions.Options;

namespace Pik.Api.Services;

/// <summary>
/// Tarea en segundo plano: corre mientras la API está encendida y, cada cierto tiempo,
/// termina los revelados vencidos y avanza la cola de cada usuario.
/// </summary>
public class ReveladoWorker(
    IServiceScopeFactory scopes,
    IOptions<ReveladoOptions> opciones,
    ILogger<ReveladoWorker> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var intervalo = TimeSpan.FromSeconds(Math.Max(5, opciones.Value.IntervaloRevisionSegundos));
        log.LogInformation("ReveladoWorker iniciado. Revisa cada {Segundos} s.", intervalo.TotalSeconds);

        using var timer = new PeriodicTimer(intervalo);
        do
        {
            try
            {
                // El DbContext es "scoped": se crea uno nuevo en cada vuelta.
                using var scope = scopes.CreateScope();
                var rollos = scope.ServiceProvider.GetRequiredService<RolloService>();

                var revelados = await rollos.ProcesarReveladosAsync(DateTime.UtcNow);
                if (revelados > 0)
                    log.LogInformation("{Cantidad} rollo(s) revelado(s).", revelados);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Un error no debe detener la tarea: se registra y se intenta en la siguiente vuelta.
                log.LogError(ex, "Error al procesar los revelados.");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}