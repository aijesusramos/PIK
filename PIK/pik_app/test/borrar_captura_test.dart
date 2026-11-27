import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

// Se prueba la versión del teléfono (la que escribe en disco).
import 'package:pik_app/fotos/borrar_captura_movil.dart';

void main() {
  late Directory temporal;

  setUp(() => temporal = Directory.systemTemp.createTempSync('pik_test_'));
  tearDown(() => temporal.deleteSync(recursive: true));

  File crear(String rutaRelativa) =>
      File('${temporal.path}/$rutaRelativa')..createSync(recursive: true)..writeAsBytesSync([1, 2, 3]);

  test('borrarCaptura borra el archivo temporal de la captura', () async {
    final captura = crear('CAP123456789.jpg');
    await borrarCaptura(XFile(captura.path));
    expect(captura.existsSync(), isFalse);
  });

  test('borrarCaptura no falla si el archivo ya no existe', () async {
    final captura = crear('CAP1.jpg')..deleteSync();
    await borrarCaptura(XFile(captura.path)); // no lanza
  });

  test('limpiarCapturasViejas borra solo las capturas del plugin (Android e iOS)', () async {
    final androidCap = crear('CAP8455128801.jpg');
    final iosCap = crear('camera/pictures/CAP_0A1B2C3D-4E5F-6789-ABCD-EF0123456789.jpg');
    // Archivos que NO son capturas y deben quedarse:
    final video = crear('camera/videos/REC_0A1B2C3D-4E5F-6789-ABCD-EF0123456789.mp4');
    final otro = crear('otro_archivo.jpg');
    final parecido = crear('CAPTURA_importante.jpg');

    final borrados = await limpiarCapturasViejas(temporal: temporal);

    expect(borrados, 2);
    expect(androidCap.existsSync(), isFalse);
    expect(iosCap.existsSync(), isFalse);
    expect(video.existsSync(), isTrue);
    expect(otro.existsSync(), isTrue);
    expect(parecido.existsSync(), isTrue);
  });

  test('limpiarCapturasViejas no falla si no hay carpeta de la cámara', () async {
    expect(await limpiarCapturasViejas(temporal: temporal), 0);
  });
}
