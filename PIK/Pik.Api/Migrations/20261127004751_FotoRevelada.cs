using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Pik.Api.Migrations
{
    /// <inheritdoc />
    public partial class FotoRevelada : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "RutaRevelada",
                table: "Fotos",
                type: "TEXT",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "TamanoBytesRevelada",
                table: "Fotos",
                type: "INTEGER",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TipoContenidoRevelada",
                table: "Fotos",
                type: "TEXT",
                maxLength: 100,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RutaRevelada",
                table: "Fotos");

            migrationBuilder.DropColumn(
                name: "TamanoBytesRevelada",
                table: "Fotos");

            migrationBuilder.DropColumn(
                name: "TipoContenidoRevelada",
                table: "Fotos");
        }
    }
}
