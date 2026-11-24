namespace Pik.Api.Models;

/// <summary>
/// Reglas de negocio de PIK (versión 1). Se validan siempre en el servidor,
/// nunca solo en la app.
/// </summary>
public static class ReglasRollo
{
    /// <summary>Rollos en estado Activo que un usuario puede tener al mismo tiempo.</summary>
    public const int MaxRollosActivos = 1;

    /// <summary>Rollos en estado Revelando que un usuario puede tener al mismo tiempo.</summary>
    public const int MaxRollosRevelando = 3;

    /// <summary>
    /// Tiempo de revelado según la capacidad del rollo. Depende de la capacidad,
    /// no de las fotos tomadas: un rollo de 24 cerrado con 10 fotos tarda 12 h.
    /// </summary>
    public static TimeSpan TiempoRevelado(CapacidadRollo capacidad) => capacidad switch
    {
        CapacidadRollo.Seis => TimeSpan.FromHours(3),
        CapacidadRollo.Doce => TimeSpan.FromHours(6),
        CapacidadRollo.Veinticuatro => TimeSpan.FromHours(12),
        _ => throw new ArgumentOutOfRangeException(nameof(capacidad), capacidad, "Capacidad no válida")
    };

    public static int NumeroDeFotos(CapacidadRollo capacidad) => (int)capacidad;
}
