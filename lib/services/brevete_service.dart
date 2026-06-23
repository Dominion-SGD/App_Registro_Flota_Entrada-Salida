import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mysql_client/mysql_client.dart';

// ── Modelo de resultado ───────────────────────────────────────────────────────
class BreveteInfo {
  final String estado; // VIGENTE | POR_VENCER | CRITICO | VENCIDO | SIN_BREVETE | DESCONOCIDO | NO_APLICA
  final bool bloquea;
  final String mensaje;
  final String? fechaVenc;
  final int? diasRestantes;
  final String? restricciones;
  final String? restriccionAviso;
  final String? categoria;

  const BreveteInfo({
    required this.estado,
    required this.bloquea,
    required this.mensaje,
    this.fechaVenc,
    this.diasRestantes,
    this.restricciones,
    this.restriccionAviso,
    this.categoria,
  });

  static const noAplica = BreveteInfo(estado: 'NO_APLICA', bloquea: false, mensaje: '');

  static BreveteInfo desconocido(String msg) =>
      BreveteInfo(estado: 'DESCONOCIDO', bloquea: false, mensaje: msg);
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class BreveteService {
  // ── Mapa de restricciones → instrucción para Seguridad ─────────────────────
  static const _restriccionInstruccion = <String, String>{
    'CON LENTES':                   'Verificar que use lentes correctores al manejar.',
    'LENTES CORRECTORES':           'Verificar que use lentes correctores al manejar.',
    'USO DE LENTES':                'Verificar que use lentes correctores al manejar.',
    'LENTES':                       'Verificar que use lentes correctores al manejar.',
    'AUDIFONO':                     'Verificar que use audífono al manejar.',
    'USO DE AUDIFONO':              'Verificar que use audífono al manejar.',
    'PROTESIS':                     'Verificar uso de prótesis al manejar.',
    'PROTESIS EN MMSS':             'Verificar prótesis en miembros superiores al manejar.',
    'PROTESIS EN MMII':             'Verificar prótesis en miembros inferiores al manejar.',
    'VEHICULO AUTOMATICO':          'Solo puede manejar vehículos con transmisión automática.',
    'TRANSMISION AUTOMATICA':       'Solo puede manejar vehículos con transmisión automática.',
    'SOLO VEHICULO AUTOMATICO':     'Solo puede manejar vehículos con transmisión automática.',
    'ESPEJO RETROVISOR ADICIONAL':  'Vehículo debe contar con espejo retrovisor adicional.',
    'DIURNA':                       'Solo puede manejar de día (entre 6:00 am y 6:00 pm).',
    'MANEJO DIURNO':                'Solo puede manejar de día (entre 6:00 am y 6:00 pm).',
  };

  static String? _traducirRestriccion(String? texto) {
    if (texto == null) return null;
    final upper = texto.trim().toUpperCase();
    if (['', 'SIN RESTRICCIONES', 'NINGUNA', 'NO TIENE', 'S/R', 'N/A'].contains(upper)) {
      return null;
    }
    final partes = upper.replaceAll(';', ',').split(',')
        .map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final instrucciones = <String>[];
    final desconocidas  = <String>[];
    for (final p in partes) {
      final t = _restriccionInstruccion[p];
      if (t != null) { instrucciones.add(t); } else { desconocidas.add(p); }
    }
    if (desconocidas.isNotEmpty) {
      instrucciones.add('Restricción: ${desconocidas.join(", ")}. Verificar cumplimiento.');
    }
    return instrucciones.isEmpty ? null : instrucciones.join(' ');
  }

  // ── Moto: placa empieza con dígito ─────────────────────────────────────────
  static bool _esMoto(String? placa) {
    if (placa == null || placa.isEmpty) return false;
    for (final ch in placa.trim().toUpperCase().split('')) {
      if (ch != '-' && ch != ' ') return RegExp(r'\d').hasMatch(ch);
    }
    return false;
  }

  // ── TTL escalado según proximidad al vencimiento ───────────────────────────
  static int? _ttlDias(int? dias) {
    if (dias == null)  { return 7;    }
    if (dias < 0)      { return null; } // vencido → siempre re-consultar
    if (dias <= 3)     { return null; } // crítico → siempre
    if (dias <= 7)     { return 1;    }
    if (dias <= 30)    { return 7;    }
    if (dias <= 90)    { return 15;   }
    if (dias <= 180)   { return 30;   }
    return 90;
  }

  static bool _cacheVigente(Map<String, dynamic> fila) {
    final fcStr = fila['fecha_consulta']?.toString();
    if (fcStr == null) return false;
    final fc = DateTime.tryParse(fcStr);
    if (fc == null) return false;
    final ahora = DateTime.now();

    final exitosa = fila['consulta_exitosa'];
    final bool ok = exitosa == 1 || exitosa?.toString() == '1' || exitosa == true;
    if (!ok) return ahora.difference(fc).inMinutes < 10;

    int? diasRestantes;
    final fv = fila['fecha_vencimiento']?.toString();
    if (fv != null && fv.isNotEmpty && fv != 'null') {
      final fecha = DateTime.tryParse(fv.length > 10 ? fv.substring(0, 10) : fv);
      if (fecha != null) {
        diasRestantes = fecha.difference(DateTime(ahora.year, ahora.month, ahora.day)).inDays;
      }
    }

    final ttl = _ttlDias(diasRestantes);
    if (ttl == null) return false;
    return ahora.difference(fc).inDays < ttl;
  }

  // ── Conexión MySQL ─────────────────────────────────────────────────────────
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

  // ── Cache: leer ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> _leerCache(MySQLConnection conn, String dni) async {
    final res = await conn.execute(
      'SELECT * FROM cache_licencia_conducir WHERE dni = :d LIMIT 1',
      {'d': dni},
    );
    if (res.rows.isEmpty) return null;
    final row = res.rows.first;
    return {
      'nombre_completo':   row.colByName('nombre_completo'),
      'numero_licencia':   row.colByName('numero_licencia'),
      'categoria':         row.colByName('categoria'),
      'fecha_vencimiento': row.colByName('fecha_vencimiento'),
      'restricciones':     row.colByName('restricciones'),
      'estado':            row.colByName('estado'),
      'tiene_brevete':     row.colByName('tiene_brevete'),
      'consulta_exitosa':  row.colByName('consulta_exitosa'),
      'fecha_consulta':    row.colByName('fecha_consulta'),
    };
  }

