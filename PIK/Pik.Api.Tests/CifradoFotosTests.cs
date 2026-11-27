using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Pik.Api.Contracts;
using Pik.Api.Data;
using Pik.Api.Services;

namespace Pik.Api.Tests;

/// <summary>Las fotos se guardan cifradas con AES-256-GCM y solo se leen descifradas por la API.</summary>
public class CifradoFotosTests(FabricaPik fabrica) : IClassFixture<FabricaPik>
{
    // Empieza como un JPEG de verdad (FF D8 FF E0) para comprobar que en disco ya no se ve así.
    private static readonly byte[] JpegFalso =
        [0xFF, 0xD8, 0xFF, 0xE0, .. "contenido de una foto de prueba"u8.ToArray()];

    private IAlmacenamientoFotos Almacen => fabrica.Services.GetRequiredService<IAlmacenamientoFotos>();

    private string EnDisco(string rutaRelativa) => Path.Combine(fabrica.RutaFotos, rutaRelativa);

    private async Task<string> GuardarAsync(byte[] contenido, Guid? fotoId = null)
    {
        using var flujo = new MemoryStream(contenido);
        return await Almacen.GuardarAsync(Guid.NewGuid(), Guid.NewGuid(), fotoId ?? Guid.NewGuid(), ".jpg", flujo);
    }

    private static byte[] Leer(Stream flujo)
    {
        using (flujo)
        using (var copia = new MemoryStream())
        {
            flujo.CopyTo(copia);
            return copia.ToArray();
        }
    }

    [Fact]
    public void La_API_usa_el_almacenamiento_cifrado()
    {
        Assert.IsType<AlmacenamientoCifrado>(Almacen);
    }

    [Fact]
    public async Task En_disco_no_se_ve_la_foto_y_al_leer_se_recupera_igual()
    {
        var ruta = await GuardarAsync(JpegFalso);

        var bytesEnDisco = await File.ReadAllBytesAsync(EnDisco(ruta));
        Assert.Equal("PIK1"u8.ToArray(), bytesEnDisco[..4]);           // nuestro encabezado
        Assert.NotEqual(JpegFalso[..4], bytesEnDisco[..4]);           // ya no es un JPEG
        Assert.Equal(JpegFalso.Length + 4 + 1 + 12 + 16, bytesEnDisco.Length);

        Assert.Equal(JpegFalso, Leer(Almacen.AbrirLectura(ruta)));
    }

    [Fact]
    public async Task La_misma_foto_cifrada_dos_veces_da_archivos_distintos()
    {
        // Nonce aleatorio por archivo: nunca se repite.
        var a = await File.ReadAllBytesAsync(EnDisco(await GuardarAsync(JpegFalso)));
        var b = await File.ReadAllBytesAsync(EnDisco(await GuardarAsync(JpegFalso)));
        Assert.NotEqual(a, b);
    }

    [Fact]
    public async Task Si_se_altera_un_byte_la_lectura_falla()
    {
        var ruta = await GuardarAsync(JpegFalso);
        var bytes = await File.ReadAllBytesAsync(EnDisco(ruta));
        bytes[20] ^= 0x01;
        await File.WriteAllBytesAsync(EnDisco(ruta), bytes);

        Assert.Throws<InvalidDataException>(() => Almacen.AbrirLectura(ruta));
    }

    [Fact]
    public async Task Si_se_copia_a_otra_ruta_ya_no_se_descifra()
    {
        var ruta = await GuardarAsync(JpegFalso);
        // Otra foto (de otro usuario) a la que se le pone encima el archivo cifrado.
        var otra = await GuardarAsync([1, 2, 3]);
        File.Copy(EnDisco(ruta), EnDisco(otra), overwrite: true);

        Assert.Throws<InvalidDataException>(() => Almacen.AbrirLectura(otra));
    }

