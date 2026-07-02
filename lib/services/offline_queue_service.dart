import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncResult {
  final int sincronizados;
  final int fallidos;
  const SyncResult({required this.sincronizados, required this.fallidos});
}

class OfflineQueueService {
  static const _prefKey = 'offline_registro_queue';

  static Future<MySQLConnection> _abrirConexion() async {
    final conn = await MySQLConnection.createConnection(
      host: dotenv.env['DB_HOST'] ?? '161.132.128.4',
      port: int.parse(dotenv.env['DB_PORT'] ?? '3306'),
      userName: dotenv.env['DB_USER'] ?? 'root',
      password: dotenv.env['DB_PASS'] ?? '',
      databaseName: dotenv.env['DB_NAME'] ?? 'dominion_gpd_energia',
      secure: true,
    );
    await conn.connect().timeout(const Duration(seconds: 8));
    return conn;
  }

  static Future<void> encolar(Map<String, dynamic> registro) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_prefKey) ?? [];
    lista.add(jsonEncode(registro));
    await prefs.setStringList(_prefKey, lista);
  }

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

  static Future<SyncResult> sincronizar() async {
    final pendientes = await _obtenerTodos();
    if (pendientes.isEmpty) {
      return const SyncResult(sincronizados: 0, fallidos: 0);
    }

    MySQLConnection? conn;
    int ok = 0;
    final restantes = <String>[];

    try {
      conn = await _abrirConexion();

      for (final reg in pendientes) {
        try {
          await conn.execute('''
            INSERT INTO registros_vehiculos
              (placa, dni_conductor, nombre_conductor, cargo_conductor,
               area_conductor, dni_autoriza, nombre_autoriza, BASE,
               base_origen, Base_Dirigida, km_actual, tipo, observacion,
               destino, usuario_id, empresa, fecha)
            VALUES
              (:placa, :dni, :nombre, :cargo,
               :area, :dni_autoriza, :nombre_autoriza, :BASE,
               :base_origen, :Base_Dirigida, :km, :tipo, :obs,
               :destino, :usuario_id, :empresa, :fecha)
          ''', {
            'placa':           reg['placa'],
            'dni':             reg['dni'],
            'nombre':          reg['nombre'],
            'cargo':           reg['cargo'],
            'area':            reg['area'],
            'dni_autoriza':    reg['dni_autoriza'],
            'nombre_autoriza': reg['nombre_autoriza'],
            'BASE':            reg['BASE'],
            'base_origen':     reg['base_origen'],
            'Base_Dirigida':   reg['Base_Dirigida'],
            'km':              reg['km'],
            'tipo':            reg['tipo'],
            'obs':             reg['obs'],
            'destino':         reg['destino'],
            'usuario_id':      reg['usuario_id'],
            'empresa':         reg['empresa'],
            'fecha':           reg['fecha'],
          });
          ok++;
        } catch (_) {
          restantes.add(jsonEncode(reg));
        }
      }
    } catch (_) {
      return SyncResult(sincronizados: 0, fallidos: pendientes.length);
    } finally {
      await conn?.close();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, restantes);
    return SyncResult(sincronizados: ok, fallidos: restantes.length);
  }
}
