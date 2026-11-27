using System.Security.Cryptography;
using System.Text;

namespace Pik.Api.Services;

/// <summary>
/// Clave AES-256 para las fotos. Se valida al arrancar la API: sin una clave correcta
/// la API no arranca (mejor eso que guardar fotos sin cifrar).
/// </summary>
public sealed class ClaveFotos
{
    public const int Bytes = 32; // 256 bits

    internal byte[] Valor { get; }

    private ClaveFotos(byte[] valor) => Valor = valor;

    public static ClaveFotos Desde(string? base64)
    {
        const string ayuda =
            " Genera una con: dotnet user-secrets set \"Almacenamiento:ClaveCifrado\" <32 bytes en Base64>" +
            " (en producción, variable de entorno Almacenamiento__ClaveCifrado).";

        if (string.IsNullOrWhiteSpace(base64))
            throw new InvalidOperationException("Falta Almacenamiento:ClaveCifrado." + ayuda);

        byte[] valor;
        try
        {
            valor = Convert.FromBase64String(base64.Trim());
        }
        catch (FormatException)
        {
            throw new InvalidOperationException("Almacenamiento:ClaveCifrado no es Base64 válido." + ayuda);
        }

        if (valor.Length != Bytes)
            throw new InvalidOperationException(
                $"Almacenamiento:ClaveCifrado debe medir {Bytes} bytes (mide {valor.Length})." + ayuda);

        return new ClaveFotos(valor);
    }
}

/// <summary>
/// Decorador que cifra con AES-256-GCM todo lo que se guarda y lo descifra al leer.
/// Envuelve a otro IAlmacenamientoFotos (AlmacenamientoLocal), así ni RolloService ni los
/// controladores saben que existe el cifrado.
///
/// Formato de cada archivo en disco:
///   "PIK1" (4) | versión de clave (1) | nonce (12) | texto cifrado (n) | tag (16)
///
/// - El nonce es aleatorio y nuevo por archivo: en GCM, repetir nonce con la misma clave
///   rompe la seguridad.
/// - El tag detecta cualquier cambio: si se altera un solo byte, la lectura falla.
/// - Datos asociados (AAD) = encabezado + ruta relativa: el archivo queda amarrado a su
///   ubicación; si se copia a la carpeta de otro usuario u otra foto, ya no se descifra.
/// </summary>
public sealed class AlmacenamientoCifrado(IAlmacenamientoFotos interno, ClaveFotos clave) : IAlmacenamientoFotos
{
    private static readonly byte[] Magico = "PIK1"u8.ToArray();

    /// <summary>Permite rotar la clave en el futuro sin volver a cifrar todo de golpe.</summary>
    private const byte VersionClave = 1;

    private const int LargoEncabezado = 4 + 1; // mágico + versión
    private const int LargoNonce = 12;         // AesGcm.NonceByteSizes.MaxSize
    private const int LargoTag = 16;           // AesGcm.TagByteSizes.MaxSize

    public async Task<string> GuardarAsync(Guid usuarioId, Guid rolloId, Guid fotoId, string extension,
        Stream contenido, string sufijo = "", CancellationToken ct = default)
    {
        // La foto ya viene limitada a 15 MB por el controlador: se puede cifrar en memoria.
        using var claro = new MemoryStream();
        await contenido.CopyToAsync(claro, ct);

        var ruta = RutasFotos.Relativa(usuarioId, rolloId, fotoId, sufijo, extension);
        var cifrado = Cifrar(claro.GetBuffer().AsSpan(0, (int)claro.Length), ruta);

        using var flujo = new MemoryStream(cifrado, writable: false);
        return await interno.GuardarAsync(usuarioId, rolloId, fotoId, extension, flujo, sufijo, ct);
    }

    public Stream AbrirLectura(string rutaRelativa)
    {
        byte[] datos;
        using (var flujo = interno.AbrirLectura(rutaRelativa))
        using (var copia = new MemoryStream())
        {
            flujo.CopyTo(copia);
            datos = copia.ToArray();
        }

        return new MemoryStream(Descifrar(datos, rutaRelativa), writable: false);
    }

    public void Eliminar(string rutaRelativa) => interno.Eliminar(rutaRelativa);

    private byte[] Cifrar(ReadOnlySpan<byte> claro, string ruta)
    {
        var salida = new byte[LargoEncabezado + LargoNonce + claro.Length + LargoTag];
        Magico.CopyTo(salida, 0);
        salida[4] = VersionClave;

        var nonce = salida.AsSpan(LargoEncabezado, LargoNonce);
        RandomNumberGenerator.Fill(nonce);
        var texto = salida.AsSpan(LargoEncabezado + LargoNonce, claro.Length);
        var tag = salida.AsSpan(salida.Length - LargoTag, LargoTag);

        using var aes = new AesGcm(clave.Valor, LargoTag);
        aes.Encrypt(nonce, claro, texto, tag, DatosAsociados(ruta));
        return salida;
    }

    private byte[] Descifrar(byte[] datos, string ruta)
    {
        if (datos.Length < LargoEncabezado + LargoNonce + LargoTag ||
            !datos.AsSpan(0, Magico.Length).SequenceEqual(Magico))
            throw new InvalidDataException($"La foto {ruta} no está cifrada con el formato de PIK.");

        if (datos[4] != VersionClave)
            throw new InvalidDataException($"La foto {ruta} usa una versión de clave desconocida ({datos[4]}).");

        var nonce = datos.AsSpan(LargoEncabezado, LargoNonce);
        var largoTexto = datos.Length - LargoEncabezado - LargoNonce - LargoTag;
        var texto = datos.AsSpan(LargoEncabezado + LargoNonce, largoTexto);
        var tag = datos.AsSpan(datos.Length - LargoTag, LargoTag);

        var claro = new byte[largoTexto];
        try
        {
            using var aes = new AesGcm(clave.Valor, LargoTag);
            aes.Decrypt(nonce, texto, tag, claro, DatosAsociados(ruta));
        }
        catch (AuthenticationTagMismatchException)
        {
            // Clave distinta, archivo alterado o movido de su ruta original.
            throw new InvalidDataException($"La foto {ruta} no pasó la verificación de integridad.");
        }
        return claro;
    }

    /// <summary>AAD: el encabezado y la ruta (con "/"; es la misma que se guarda en la base).</summary>
    private static byte[] DatosAsociados(string ruta) =>
        [.. Magico, VersionClave, .. Encoding.UTF8.GetBytes(ruta.Replace('\\', '/'))];
}
