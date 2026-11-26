using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Pik.Api.Migrations
{
    /// <inheritdoc />
    public partial class TituloRollo : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Titulo",
                table: "Rollos",
                type: "TEXT",
                maxLength: 40,
                nullable: false,
                defaultValue: "");

            // Los rollos que ya existían reciben "Rollo 1", "Rollo 2"... por usuario,
            // en el orden en que se crearon (las fechas en SQLite son texto ISO 8601,
            // así que compararlas como texto respeta el orden cronológico).
            migrationBuilder.Sql("""
                UPDATE Rollos
                SET Titulo = 'Rollo ' || (
                    SELECT COUNT(*) FROM Rollos AS anterior
                    WHERE anterior.UsuarioId = Rollos.UsuarioId
                      AND anterior.FechaCreacionUtc <= Rollos.FechaCreacionUtc)
                WHERE Titulo = '';
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Titulo",
                table: "Rollos");
        }
    }
}
