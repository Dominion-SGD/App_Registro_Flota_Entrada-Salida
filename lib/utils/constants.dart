import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF003c8f);
  static const primaryLight = Color(0xFF5e92f3);
  static const accent = Color(0xFFFF6F00);
  static const entrada = Color(0xFF2E7D32);
  static const salida = Color(0xFFC62828);
  static const background = Color(0xFFF5F5F5);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
}

class AppStrings {
  static const appName = 'Flota Dominion';
  static const empresa = 'Dominion';
  static const loginTitle = 'Iniciar Sesión';
  static const entradaLabel = 'ENTRADA';
  static const salidaLabel = 'SALIDA';
}

class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const registroVehiculo = '/registro-vehiculo';
  static const historial = '/historial';
  static const vehiculos = '/vehiculos';
}

const String kTokenKey = 'auth_token';
const String kUserKey = 'user_data';
