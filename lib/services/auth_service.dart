import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/usuario_model.dart';
import '../utils/constants.dart';
import 'db_service.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();

  Future<Usuario> login(String username, String password) async {
    final conn = await dbService.connection;

    final result = await conn.execute(
      'SELECT id, username, password, nombre_completo FROM usuarios WHERE username = :username LIMIT 1',
      {'username': username.trim()},
    );

    if (result.rows.isEmpty) {
      throw Exception('Usuario no encontrado');
    }

    final row = result.rows.first.assoc();
    final dbPassword = row['password'] ?? '';

    if (!_validarPassword(password, dbPassword)) {
      throw Exception('Contraseña incorrecta');
    }

    final usuario = Usuario.fromRow(row);
    await _guardarSesion(usuario);
    return usuario;
  }

  bool _validarPassword(String ingresada, String guardada) {
    // Compara texto plano; si la BD usa MD5 ajustar aquí
    return ingresada == guardada;
  }

  Future<void> _guardarSesion(Usuario usuario) async {
    await _storage.write(key: kTokenKey, value: 'local_${usuario.id}');
    await _storage.write(key: kUserKey, value: jsonEncode(usuario.toJson()));
  }

  Future<void> logout() async {
    await _storage.delete(key: kTokenKey);
    await _storage.delete(key: kUserKey);
  }

  Future<Usuario?> getUsuarioGuardado() async {
    final token = await _storage.read(key: kTokenKey);
    final userData = await _storage.read(key: kUserKey);
    if (token == null || userData == null) return null;
    return Usuario.fromJson(jsonDecode(userData));
  }

  Future<bool> estaAutenticado() async {
    final token = await _storage.read(key: kTokenKey);
    return token != null;
  }
}

final authService = AuthService();