  // ── Cache: guardar / actualizar ────────────────────────────────────────────
  static Future<void> _guardarCache(
    MySQLConnection conn, String dni, Map<String, dynamic> info, bool exito,
  ) async {
    final fechaVenc = info['fecha_vencimiento'] as DateTime?;
    final fvStr = fechaVenc != null
        ? '${fechaVenc.year}-${fechaVenc.month.toString().padLeft(2,'0')}-${fechaVenc.day.toString().padLeft(2,'0')}'
        : null;

    await conn.execute('''
      INSERT INTO cache_licencia_conducir
        (dni, nombre_completo, numero_licencia, categoria,
         fecha_vencimiento, restricciones, estado,
         tiene_brevete, consulta_exitosa, fecha_consulta, ultima_revision, veces_consultado)
      VALUES
        (:dni, :nombre, :num, :cat, :fv, :restr, :est,
         :tb, :ok, NOW(), NOW(), 1)
      ON DUPLICATE KEY UPDATE
        nombre_completo   = COALESCE(VALUES(nombre_completo), nombre_completo),
        numero_licencia   = COALESCE(VALUES(numero_licencia), numero_licencia),
        categoria         = COALESCE(VALUES(categoria), categoria),
        fecha_vencimiento = COALESCE(VALUES(fecha_vencimiento), fecha_vencimiento),
        restricciones     = COALESCE(VALUES(restricciones), restricciones),
        estado            = COALESCE(VALUES(estado), estado),
        tiene_brevete     = VALUES(tiene_brevete),
        consulta_exitosa  = VALUES(consulta_exitosa),
        fecha_consulta    = NOW(),
        ultima_revision   = NOW(),
        veces_consultado  = veces_consultado + 1
    ''', {
      'dni':    dni,
      'nombre': info['nombre_completo'],
      'num':    info['numero_licencia'],
      'cat':    info['categoria'],
      'fv':     fvStr,
      'restr':  info['restricciones'],
      'est':    info['estado'],
      'tb':     (info['tiene_brevete'] == true) ? 1 : 0,
      'ok':     exito ? 1 : 0,
    });
  }

