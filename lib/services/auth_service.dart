import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/usuario_model.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();
  static const _kJwtKey = 'jwt_token';

  Future<Usuario> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usuario': username.trim(), 'password': password}),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200 || data['success'] == false) {
      throw Exception(
        data['error'] ?? data['message'] ?? 'Credenciales incorrectas',
      );
    }

    final userData = data['user'] as Map<String, dynamic>;
    final token = data['token'] as String?;

    final usuario = Usuario.fromJson(userData);
    await _guardarSesion(usuario, token);
    if (token != null) apiService.setToken(token);
    return usuario;
  }

  Future<void> _guardarSesion(Usuario usuario, String? token) async {
    await _storage.write(key: kTokenKey, value: 'local_${usuario.id}');
    await _storage.write(key: kUserKey, value: jsonEncode(usuario.toJson()));
    if (token != null) {
      await _storage.write(key: _kJwtKey, value: token);
    }
  }

  Future<void> logout() async {
    apiService.clearToken();
    await _storage.delete(key: kTokenKey);
    await _storage.delete(key: kUserKey);
    await _storage.delete(key: _kJwtKey);
  }

  Future<Usuario?> getUsuarioGuardado() async {
    final localToken = await _storage.read(key: kTokenKey);
    final userData = await _storage.read(key: kUserKey);
    if (localToken == null || userData == null) return null;

    final jwt = await _storage.read(key: _kJwtKey);
    if (jwt != null) apiService.setToken(jwt);

    return Usuario.fromJson(jsonDecode(userData));
  }

  Future<bool> estaAutenticado() async {
    final token = await _storage.read(key: kTokenKey);
    return token != null;
  }
}

final authService = AuthService();
