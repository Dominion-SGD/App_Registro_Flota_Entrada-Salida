import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SyncResult {
  final int sincronizados;
  final int fallidos;
  const SyncResult({required this.sincronizados, required this.fallidos});
}

class OfflineQueueService {
  static const _prefKey = 'offline_registro_queue';

  static String get _apiBase =>
      dotenv.env['API_BASE_URL'] ?? 'http://161.132.128.4:3000/api';

  /// Guarda un registro en la cola local (SharedPreferences).
  static Future<void> encolar(Map<String, dynamic> registro) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_prefKey) ?? [];
    lista.add(jsonEncode(registro));
    await prefs.setStringList(_prefKey, lista);
  }

  /// Cantidad de registros pendientes de sincronizar.
  static Future<int> contarPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefKey) ?? []).length;
  }

  static Future<List<Map<String, dynamic>>> _obtenerTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_prefKey) ?? [];
    return lista
        .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
        .toList();
  }

  /// Envía cada registro pendiente al endpoint /mobile/guardar_registro.
  /// Los que el servidor acepta se eliminan de la cola; los que fallan se conservan.
  static Future<SyncResult> sincronizar() async {
    final pendientes = await _obtenerTodos();
    if (pendientes.isEmpty) {
      return const SyncResult(sincronizados: 0, fallidos: 0);
    }

    int ok = 0;
    final restantes = <String>[];
    final uri = Uri.parse('$_apiBase/mobile/guardar_registro');
    const headers = {'Content-Type': 'application/json'};

    for (final reg in pendientes) {
      try {
        final resp = await http
            .post(uri, headers: headers, body: jsonEncode(reg))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final body = jsonDecode(utf8.decode(resp.bodyBytes));
          if (body is Map && body['success'] == true) {
            ok++;
            continue;
          }
        }
        restantes.add(jsonEncode(reg));
      } catch (_) {
        restantes.add(jsonEncode(reg));
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, restantes);
    return SyncResult(sincronizados: ok, fallidos: restantes.length);
  }
}