  static Future<void> _marcarRevision(MySQLConnection conn, String dni) async {
    await conn.execute('''
      UPDATE cache_licencia_conducir
      SET ultima_revision = NOW(), veces_consultado = veces_consultado + 1
      WHERE dni = :d
    ''', {'d': dni});
  }

  // ── Llamada a json.pe ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> _consultarJsonpe(String dni) async {
    final url   = dotenv.env['JSONPE_URL']   ?? 'https://api.json.pe/api/licencia';
    final token = dotenv.env['JSONPE_TOKEN'] ?? '';

    if (token.isEmpty) {
      return {'ok': false, 'error': 'JSONPE_TOKEN no configurado en .env'};
    }

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'dni': dni}),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 400 || res.statusCode == 404) {
        return {'ok': true, 'tiene_brevete': false};
      }
      if (res.statusCode != 200) {
        return {'ok': false, 'error': 'HTTP ${res.statusCode}'};
      }

      final body = jsonDecode(res.body);
      final data = (body is Map && body.containsKey('data')) ? body['data'] : body;
      if (data is! Map) return {'ok': true, 'tiene_brevete': false};

      final lic = data['licencia'];
      if (lic is! Map || lic['numero'] == null) {
        return {'ok': true, 'tiene_brevete': false, 'nombre_completo': data['nombre_completo']};
      }

      // Parsear fecha dd/mm/yyyy
      DateTime? fechaVenc;
      final fvStr = (lic['fecha_vencimiento'] ?? '').toString().trim();
      if (fvStr.isNotEmpty) {
        final parts = fvStr.split('/');
        if (parts.length == 3) {
          try {
            fechaVenc = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          } catch (_) {}
        }
      }

      return {
        'ok':              true,
        'tiene_brevete':   true,
        'nombre_completo': data['nombre_completo'],
        'numero_licencia': lic['numero'],
        'categoria':       lic['categoria'],
        'fecha_vencimiento': fechaVenc,
        'restricciones':   (lic['restricciones'] ?? '').toString().trim(),
        'estado':          (lic['estado'] ?? '').toString().trim(),
      };
    } catch (e) {
      return {'ok': false, 'error': 'Error red: $e'};
    }
  }

  // ── Construir BreveteInfo desde datos ──────────────────────────────────────
  static BreveteInfo _construirResultado({
    required bool tieneBrevete,
    DateTime? fechaVencimiento,
    String? restricciones,
    String? categoria,
    String? advertencia,
  }) {
    if (!tieneBrevete) {
      return const BreveteInfo(
        estado: 'SIN_BREVETE',
        bloquea: true,
        mensaje: '⛔ Este DNI no tiene brevete registrado. No puede salir hasta verificar.',
      );
    }

    if (fechaVencimiento == null) {
      return BreveteInfo.desconocido('Brevete registrado pero sin fecha de vencimiento');
    }

    final hoy  = DateTime.now();
    final dias = fechaVencimiento.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
    final fv   = '${fechaVencimiento.day.toString().padLeft(2,'0')}/'
                 '${fechaVencimiento.month.toString().padLeft(2,'0')}/'
                 '${fechaVencimiento.year}';
    final aviso = _traducirRestriccion(restricciones);

    if (dias < 0) {
      return BreveteInfo(
        estado: 'VENCIDO', bloquea: true,
        mensaje: '⛔ BREVETE VENCIDO el $fv (hace ${dias.abs()} días). No puede salir.',
        fechaVenc: fv, diasRestantes: dias,
        restricciones: restricciones, restriccionAviso: aviso, categoria: categoria,
      );
    }
    if (dias <= 3) {
      return BreveteInfo(
        estado: 'CRITICO', bloquea: true,
        mensaje: '⛔ Brevete vence en $dias día(s) ($fv). Debe renovar ANTES de salir.',
        fechaVenc: fv, diasRestantes: dias,
        restricciones: restricciones, restriccionAviso: aviso, categoria: categoria,
      );
    }
    if (dias <= 7) {
      return BreveteInfo(
        estado: 'POR_VENCER', bloquea: false,
        mensaje: '⚠ Brevete vence en $dias días ($fv). Renovar URGENTE.',
        fechaVenc: fv, diasRestantes: dias,
        restricciones: restricciones, restriccionAviso: aviso, categoria: categoria,
      );
    }
    if (dias <= 90) {
      return BreveteInfo(
        estado: 'POR_VENCER', bloquea: false,
        mensaje: '⚠ Brevete vence el $fv (en $dias días). Recuerde renovarlo.',
        fechaVenc: fv, diasRestantes: dias,
        restricciones: restricciones, restriccionAviso: aviso, categoria: categoria,
      );
    }
    return BreveteInfo(
      estado: 'VIGENTE', bloquea: false,
      mensaje: advertencia != null
          ? 'Brevete vigente hasta $fv. ⚠ $advertencia'
          : 'Brevete vigente hasta $fv.',
      fechaVenc: fv, diasRestantes: dias,
      restricciones: restricciones, restriccionAviso: aviso, categoria: categoria,
    );
  }

  // ── API pública ───────────────────────────────────────────────────────────
  /// Consulta el brevete: revisa cache en BD → si expiró llama json.pe → actualiza cache.
  static Future<BreveteInfo> consultar(String dni, {String? placa}) async {
    if (_esMoto(placa)) return BreveteInfo.noAplica;

    dni = dni.trim();
    if (dni.isEmpty || !RegExp(r'^\d+$').hasMatch(dni)) {
      return BreveteInfo.desconocido('DNI inválido para consulta de brevete');
    }
    if (dni.length != 8) return BreveteInfo.noAplica; // extranjero

    MySQLConnection? conn;
    try {
      conn = await _abrirConexion();

      // 1. Leer cache
      final fila = await _leerCache(conn, dni);

      if (fila != null && _cacheVigente(fila)) {
        await _marcarRevision(conn, dni);
        return _desdeFila(fila);
      }

      // 2. Llamar a json.pe
      final info = await _consultarJsonpe(dni);

      if (!(info['ok'] as bool? ?? false)) {
        // API falló — usar cache viejo si existe
        if (fila != null) {
          await _marcarRevision(conn, dni);
          return _desdeFila(fila, advertencia: 'Datos pueden estar desactualizados');
        }
        await _guardarCache(conn, dni, {'tiene_brevete': false}, false);
        return BreveteInfo.desconocido('No se pudo verificar el brevete');
      }

      // 3. Guardar cache actualizado
      await _guardarCache(conn, dni, info, true);

      return _construirResultado(
        tieneBrevete:     info['tiene_brevete'] as bool? ?? false,
        fechaVencimiento: info['fecha_vencimiento'] as DateTime?,
        restricciones:    info['restricciones']?.toString(),
        categoria:        info['categoria']?.toString(),
      );
    } catch (e) {
      return BreveteInfo.desconocido('Error al verificar brevete');
    } finally {
      await conn?.close();
    }
  }

  static BreveteInfo _desdeFila(Map<String, dynamic> fila, {String? advertencia}) {
    final tb = fila['tiene_brevete'];
    final tieneBrevete = tb == 1 || tb?.toString() == '1' || tb == true;
    final fvStr = fila['fecha_vencimiento']?.toString();
    DateTime? fechaVenc;
    if (fvStr != null && fvStr.isNotEmpty && fvStr != 'null') {
      fechaVenc = DateTime.tryParse(fvStr.length > 10 ? fvStr.substring(0, 10) : fvStr);
    }
    return _construirResultado(
      tieneBrevete:     tieneBrevete,
      fechaVencimiento: fechaVenc,
      restricciones:    fila['restricciones']?.toString(),
      categoria:        fila['categoria']?.toString(),
      advertencia:      advertencia,
    );
  }
}
