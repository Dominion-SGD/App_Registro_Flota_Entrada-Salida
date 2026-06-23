import 'package:flutter/material.dart';
import '../models/usuario_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { checking, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.checking;
  Usuario? _usuario;
  String? _error;

  AuthStatus get status => _status;
  Usuario? get usuario => _usuario;
  String? get error => _error;
  bool get isLoading => _status == AuthStatus.checking;

  Future<void> verificarSesion() async {
    _status = AuthStatus.checking;
    notifyListeners();
    try {
      final usuario = await authService.getUsuarioGuardado();
      if (usuario != null) {
        _usuario = usuario;
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    _status = AuthStatus.checking;
    notifyListeners();
    try {
      _usuario = await authService.login(email, password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await authService.logout();
    _usuario = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
