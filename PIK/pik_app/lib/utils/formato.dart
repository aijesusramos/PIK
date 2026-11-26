/// Formatos de texto que usan varias pantallas.
library;

/// "2 h 15 min", "40 min", "menos de 1 min"...
String formatearDuracion(Duration d) {
  if (d <= Duration.zero) return 'unos segundos';
  final horas = d.inHours;
  final minutos = d.inMinutes.remainder(60);
  if (horas > 0) return '$horas h $minutos min';
  if (minutos > 0) return '$minutos min';
  return 'menos de 1 min';
}

/// Fecha en la hora local del dispositivo: "25/11/2026 14:30".
/// La API manda UTC; toLocal() la convierte a la zona horaria del usuario.
String formatearFecha(DateTime fecha) {
  final f = fecha.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}