    [Fact]
    public async Task Un_archivo_sin_cifrar_no_se_acepta()
    {
        var ruta = await GuardarAsync(JpegFalso);
        await File.WriteAllBytesAsync(EnDisco(ruta), JpegFalso); // como las fotos de antes

        Assert.Throws<InvalidDataException>(() => Almacen.AbrirLectura(ruta));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("esto no es base64")]
    [InlineData("MTIzNDU2Nzg5MDEyMzQ1Ng==")] // 16 bytes: AES-128, no 256
    public void Sin_una_clave_de_32_bytes_la_API_no_arranca(string? clave)
    {
        Assert.Throws<InvalidOperationException>(() => ClaveFotos.Desde(clave));
    }

    [Fact]
    public async Task De_punta_a_punta_se_sube_cifrada_y_el_endpoint_la_devuelve_descifrada()
    {
        var cliente = fabrica.CreateClient();
        var u = Guid.NewGuid().ToString("N")[..8];
        var entrar = await cliente.PostAsJsonAsync("/api/auth/google",
            new { idToken = fabrica.Google.Token($"sub-{u}", $"cifrado.{u}@gmail.com") });
        var auth = (await entrar.Content.ReadFromJsonAsync<AuthRespuesta>())!;
        cliente.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Rollo de 6 con una foto (original y revelada distintas), y se cierra.
        var crear = await cliente.PostAsJsonAsync("/api/rollos", new { filtro = "Original", capacidad = 6 });
        Assert.Equal(HttpStatusCode.Created, crear.StatusCode);
        var rolloId = JsonDocument.Parse(await crear.Content.ReadAsStringAsync())
            .RootElement.GetProperty("id").GetGuid();

        byte[] revelada = [0xFF, 0xD8, 0xFF, 0xE0, .. "la revelada"u8.ToArray()];
        var fotoId = Guid.NewGuid();
        using var formulario = new MultipartFormDataContent
        {
            { new StringContent(fotoId.ToString()), "id" },
            { Imagen(JpegFalso), "archivo", "original.jpg" },
            { Imagen(revelada), "revelada", "revelada.jpg" },
            { new StringContent("10"), "ancho" },
            { new StringContent("10"), "alto" },
        };
        var subir = await cliente.PostAsync($"/api/rollos/{rolloId}/fotos", formulario);
        Assert.Equal(HttpStatusCode.Created, subir.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await cliente.PostAsync($"/api/rollos/{rolloId}/cerrar", null)).StatusCode);

        // En disco, las dos versiones están cifradas.
        string rutaOriginal, rutaRevelada;
        using (var scope = fabrica.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<PikDbContext>();
            var foto = await db.Fotos.SingleAsync(f => f.Id == fotoId);
            (rutaOriginal, rutaRevelada) = (foto.RutaArchivo, foto.RutaRevelada!);

            // Adelantar el reloj: el revelado ya terminó.
            var rollo = await db.Rollos.SingleAsync(r => r.Id == rolloId);
            rollo.FechaFinReveladoUtc = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        }
        Assert.Equal("PIK1"u8.ToArray(), (await File.ReadAllBytesAsync(EnDisco(rutaOriginal)))[..4]);
        Assert.Equal("PIK1"u8.ToArray(), (await File.ReadAllBytesAsync(EnDisco(rutaRevelada)))[..4]);

        // El endpoint las devuelve descifradas y sin permitir caché.
        var respuesta = await cliente.GetAsync($"/api/fotos/{fotoId}/archivo");
        Assert.Equal(HttpStatusCode.OK, respuesta.StatusCode);
        Assert.Equal(revelada, await respuesta.Content.ReadAsByteArrayAsync());
        Assert.True(respuesta.Headers.CacheControl?.NoStore);

        var original = await cliente.GetAsync($"/api/fotos/{fotoId}/archivo?version=original");
        Assert.Equal(JpegFalso, await original.Content.ReadAsByteArrayAsync());
    }

    private static ByteArrayContent Imagen(byte[] bytes)
    {
        var contenido = new ByteArrayContent(bytes);
        contenido.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        return contenido;
    }
}
