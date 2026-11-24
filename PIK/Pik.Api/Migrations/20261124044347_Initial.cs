using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Pik.Api.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Usuarios",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Email = table.Column<string>(type: "TEXT", maxLength: 256, nullable: false),
                    NombreUsuario = table.Column<string>(type: "TEXT", maxLength: 50, nullable: false),
                    PasswordHash = table.Column<string>(type: "TEXT", nullable: false),
                    FechaRegistroUtc = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Usuarios", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Dispositivos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    UsuarioId = table.Column<Guid>(type: "TEXT", nullable: false),
                    TokenFcm = table.Column<string>(type: "TEXT", maxLength: 4096, nullable: false),
                    Plataforma = table.Column<string>(type: "TEXT", nullable: false),
                    FechaRegistroUtc = table.Column<DateTime>(type: "TEXT", nullable: false),
                    UltimaActividadUtc = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Dispositivos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Dispositivos_Usuarios_UsuarioId",
                        column: x => x.UsuarioId,
                        principalTable: "Usuarios",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Rollos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    UsuarioId = table.Column<Guid>(type: "TEXT", nullable: false),
                    Filtro = table.Column<string>(type: "TEXT", nullable: false),
                    Capacidad = table.Column<int>(type: "INTEGER", nullable: false),
                    Estado = table.Column<string>(type: "TEXT", nullable: false),
                    FechaCreacionUtc = table.Column<DateTime>(type: "TEXT", nullable: false),
                    FechaCierreUtc = table.Column<DateTime>(type: "TEXT", nullable: true),
                    FechaInicioReveladoUtc = table.Column<DateTime>(type: "TEXT", nullable: true),
                    FechaFinReveladoUtc = table.Column<DateTime>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Rollos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Rollos_Usuarios_UsuarioId",
                        column: x => x.UsuarioId,
                        principalTable: "Usuarios",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Fotos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    RolloId = table.Column<Guid>(type: "TEXT", nullable: false),
                    NumeroEnRollo = table.Column<int>(type: "INTEGER", nullable: false),
                    RutaArchivo = table.Column<string>(type: "TEXT", maxLength: 500, nullable: false),
                    TipoContenido = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    TamanoBytes = table.Column<long>(type: "INTEGER", nullable: false),
                    Ancho = table.Column<int>(type: "INTEGER", nullable: false),
                    Alto = table.Column<int>(type: "INTEGER", nullable: false),
                    FechaCapturaUtc = table.Column<DateTime>(type: "TEXT", nullable: false),
                    FechaSubidaUtc = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Fotos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Fotos_Rollos_RolloId",
                        column: x => x.RolloId,
                        principalTable: "Rollos",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Notificaciones",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    UsuarioId = table.Column<Guid>(type: "TEXT", nullable: false),
                    RolloId = table.Column<Guid>(type: "TEXT", nullable: true),
                    Tipo = table.Column<string>(type: "TEXT", nullable: false),
                    Titulo = table.Column<string>(type: "TEXT", maxLength: 120, nullable: false),
                    Mensaje = table.Column<string>(type: "TEXT", maxLength: 500, nullable: false),
                    FechaCreacionUtc = table.Column<DateTime>(type: "TEXT", nullable: false),
                    Enviada = table.Column<bool>(type: "INTEGER", nullable: false),
                    FechaEnvioUtc = table.Column<DateTime>(type: "TEXT", nullable: true),
                    Leida = table.Column<bool>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Notificaciones", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Notificaciones_Rollos_RolloId",
                        column: x => x.RolloId,
                        principalTable: "Rollos",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_Notificaciones_Usuarios_UsuarioId",
                        column: x => x.UsuarioId,
                        principalTable: "Usuarios",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Dispositivos_TokenFcm",
                table: "Dispositivos",
                column: "TokenFcm",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Dispositivos_UsuarioId",
                table: "Dispositivos",
                column: "UsuarioId");

            migrationBuilder.CreateIndex(
                name: "IX_Fotos_RolloId_NumeroEnRollo",
                table: "Fotos",
                columns: new[] { "RolloId", "NumeroEnRollo" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Notificaciones_Enviada",
                table: "Notificaciones",
                column: "Enviada");

            migrationBuilder.CreateIndex(
                name: "IX_Notificaciones_RolloId",
                table: "Notificaciones",
                column: "RolloId");

            migrationBuilder.CreateIndex(
                name: "IX_Notificaciones_UsuarioId_Leida",
                table: "Notificaciones",
                columns: new[] { "UsuarioId", "Leida" });

            migrationBuilder.CreateIndex(
                name: "IX_Rollos_Estado_FechaCierreUtc",
                table: "Rollos",
                columns: new[] { "Estado", "FechaCierreUtc" });

            migrationBuilder.CreateIndex(
                name: "IX_Rollos_Estado_FechaFinReveladoUtc",
                table: "Rollos",
                columns: new[] { "Estado", "FechaFinReveladoUtc" });

            migrationBuilder.CreateIndex(
                name: "IX_Rollos_UsuarioId_Estado",
                table: "Rollos",
                columns: new[] { "UsuarioId", "Estado" });

            migrationBuilder.CreateIndex(
                name: "IX_Usuarios_Email",
                table: "Usuarios",
                column: "Email",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Usuarios_NombreUsuario",
                table: "Usuarios",
                column: "NombreUsuario",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Dispositivos");

            migrationBuilder.DropTable(
                name: "Fotos");

            migrationBuilder.DropTable(
                name: "Notificaciones");

            migrationBuilder.DropTable(
                name: "Rollos");

            migrationBuilder.DropTable(
                name: "Usuarios");
        }
    }
}
