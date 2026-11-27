/// Parámetros de cada filtro de PIK.
///
/// La parte de color vive en el LUT (`assets/luts/<filtro>.png`);
/// halation y grano son parámetros, así se ajustan sin regenerar el LUT.
/// Los valores deben coincidir con PRESET_ORIGINAL en tools/preview.py.
enum FilmFilter { original, bw, redBlue }

class FilmPreset {
  const FilmPreset({
    required this.lutAsset,
    this.lutSize = 33,
    this.halationWeights = (0.2126, 0.7152, 0.0722),
    required this.halationThreshold,
    required this.halationTint,
    required this.halationStrength,
    required this.halationRadius,
    this.halationScale = 0.25,
    required this.grainAmount,
    required this.grainSize,
  });

  /// Strip 2D del LUT 3D, generado con tools/generate_lut.py
  final String lutAsset;
  final int lutSize;

  /// Pesos (r, g, b) con los que se mide qué tan "brillante" es un píxel
  /// para la halation. Por defecto luminancia; Red&Blue usa casi sólo el rojo
  /// (en la película real la halation se forma en la capa sensible al rojo),
  /// así los neones rojos también resplandecen.
  final (double, double, double) halationWeights;

  /// Valor (0..1) a partir del cual una zona "sangra" luz.
  final double halationThreshold;

  /// Color del resplandor (r, g, b) 0..1. En película real es rojo-naranja.
  final (double, double, double) halationTint;
  final double halationStrength;

  /// Sigma del desenfoque como fracción del lado largo de la foto.
  final double halationRadius;

  /// Resolución relativa a la que se calcula la halation (barato y suficiente).
  final double halationScale;

  /// Desviación estándar del grano (0..1 en valores de color).
  final double grainAmount;

  /// Tamaño del grano como fracción del lado largo (independiente de la resolución).
  final double grainSize;

  static const original = FilmPreset(
    lutAsset: 'assets/luts/original.png',
    halationThreshold: 0.72,
    halationTint: (1.0, 0.32, 0.10),
    halationStrength: 0.55,
    halationRadius: 0.012,
    grainAmount: 0.045,
    grainSize: 1 / 1500,
  );

  /// Inspirado en Cinestill 800T: tungsteno, sombras azules, mucho resplandor rojo.
  static const redBlue = FilmPreset(
    lutAsset: 'assets/luts/red_blue.png',
    halationWeights: (0.9, 0.1, 0.0),
    halationThreshold: 0.72,
    halationTint: (1.0, 0.12, 0.06),
    halationStrength: 3.0,
    halationRadius: 0.022,
    grainAmount: 0.04,
    grainSize: 1 / 1100,
  );

  /// Inspirado en Kodak Tri-X 400: altas luces cremosas, sombras profundas,
  /// piel en grises claros. Resplandor neutro y suave (difusión, no color).
  static const bw = FilmPreset(
    lutAsset: 'assets/luts/bw.png',
    halationThreshold: 0.82,
    halationTint: (1.0, 1.0, 1.0),
    halationStrength: 0.30,
    halationRadius: 0.010,
    grainAmount: 0.045,
    grainSize: 1 / 1300,
  );

  static FilmPreset of(FilmFilter filter) => switch (filter) {
        FilmFilter.original => original,
        FilmFilter.redBlue => redBlue,
        FilmFilter.bw => bw,
      };
}