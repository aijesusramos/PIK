using Microsoft.Extensions.Options;

namespace Pik.Api.Services;

/// <summary>
/// Guarda y lee los archivos de las fotos. Es una interfaz para que, si después
/// las quieres mover a la nube, solo cambies esta clase y no los controladores.
/// </summary>
public interface IAlmacenamientoFotos
{
    /// <summary>
    /// Guarda el archivo y devuelve su ruta relativa (la que se guarda en la base).
    /// [sufijo] distingue versiones de la misma foto: "" = original, "_revelada" = revelada.
    /// </summary>
    Task<string> GuardarAsync(Guid usuarioId, Guid rolloId, Guid fotoId, string extension,
        Stream contenido, string sufijo = "", CancellationToken ct = default);

    Stream AbrirLectura(string rutaRelativa);

    void Eliminar(string rutaRelativa);
}

public class AlmacenamientoOptions
{
    /// <summary>Carpeta de las fotos, relativa a la carpeta del proyecto. Nunca dentro de wwwroot.</summary>
    public string RutaFotos { get; set; } = "almacenamiento/fotos";
}

/// <summary>
/// Almacenamiento en una carpeta privada del servidor:
/// almacenamiento/fotos/{usuario}/{rollo}/{foto}.jpg (original) y {foto}_revelada.jpg
/// </summary>
public class AlmacenamientoLocal : IAlmacenamientoFotos
{
    private readonly string _raiz;

    public AlmacenamientoLocal(IOptions<AlmacenamientoOptions> opciones, IWebHostEnvironment env)
    {
        _raiz = Path.GetFullPath(Path.Combine(env.ContentRootPath, opciones.Value.RutaFotos));
        Directory.CreateDirectory(_raiz);
    }

    public async Task<string> GuardarAsync(Guid usuarioId, Guid rolloId, Guid fotoId, string extension,
        Stream contenido, string sufijo = "", CancellationToken ct = default)
    {
        var relativa = $"{usuarioId}/{rolloId}/{fotoId}{sufijo}{extension}";
        var completa = RutaCompleta(relativa);
        Directory.CreateDirectory(Path.GetDirectoryName(completa)!);

        await using var archivo = new FileStream(completa, FileMode.CreateNew, FileAccess.Write,
            FileShare.None, bufferSize: 81920, useAsync: true);
        await contenido.CopyToAsync(archivo, ct);

        return relativa;
    }

    public Stream AbrirLectura(string rutaRelativa) =>
        new FileStream(RutaCompleta(rutaRelativa), FileMode.Open, FileAccess.Read,
            FileShare.Read, bufferSize: 81920, useAsync: true);

    public void Eliminar(string rutaRelativa)
    {
        var completa = RutaCompleta(rutaRelativa);
        if (File.Exists(completa)) File.Delete(completa);
    }

    /// <summary>Convierte la ruta relativa en absoluta e impide salir de la carpeta de fotos.</summary>
    private string RutaCompleta(string rutaRelativa)
    {
        var completa = Path.GetFullPath(Path.Combine(_raiz, rutaRelativa));
        if (!completa.StartsWith(_raiz + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Ruta fuera de la carpeta de almacenamiento.");
        return completa;
    }
}