namespace Pik.Api.Models;

/// <summary>Estilo de color del rollo. Se elige al crear el rollo y aplica a todas sus fotos.</summary>
public enum FiltroRollo
{
    Original,
    BlancoNegro,
    RedBlue
}

/// <summary>Cantidad de fotos que admite un rollo. El valor numérico es el número de fotos.</summary>
public enum CapacidadRollo
{
    Seis = 6,
    Doce = 12,
    Veinticuatro = 24
}

/// <summary>Ciclo de vida de un rollo: Activo → EnCola → Revelando → Revelado.</summary>
public enum EstadoRollo
{
    /// <summary>El usuario está tomando fotos.</summary>
    Activo,
    /// <summary>Cerrado (lleno o manual) y esperando un lugar libre para revelarse.</summary>
    EnCola,
    /// <summary>Corriendo el tiempo de revelado; las fotos siguen bloqueadas.</summary>
    Revelando,
    /// <summary>Fotos disponibles para ver, descargar y compartir.</summary>
    Revelado
}

public enum PlataformaDispositivo
{
    Android,
    iOS
}

public enum TipoNotificacion
{
    RolloRevelado,
    RolloInicioRevelado
}
