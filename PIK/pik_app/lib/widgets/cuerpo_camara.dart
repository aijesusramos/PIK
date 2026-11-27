import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Piezas visuales de la pantalla de la cámara: el cuerpo metálico, los paneles hundidos
/// (visor, contador, compartimento del rollo) y la retícula del visor.

/// Fondo de metal cepillado gris claro, como el cuerpo de una cámara.
///
/// La textura (assets/texturas/metal.png, generada con un script de Python) es repetible:
/// se dibuja como mosaico. Encima va un degradado de brillo suave (luz desde arriba) para
/// que no se vea plano.
class CuerpoMetalico extends StatelessWidget {
  const CuerpoMetalico({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: colorMetal, // mientras carga la textura
        image: DecorationImage(
          image: AssetImage('assets/texturas/metal.png'),
          repeat: ImageRepeat.repeat,
          scale: 2, // vetas más finas en pantallas de alta densidad
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Panel oscuro "hundido" en el metal: borde biselado (sombra arriba, luz abajo) y una
/// sombra interior en la orilla superior e izquierda. Separa visualmente lo que va dentro
/// (visor, textos, rollo) del cuerpo de la cámara.
///
/// Flutter no tiene sombras interiores (BoxShadow solo es exterior): se dibujan con
/// degradados DEBAJO del contenido, así no lo oscurecen.
class PanelHundido extends StatelessWidget {
  const PanelHundido({
    super.key,
    required this.child,
    this.radio = 12,
    this.padding = const EdgeInsets.all(8),
    this.fondo = colorPanel,
  });

  final Widget child;
  final double radio;
  final EdgeInsetsGeometry padding;
  final Color fondo;

  static const _bisel = 1.5;

  @override
  Widget build(BuildContext context) {
    final sombra = Color.lerp(fondo, Colors.black, 0.75)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radio),
        // Bisel: arriba oscuro (la orilla proyecta sombra hacia adentro), abajo claro
        // (la luz pega en la orilla inferior). Así se lee "hundido", no "en relieve".
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6E7175), Color(0xFFA9ACB0), Color(0xFFF7F8F9)],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_bisel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radio - _bisel),
          child: ColoredBox(
            color: fondo,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // Sombra interior arriba...
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [sombra, sombra.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                // ...y a la izquierda, más tenue.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [sombra.withValues(alpha: 0.6), sombra.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Texto "grabado" en el metal: oscuro con un brillo de 1 px abajo, como las letras
/// grabadas en el cuerpo de una cámara.
class TextoGrabado extends StatelessWidget {
  const TextoGrabado(this.texto, {super.key, this.tamano = 15});

  final String texto;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        fontFamily: fuenteRotulos,
        fontWeight: FontWeight.w800,
        fontSize: tamano,
        letterSpacing: tamano * 0.18,
        color: const Color(0xFF55585C),
        shadows: const [Shadow(color: Color(0xCCFFFFFF), offset: Offset(0, 1))],
      ),
    );
  }
}

/// Retícula del visor, inspirada en los visores de cámaras de rollo (telémetro / réflex):
///  - marco de "líneas brillantes" (solo las esquinas), una guía de encuadre con un margen
///    de 7 %. OJO: la foto incluye TODA la vista previa, también lo que queda fuera del
///    marco (como en los telémetros reales, cuyo marco cubre ~85-90 % de la foto);
///  - marcas de tercios y de centro en los lados del marco (ayudan a componer sin llenar
///    la imagen con una cuadrícula);
///  - círculo de imagen partida al centro (la línea horizontal que lo divide sirve para
///    nivelar el horizonte) y un anillo de microprismas punteado alrededor.
///
/// Opacidad baja: blanco translúcido con una sombra oscura muy tenue, para que se vea
/// tanto en escenas claras como oscuras sin estorbar.
class ReticulaVisor extends CustomPainter {
  const ReticulaVisor();

  static const _linea = Color(0x80FFFFFF); // ~50 %
  static const _sombra = Color(0x33000000); // ~20 %

  @override
  void paint(Canvas canvas, Size size) {
    // Primero la sombra desplazada 1 px, luego la línea: así se ve en el cielo y en la noche.
    _dibujar(canvas, size, _sombra, const Offset(0.8, 0.8));
    _dibujar(canvas, size, _linea, Offset.zero);
  }

  void _dibujar(Canvas canvas, Size size, Color color, Offset desplazamiento) {
    canvas.save();
    canvas.translate(desplazamiento.dx, desplazamiento.dy);

    final lado = math.min(size.width, size.height);
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    final fino = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // --- Marco de líneas brillantes: solo las esquinas ---
    final margen = lado * 0.07;
    final marco = Rect.fromLTRB(margen, margen, size.width - margen, size.height - margen);
    final brazo = lado * 0.08;
    final r = lado * 0.015; // esquinas apenas redondeadas
    for (final (esquina, dx, dy) in [
      (marco.topLeft, 1.0, 1.0),
      (marco.topRight, -1.0, 1.0),
      (marco.bottomLeft, 1.0, -1.0),
      (marco.bottomRight, -1.0, -1.0),
    ]) {
      final p = Path()
        ..moveTo(esquina.dx + dx * brazo, esquina.dy)
        ..lineTo(esquina.dx + dx * r, esquina.dy)
        ..quadraticBezierTo(esquina.dx, esquina.dy, esquina.dx, esquina.dy + dy * r)
        ..lineTo(esquina.dx, esquina.dy + dy * brazo);
      canvas.drawPath(p, trazo);
    }

    // --- Marcas en los lados del marco: tercios (cortas) y centro (más larga) ---
    final corta = lado * 0.022;
    final larga = lado * 0.04;
    for (final t in [1 / 3, 1 / 2, 2 / 3]) {
      final l = t == 1 / 2 ? larga : corta;
      final x = marco.left + marco.width * t;
      final y = marco.top + marco.height * t;
      canvas.drawLine(Offset(x, marco.top), Offset(x, marco.top + l), fino);
      canvas.drawLine(Offset(x, marco.bottom), Offset(x, marco.bottom - l), fino);
      canvas.drawLine(Offset(marco.left, y), Offset(marco.left + l, y), fino);
      canvas.drawLine(Offset(marco.right, y), Offset(marco.right - l, y), fino);
    }

    // --- Centro: imagen partida + anillo de microprismas ---
    final centro = size.center(Offset.zero);
    final radio = lado * 0.085;
    canvas.drawCircle(centro, radio, trazo);
    // Línea que parte el círculo (nivel del horizonte), sale un poco del círculo.
    canvas.drawLine(centro - Offset(radio * 1.35, 0), centro + Offset(radio * 1.35, 0), fino);

    // Anillo punteado (microprismas).
    final radioAnillo = radio * 1.65;
    const puntos = 48;
    final punto = Paint()..color = color;
    for (var i = 0; i < puntos; i++) {
      final a = i * 2 * math.pi / puntos;
      canvas.drawCircle(centro + Offset(math.cos(a), math.sin(a)) * radioAnillo, 0.9, punto);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(ReticulaVisor oldDelegate) => false; // es fija
}
