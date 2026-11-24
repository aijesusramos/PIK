using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Pik.Api.Models;

namespace Pik.Api.Data;

public class PikDbContext : DbContext
{
    public PikDbContext(DbContextOptions<PikDbContext> options) : base(options) { }

    public DbSet<Usuario> Usuarios => Set<Usuario>();
    public DbSet<Rollo> Rollos => Set<Rollo>();
    public DbSet<Foto> Fotos => Set<Foto>();
    public DbSet<Dispositivo> Dispositivos => Set<Dispositivo>();
    public DbSet<Notificacion> Notificaciones => Set<Notificacion>();

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        // SQLite guarda las fechas como texto y al leerlas pierde el "Kind".
        // Estos convertidores las devuelven siempre marcadas como UTC.
        configurationBuilder.Properties<DateTime>().HaveConversion<FechaUtcConverter>();
        configurationBuilder.Properties<DateTime?>().HaveConversion<FechaUtcNullableConverter>();

        // Los enums se guardan como texto ("Revelando", "BlancoNegro"...):
        // más legibles al revisar la base y seguros si se reordenan.
        configurationBuilder.Properties<FiltroRollo>().HaveConversion<string>();
        configurationBuilder.Properties<EstadoRollo>().HaveConversion<string>();
        configurationBuilder.Properties<PlataformaDispositivo>().HaveConversion<string>();
        configurationBuilder.Properties<TipoNotificacion>().HaveConversion<string>();
        // CapacidadRollo se guarda como número (6, 12, 24).
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Usuario>(e =>
        {
            e.HasIndex(u => u.Email).IsUnique();
            e.HasIndex(u => u.NombreUsuario).IsUnique();
            e.Property(u => u.Email).HasMaxLength(256).IsRequired();
            e.Property(u => u.NombreUsuario).HasMaxLength(50).IsRequired();
            e.Property(u => u.PasswordHash).IsRequired();
        });

        modelBuilder.Entity<Rollo>(e =>
        {
            e.HasOne(r => r.Usuario)
             .WithMany(u => u.Rollos)
             .HasForeignKey(r => r.UsuarioId)
             .OnDelete(DeleteBehavior.Cascade);

            // Contar rollos Activos / Revelando de un usuario (reglas de 2 y 3).
            e.HasIndex(r => new { r.UsuarioId, r.Estado });

            // Tarea en segundo plano: revelados que ya terminaron y cola por orden de cierre.
            e.HasIndex(r => new { r.Estado, r.FechaFinReveladoUtc });
            e.HasIndex(r => new { r.Estado, r.FechaCierreUtc });
        });

        modelBuilder.Entity<Foto>(e =>
        {
            e.HasOne(f => f.Rollo)
             .WithMany(r => r.Fotos)
             .HasForeignKey(f => f.RolloId)
             .OnDelete(DeleteBehavior.Cascade);

            // No puede haber dos fotos con el mismo número en un rollo.
            e.HasIndex(f => new { f.RolloId, f.NumeroEnRollo }).IsUnique();
            e.Property(f => f.RutaArchivo).HasMaxLength(500).IsRequired();
            e.Property(f => f.TipoContenido).HasMaxLength(100);
        });

        modelBuilder.Entity<Dispositivo>(e =>
        {
            e.HasOne(d => d.Usuario)
             .WithMany(u => u.Dispositivos)
             .HasForeignKey(d => d.UsuarioId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(d => d.TokenFcm).IsUnique();
            e.Property(d => d.TokenFcm).HasMaxLength(4096).IsRequired();
        });

        modelBuilder.Entity<Notificacion>(e =>
        {
            e.HasOne(n => n.Usuario)
             .WithMany(u => u.Notificaciones)
             .HasForeignKey(n => n.UsuarioId)
             .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(n => n.Rollo)
             .WithMany()
             .HasForeignKey(n => n.RolloId)
             .OnDelete(DeleteBehavior.SetNull);

            e.HasIndex(n => new { n.UsuarioId, n.Leida });
            e.HasIndex(n => n.Enviada);
            e.Property(n => n.Titulo).HasMaxLength(120);
            e.Property(n => n.Mensaje).HasMaxLength(500);
        });
    }

    private sealed class FechaUtcConverter : ValueConverter<DateTime, DateTime>
    {
        public FechaUtcConverter() : base(
            v => v.Kind == DateTimeKind.Utc ? v : v.ToUniversalTime(),
            v => DateTime.SpecifyKind(v, DateTimeKind.Utc)) { }
    }

    private sealed class FechaUtcNullableConverter : ValueConverter<DateTime?, DateTime?>
    {
        public FechaUtcNullableConverter() : base(
            v => v.HasValue ? (v.Value.Kind == DateTimeKind.Utc ? v : v.Value.ToUniversalTime()) : v,
            v => v.HasValue ? DateTime.SpecifyKind(v.Value, DateTimeKind.Utc) : v) { }
    }
}
