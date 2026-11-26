import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/modelos.dart';
import 'rollos_service.dart';

/// Los rollos del usuario, compartidos por la cámara y la galería.
///
/// Es un ChangeNotifier: cuando algo cambia (se toma una foto, se crea o se cierra
/// un rollo) avisa, y todas las pantallas que lo escuchan se redibujan con los
/// mismos datos. Así la cámara y la galería nunca muestran cosas distintas.
///
/// Se crea al iniciar sesión y se destruye al cerrarla (ver InicioScreen), así
/// los rollos de un usuario nunca se le muestran a otro.
class MisRollos extends ChangeNotifier {
  MisRollos(this._servicio) {
    cargar();
    // Cada 30 s: redibuja las cuentas regresivas y, si un revelado ya terminó,
    // vuelve a pedir la lista (ese rollo pasa a Revelado y quizá avanza la cola).
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (rollos.any((r) => r.tiempoRestante == Duration.zero)) {
        cargar();
      } else {
        _avisar();
      }
    });
  }

  final RollosService _servicio;
  Timer? _reloj;
  bool _destruido = false;

  List<Rollo> rollos = [];
  bool cargando = true;
  String? error;

  /// El rollo en el que se están tomando fotos (como máximo hay uno).
  Rollo? get activo {
    for (final r in rollos) {
      if (r.estado == EstadoRollo.activo) return r;
    }
    return null;
  }

  List<Rollo> get enProceso => rollos
      .where((r) => r.estado == EstadoRollo.revelando || r.estado == EstadoRollo.enCola)
      .toList();

  List<Rollo> get revelados => rollos.where((r) => r.estado == EstadoRollo.revelado).toList();

  Future<void> cargar() async {
    try {
      rollos = await _servicio.listar();
      error = null;
    } on ApiException catch (e) {
      error = e.mensaje;
    } finally {
      cargando = false;
      _avisar();
    }
  }

  Future<Rollo> crear(FiltroRollo filtro, int capacidad, {String? titulo}) async {
    final nuevo = await _servicio.crear(filtro, capacidad, titulo: titulo);
    rollos = [nuevo, ...rollos]; // la API ordena del más nuevo al más viejo
    _avisar();
    return nuevo;
  }

  /// Cierre manual. Devuelve el rollo ya en Revelando o En cola.
  Future<Rollo> cerrar(Rollo rollo) async {
    final cerrado = await _servicio.cerrar(rollo.id);
    actualizar(cerrado);
    return cerrado;
  }

  Future<Rollo> renombrar(Rollo rollo, String titulo) async {
    final renombrado = await _servicio.renombrar(rollo.id, titulo);
    actualizar(renombrado);
    return renombrado;
  }

  /// Reemplaza un rollo con su versión más reciente (p. ej. tras subir una foto).
  void actualizar(Rollo rollo) {
    final i = rollos.indexWhere((r) => r.id == rollo.id);
    if (i < 0) return;
    rollos = [...rollos]..[i] = rollo;
    _avisar();
  }

  /// Las peticiones pueden terminar después de cerrar sesión: no avisar a nadie si
  /// este objeto ya se destruyó (Flutter lanzaría un error).
  void _avisar() {
    if (!_destruido) notifyListeners();
  }

  @override
  void dispose() {
    _destruido = true;
    _reloj?.cancel();
    super.dispose();
  }
}
