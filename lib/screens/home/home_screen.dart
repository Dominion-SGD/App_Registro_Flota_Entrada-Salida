import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/brevete_service.dart';
import '../../services/offline_queue_service.dart';
import '../../utils/constants.dart';
import '../vehiculos/scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();

  // Vehículo
  final _placaCtrl = TextEditingController();
  String _tipo = 'Entrada';
  final _kmCtrl = TextEditingController();

  // Conductor
  final _dniCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  bool _personalEncontrado = false;
  bool _buscandoPersonal = false;
  String? _cargoPersonal;
  String? _areaPersonal;

  // Validación placa (API)
  bool _verificandoReg = false;
  bool _kmAutoLlenado = false;
  Timer? _placaTimer;

  // Mensajes de la API
  String? _bloqueoMensaje;   // rojo: no puede guardar
  bool _bloqueado = false;
  bool _soatBloquea = false;  // bloquea salida cuando SOAT vencido
  String? _avisoNaranja;     // advertencia: SOAT, brevete, grupo
  String? _avisoVerde;       // info positiva: estacionamiento, recojo
  String? _avisoInspeccion;  // primera salida sin checklist
  String? _avisoKm;          // advertencia diferencia de KM
  int? _ultimoKmRegistrado;  // último KM en BD (para validar diferencia)
  int _kmDiferenciaMax = 200;
  String? _errorConexion;
  String? _estacionamiento;
  int _pendientes = 0;
  bool _sincronizando = false;

  // Brevete conductor
  BreveteInfo? _brevete;
  bool _buscandoBrevete = false;

  // Autorización (solo si no está en personal)
  final _dniAutorizaCtrl = TextEditingController();
  final _nombreAutorizaCtrl = TextEditingController();

  // Destino — clave=display, valor=enum BD
  static const _destinosMap = <String, String>{
    'Almacén':       'almacen',
    'SOMA':          'soma',
    'Parquear':      'parquear',
    'Reunión':       'reunion',
    'Campo':         'Campo',
    'Obras':         'Obras',
    'Taller':        'Taller',
    'Base Minka':    'Base Minka',
    'Base Argentina':'Base Argentina',
  };
  String _destino = 'almacen';

  final _empresaCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _guardando = false;

  static const _autorizadores = {
    '40636269': 'MEZA MEZA WILLIAM ERNESTO - JEFE DE SSOMAC',
    '70918759': 'PERALTA FERNANDEZ CARLOS ALBERTO - AREA DE SISTEMAS',
    '10755495': 'PIÑIN CUEVA MIGUEL ANGEL - COORDINADOR GENERAL DE OPERACIONES TÉCNICAS',
    '08475080': 'GARCIA VALLEJO DANIEL - JEFE DE CONTROLLING',
    '05469554': 'ALONSO SANCHEZ IGNACIO - GERENTE DE ELECTRICIDAD',
    '45142362': 'PACHAMORO CASTRO CARLOS - COORDINADOR DE FLOTA Y TRANSPORTE',
    '43431212': 'VARGAS MEJIA JAVIER ALONZO - JEFE DE AREA DE LOGISTICA',
  };

  Future<MySQLConnection> _abrirConexion() async {
    final conn = await MySQLConnection.createConnection(
      host: dotenv.env['DB_HOST'] ?? '161.132.128.4',
      port: int.parse(dotenv.env['DB_PORT'] ?? '3306'),
      userName: dotenv.env['DB_USER'] ?? 'root',
      password: dotenv.env['DB_PASS'] ?? '',
      databaseName: dotenv.env['DB_NAME'] ?? 'dominion_gpd_energia',
      secure: true,
    );
    await conn.connect().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception('Timeout: no se pudo conectar a la base de datos en 8 segundos.'),
    );
    return conn;
  }

  @override
  void initState() {
    super.initState();
    _dniCtrl.addListener(_onDniChanged);
    _placaCtrl.addListener(_onPlacaChanged);
    _kmCtrl.addListener(_onKmChanged);
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    final n = await OfflineQueueService.contarPendientes();
    if (mounted) setState(() => _pendientes = n);
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    final result = await OfflineQueueService.sincronizar();
    await _cargarPendientes();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    final msg = result.sincronizados > 0
        ? '✅ ${result.sincronizados} registro(s) sincronizado(s)${result.fallidos > 0 ? ". ${result.fallidos} pendiente(s)." : "."}'
        : result.fallidos > 0
            ? 'Sin conexión. ${result.fallidos} registro(s) aún pendientes.'
            : 'No hay registros pendientes.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: result.sincronizados > 0 ? Colors.green.shade700 : Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  void dispose() {
    _placaTimer?.cancel();
    _placaCtrl.dispose();
    _kmCtrl.dispose();
    _dniCtrl.dispose();
    _nombreCtrl.dispose();
    _dniAutorizaCtrl.dispose();
    _nombreAutorizaCtrl.dispose();
    _empresaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  // ── Listeners ────────────────────────────────────────────────
  void _onDniChanged() {
    final dni = _dniCtrl.text.trim();
    if (dni.length == 8) _buscarPersonal(dni);
    if (dni.isEmpty) {
      setState(() {
        _nombreCtrl.clear();
        _cargoPersonal = null;
        _areaPersonal = null;
        _personalEncontrado = false;
        _dniAutorizaCtrl.clear();
        _nombreAutorizaCtrl.clear();
        _empresaCtrl.clear();
        _avisoNaranja = null;
        _brevete = null;
      });
    }
  }

  void _onPlacaChanged() {
    _placaTimer?.cancel(); // cancelar SIEMPRE, no solo cuando length >= 7
    final placa = _placaCtrl.text.trim().toUpperCase();
    if (placa.length >= 7) {
      _placaTimer = Timer(const Duration(milliseconds: 400), () {
        _procesarPlacaCompleta(placa);
      });
    } else if (placa.isEmpty) {
      _resetEstadoPlaca();
    }
  }

  void _resetEstadoPlaca() {
    setState(() {
      _tipo = 'Entrada';
      _kmCtrl.clear();
      _kmAutoLlenado = false;
      _bloqueoMensaje = null;
      _bloqueado = false;
      _soatBloquea = false;
      _avisoNaranja = null;
      _avisoVerde = null;
      _avisoInspeccion = null;
      _avisoKm = null;
      _ultimoKmRegistrado = null;
      _kmDiferenciaMax = 200;
      _verificandoReg = false;
      _errorConexion = null;
      _estacionamiento = null;
    });
  }

  bool _esHorarioRecojo() {
    final now = DateTime.now();
    final minutos = now.hour * 60 + now.minute;
    return minutos >= 11 * 60 && minutos < 16 * 60 + 30;
  }

  String _formatFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _onKmChanged() {
    if (_ultimoKmRegistrado == null) return;
    final km = int.tryParse(_kmCtrl.text.trim());
    if (km == null) {
      if (_avisoKm != null) setState(() => _avisoKm = null);
      return;
    }
    final diff = km - _ultimoKmRegistrado!;
    String? aviso;
    if (diff < 0) {
      aviso = 'KM ingresado ($km) es menor al último registrado ($_ultimoKmRegistrado km). Verifica el odómetro.';
    } else if (diff > _kmDiferenciaMax) {
      aviso = 'Diferencia de KM ($diff km) supera el máximo esperado ($_kmDiferenciaMax km). Verifica el odómetro.';
    }
    if (aviso != _avisoKm) setState(() => _avisoKm = aviso);
  }

  // ── Todas las validaciones de mobile.py en consulta directa MySQL ────────
  Future<void> _procesarPlacaCompleta(String placa) async {
    if (_verificandoReg) return;
    setState(() {
      _verificandoReg = true;
      _errorConexion = null;
      _bloqueoMensaje = null;
      _bloqueado = false;
      _soatBloquea = false;
      _avisoNaranja = null;
      _avisoVerde = null;
      _avisoInspeccion = null;
      _avisoKm = null;
      _ultimoKmRegistrado = null;
    });

    MySQLConnection? conn;
    try {
      conn = await _abrirConexion();
      final placaSinGuion = placa.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
      final placaConGuion = placa.toUpperCase();

      // ── 1. Detección entrada/salida ──────────────────────────────────────
      final resUltimo = await conn.execute(
        '''SELECT tipo, km_actual FROM registros_vehiculos
           WHERE REPLACE(REPLACE(UPPER(placa), ' ', ''), '-', '') = :p
             AND fecha <= DATE_ADD(NOW(), INTERVAL 5 MINUTE)
           ORDER BY fecha DESC, id DESC LIMIT 1''',
        {'p': placaSinGuion},
      );

      String tipoDetectado = 'Entrada';
      int? ultimoKm;

      if (resUltimo.rows.isNotEmpty) {
        final row = resUltimo.rows.first;
        final ultimoTipo = (row.colByName('tipo') ?? '').toString().toLowerCase().trim();
        final kmVal = row.colByName('km_actual');
        ultimoKm = kmVal != null ? int.tryParse(kmVal.toString()) : null;
        tipoDetectado = ultimoTipo == 'entrada' ? 'Salida' : 'Entrada';
      }

      if (!mounted) return;
      setState(() {
        _tipo = tipoDetectado;
        _ultimoKmRegistrado = ultimoKm;
        if (tipoDetectado == 'Salida' && ultimoKm != null) {
          _kmCtrl.text = ultimoKm.toString();
          _kmAutoLlenado = true;
        } else {
          _kmCtrl.clear();
          _kmAutoLlenado = false;
        }
      });

      // ── 2. SOAT (desde flota_maestro) ────────────────────────────────────
      final resSoat = await conn.execute(
        '''SELECT estado_soat, vencimiento_soat FROM flota_maestro
           WHERE placa = :p_con OR placa = :p_sin LIMIT 1''',
        {'p_con': placaConGuion, 'p_sin': placaSinGuion},
      );

      if (resSoat.rows.isNotEmpty) {
        final rowSoat = resSoat.rows.first;
        final estadoSoat = (rowSoat.colByName('estado_soat') ?? '').toString().trim().toUpperCase();
        final vencStr = rowSoat.colByName('vencimiento_soat')?.toString();

        bool soatVencido = false;
        String? mensajeSoat;

        if (vencStr != null && vencStr.isNotEmpty && vencStr != 'null') {
          try {
            final fechaVenc = DateTime.parse(vencStr.length > 10 ? vencStr.substring(0, 10) : vencStr);
            final hoy = DateTime.now();
            final dias = fechaVenc.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
            if (dias < 0) {
              soatVencido = true;
              mensajeSoat = '⛔ SOAT VENCIDO el ${_formatFecha(fechaVenc)} (hace ${dias.abs()} día(s)). El vehículo NO PUEDE SALIR.';
            }
          } catch (_) {}
        } else if (estadoSoat == 'VENCIDO') {
          soatVencido = true;
          mensajeSoat = '⛔ SOAT VENCIDO. El vehículo NO PUEDE SALIR hasta renovar el SOAT.';
        }

        if (soatVencido && mensajeSoat != null && mounted) {
          setState(() { _soatBloquea = true; _avisoNaranja = mensajeSoat; });
        }
      }

      // ── 3. Placa personal / Dominion (desde vehiculos_personal) ──────────
      final resVP = await conn.execute(
        '''SELECT placa_personal, placa_dominion, personal, dni,
                  puede_ingresar, estacionamiento
           FROM vehiculos_personal WHERE placa_personal = :p LIMIT 1''',
        {'p': placaConGuion},
      );

      if (resVP.rows.isNotEmpty) {
        // Es PLACA PERSONAL
        final vp = resVP.rows.first;
        final puedeIngresar = (vp.colByName('puede_ingresar') ?? '').toString().trim().toUpperCase();

        if (puedeIngresar == 'NO' && mounted) {
          setState(() {
            _bloqueado = true;
            _bloqueoMensaje = 'La placa $placaConGuion está marcada como NO HABILITADA. Contacte al supervisor.';
          });
        } else {
          final placaDom = (vp.colByName('placa_dominion') ?? '').toString().trim().toUpperCase();
          final estac = (vp.colByName('estacionamiento') ?? '').toString().trim();
          final horarioRecojo = _esHorarioRecojo();

          if (placaDom.isNotEmpty && placaDom != 'N/A' && placaDom != 'NA') {
            // ¿La Dominion está adentro?
            final resDomStatus = await conn.execute(
              '''SELECT tipo FROM registros_vehiculos WHERE placa = :p
                 AND fecha <= DATE_ADD(NOW(), INTERVAL 5 MINUTE)
                 ORDER BY fecha DESC, id DESC LIMIT 1''',
              {'p': placaDom},
            );

            final domAdentro = resDomStatus.rows.isNotEmpty &&
                (resDomStatus.rows.first.colByName('tipo') ?? '').toString().toLowerCase().trim() == 'entrada';

            if (domAdentro && mounted) {
              if (horarioRecojo) {
                setState(() => _avisoVerde = 'El vehículo Dominion $placaDom está en base. Puede ingresar a recoger materiales.');
              } else {
                setState(() {
                  _bloqueado = true;
                  _bloqueoMensaje = 'El vehículo Dominion $placaDom aún no ha salido. $placaConGuion no puede ingresar.';
                });
              }
            }

            // ¿Un compañero del grupo está adentro?
            if (!_bloqueado) {
              final resComp = await conn.execute(
                '''SELECT placa_personal, personal FROM vehiculos_personal
                   WHERE placa_dominion = :pd AND placa_personal <> :pp''',
                {'pd': placaDom, 'pp': placaConGuion},
              );

              for (final comp in resComp.rows) {
                final placaComp = (comp.colByName('placa_personal') ?? '').toString().trim();
                if (placaComp.isEmpty) continue;

                final resCompStatus = await conn.execute(
                  '''SELECT tipo FROM registros_vehiculos WHERE placa = :p
                     AND fecha <= DATE_ADD(NOW(), INTERVAL 5 MINUTE)
                     ORDER BY fecha DESC, id DESC LIMIT 1''',
                  {'p': placaComp},
                );

                if (resCompStatus.rows.isNotEmpty &&
                    (resCompStatus.rows.first.colByName('tipo') ?? '').toString().toLowerCase().trim() == 'entrada') {
                  final nombreComp = (comp.colByName('personal') ?? 'compañero de cuadrilla').toString().trim();
                  if (mounted) {
                    if (horarioRecojo) {
                      setState(() { _avisoVerde ??= 'El vehículo $placaComp ($nombreComp) está en base. Puede ingresar a recoger materiales.'; });
                    } else {
                      setState(() {
                        _bloqueado = true;
                        _bloqueoMensaje = 'El vehículo $placaComp ($nombreComp) ya ocupa el lugar. No puede ingresar.';
                      });
                    }
                  }
                  break;
                }
              }
            }
          }

          // Guardar estacionamiento para mostrarlo en el snackbar al guardar
          if (!_bloqueado && estac.isNotEmpty && estac != 'null' && mounted) {
            setState(() => _estacionamiento = estac);
          }
        }
      } else {
        // Verificar si es PLACA DOMINION
        final resDomPersonal = await conn.execute(
          '''SELECT placa_personal, personal FROM vehiculos_personal
             WHERE placa_dominion = :p''',
          {'p': placaConGuion},
        );

        if (resDomPersonal.rows.isNotEmpty) {
          final horarioRecojo = _esHorarioRecojo();
          DateTime? mejorFecha;
          String? placaPersonalMejor;
          String? nombrePersonalMejor;

          for (final row in resDomPersonal.rows) {
            final placaP = (row.colByName('placa_personal') ?? '').toString().trim();
            if (placaP.isEmpty) continue;

            final resPs = await conn.execute(
              '''SELECT tipo, fecha FROM registros_vehiculos WHERE placa = :p
                 AND fecha <= DATE_ADD(NOW(), INTERVAL 5 MINUTE)
                 ORDER BY fecha DESC, id DESC LIMIT 1''',
              {'p': placaP},
            );

            if (resPs.rows.isNotEmpty &&
                (resPs.rows.first.colByName('tipo') ?? '').toString().toLowerCase().trim() == 'entrada') {
              final fechaStr = resPs.rows.first.colByName('fecha')?.toString();
              DateTime? fechaP;
              try { fechaP = fechaStr != null ? DateTime.tryParse(fechaStr) : null; } catch (_) {}
              if (mejorFecha == null || (fechaP != null && fechaP.isAfter(mejorFecha))) {
                mejorFecha = fechaP;
                placaPersonalMejor = placaP;
                nombrePersonalMejor = (row.colByName('personal') ?? 'personal del grupo').toString().trim();
              }
            }
          }

          if (placaPersonalMejor != null && mounted) {
            if (horarioRecojo) {
              setState(() => _avisoVerde = 'El vehículo $placaPersonalMejor ($nombrePersonalMejor) está en base. Puede ingresar a recoger materiales.');
            } else {
              setState(() => _avisoNaranja = 'Sacar el vehículo $placaPersonalMejor ($nombrePersonalMejor) porque ingresa placa Dominion $placaConGuion');
            }
          }
        }
      }

      // ── 4. Inspección — solo flota Dominion (flota_maestro) ────────────────
      if (tipoDetectado == 'Salida' && !_bloqueado) {
        final resFlota = await conn.execute(
          'SELECT 1 FROM flota_maestro WHERE placa = :p_con OR placa = :p_sin LIMIT 1',
          {'p_con': placaConGuion, 'p_sin': placaSinGuion},
        );
        if (resFlota.rows.isNotEmpty) {
          final insp = await _verificarInspeccion(conn, placaSinGuion);
          if (insp != null && mounted) {
            setState(() {
              _bloqueado      = insp['bloquea'] as bool? ?? false;
              _bloqueoMensaje = insp['mensaje'] as String?;
            });
          }
        }
      }

    } catch (e) {
      debugPrint('❌ _procesarPlacaCompleta: $e');
      if (mounted) setState(() => _errorConexion = 'Sin conexión a la BD — escribir manualmente los registros');
    } finally {
      await conn?.close();
      if (mounted) setState(() => _verificandoReg = false);
    }
  }

  // ── Búsqueda conductor: consulta directa a personal ──────────
  Future<void> _buscarPersonal(String dni) async {
    if (_buscandoPersonal) return;
    setState(() {
      _buscandoPersonal = true;
      _personalEncontrado = false;
      _cargoPersonal = null;
      _areaPersonal = null;
      _dniAutorizaCtrl.clear();
      _nombreAutorizaCtrl.clear();
      _avisoNaranja = null;
    });

    MySQLConnection? conn;
    try {
      conn = await _abrirConexion();
      final result = await conn.execute(
        'SELECT Nombre, CARGO, area FROM personal WHERE Documento = :dni LIMIT 1',
        {'dni': dni.trim()},
      );

      if (!mounted) return;

      if (result.rows.isNotEmpty) {
        final row = result.rows.first;
        setState(() {
          _nombreCtrl.text = row.colByName('Nombre')?.toString() ?? '';
          _cargoPersonal = row.colByName('CARGO')?.toString();
          _areaPersonal = row.colByName('area')?.toString();
          _personalEncontrado = true;
          _empresaCtrl.text = 'DOMINION';
        });
        // Verificar brevete en paralelo (no bloquea el flujo del formulario)
        _verificarBrevete(dni);
      } else {
        setState(() {
          _nombreCtrl.clear();
          _cargoPersonal = null;
          _areaPersonal = null;
          _personalEncontrado = false;
          _empresaCtrl.clear();
          _brevete = null;
        });
      }
    } catch (e) {
      debugPrint('❌ _buscarPersonal: $e');
      // Conexión fallida — el operador puede escribir el nombre manualmente
    } finally {
      await conn?.close();
      if (mounted) setState(() => _buscandoPersonal = false);
    }
  }

  Future<void> _verificarBrevete(String dni) async {
    if (_buscandoBrevete) return;
    if (mounted) setState(() { _buscandoBrevete = true; _brevete = null; });
    try {
      final result = await BreveteService.consultar(
        dni,
        placa: _placaCtrl.text.trim(),
      );
      if (mounted) setState(() => _brevete = result);
    } catch (_) {
      // Silencioso — brevete no crítico para el flujo
    } finally {
      if (mounted) setState(() => _buscandoBrevete = false);
    }
  }

  // ── Inspección diaria ─────────────────────────────────────────
  String _mCheckCondicion(String tabla) {
    final comunes = <String>[
      'Neumáticos Delanteros (cocada)',
      'Neumáticos Traseros (cocada)',
      'Aros (Deformación, Saliente con riesgo)',
      'Espejo retrovisor interior',
      'Cerradura puertas',
      'Manijas exteriores de puerta',
      'Manijas interiores de lunas',
      'Parabrisas (Rajadura)',
      'Faros delanteros y posteriores',
      'Direccionales delant. y post.',
      'Luces de frenos',
      'Luces de retroceso',
      'Luces de emergencia',
      'Llanta de repuesto',
      'Triángulos de Seg. (2)',
      'Destornillador / Alicate',
      'Medidor Pres. de aire',
      'Fuga de fluidos',
    ];
    final extras = <String>[];
    if (tabla == 'inspecciones_minivan_livianos') {
      extras.addAll([
        'Espejo retrovisor Derecho', 'Espejo retrovisor Izquierdo',
        'Claxon', 'Nivel de aceite', 'Estado de frenos',
        'Llave de rueda', 'Gata', 'Llaves Mixta N° 10, 12',
        'Listado de botiquín P.A', 'Alarme de Retroceso',
      ]);
    } else if (tabla == 'inspecciones_hidroelevador_teko') {
      extras.addAll([
        'Espejo retrovisor Derecho', 'Espejo retrovisor Izquierdo',
        'Claxon', 'Nivel de aceite', 'Estado de frenos',
        'Llave de rueda', 'Gata', 'Llaves Mixta N° 10, 12',
        'Alarme de Retroceso',
      ]);
    } else {
      // inspecciones_camion_grua — nombres ligeramente distintos
      extras.addAll([
        'Espejo retrovisor Derecho-Izquierdo',
        'Claxón', 'Niveles de aceite', 'Estado de freno',
        'Gata, Llave de rueda', 'Llaves Mixta N° 10, 12',
        'Alarma de retroceso',
      ]);
    }
    return [...comunes, ...extras]
        .map((c) => "UPPER(TRIM(`$c`)) = 'M'")
        .join('\n    OR ');
  }

  Future<Map<String, dynamic>?> _verificarInspeccion(
    MySQLConnection conn, String placaSinGuion,
  ) async {
    const tablas = [
      ('inspecciones_minivan_livianos',   'MINIVAN / LIVIANO'),
      ('inspecciones_hidroelevador_teko', 'HIDROELEVADOR / TEKO'),
      ('inspecciones_camion_grua',        'CAMIÓN GRUA'),
    ];

    for (final (tabla, etiqueta) in tablas) {
      try {
        final mCond = _mCheckCondicion(tabla);
        final res = await conn.execute('''
          SELECT
            (firma IS NOT NULL AND LENGTH(firma) > 0) AS tiene_firma,
            (firma_supervisor IS NOT NULL AND LENGTH(firma_supervisor) > 0) AS tiene_firma_sup,
            CASE WHEN ($mCond) THEN 1 ELSE 0 END AS tiene_mal
          FROM `$tabla`
          WHERE REPLACE(REPLACE(UPPER(placa), ' ', ''), '-', '') = :p
            AND DATE(fecha_inspeccion) = CURDATE()
          ORDER BY id DESC LIMIT 1
        ''', {'p': placaSinGuion});

        if (res.rows.isEmpty) continue;

        final row         = res.rows.first;
        final tieneFirma  = row.colByName('tiene_firma')?.toString()    == '1';
        final tieneFirmaSup = row.colByName('tiene_firma_sup')?.toString() == '1';
        final tieneMal    = row.colByName('tiene_mal')?.toString()      == '1';

        if (tieneMal) {
          return {
            'bloquea': true,
            'mensaje': '⛔ La inspección ($etiqueta) tiene ítems en MAL estado. El vehículo NO puede salir hasta que sean corregidos.',
          };
        }
        if (!tieneFirma || !tieneFirmaSup) {
          final faltante = !tieneFirma && !tieneFirmaSup
              ? 'firma del conductor y del supervisor CAPA'
              : !tieneFirma ? 'firma del conductor' : 'firma del supervisor CAPA';
          return {
            'bloquea': true,
            'mensaje': '⛔ Inspección $etiqueta incompleta: falta $faltante. El vehículo NO puede salir.',
          };
        }
        return null; // Inspección OK → puede salir
      } catch (e) {
        debugPrint('Inspección $tabla: $e');
        // Tabla sin registro hoy o error de columna — intentar siguiente
      }
    }

    // Ninguna tabla tiene inspección de hoy
    return {
      'bloquea': true,
      'mensaje': '⛔ Primera salida del día sin inspección (checklist) registrada hoy. Realizar la inspección antes de salir.',
    };
  }

  // ── Escáner ──────────────────────────────────────────────────
  Future<void> _escanearPlaca() async {
    final res = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => const ScannerScreen(
        titulo: 'Escanear Placa / QR',
        instruccion: 'Apunta al código QR o código de barras de la placa',
      ),
    ));
    if (res != null && mounted) {
      final clean = res.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      _placaCtrl.text = _formatPlaca(clean);
    }
  }

  Future<void> _escanearDNI() async {
    final res = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => const ScannerScreen(
        titulo: 'Escanear DNI',
        instruccion: 'Apunta al código de barras del DNI',
      ),
    ));
    if (res != null && mounted) {
      final partes = res.split('@');
      if (partes.length >= 5) {
        final dni = partes[4].trim();
        _dniCtrl.text = dni;
        _nombreCtrl.text = '${partes[2].trim()} ${partes[1].trim()}';
        _buscarPersonal(dni);
      } else {
        _dniCtrl.text = res.trim();
      }
    }
  }

  String _formatPlaca(String clean) {
    if (clean.isEmpty) return clean;
    if (RegExp(r'^[A-Z]').hasMatch(clean)) {
      final s = clean.length > 6 ? clean.substring(0, 6) : clean;
      return s.length <= 3 ? s : '${s.substring(0, 3)}-${s.substring(3)}';
    } else {
      final s = clean.length > 6 ? clean.substring(0, 6) : clean;
      return s.length <= 4 ? s : '${s.substring(0, 4)}-${s.substring(4)}';
    }
  }

  // ── Guardar: INSERT a BD; si falla, encola offline ──────────
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bloqueado) return;

    final tipoGuardado = _tipo;
    final usuario = context.read<AuthProvider>().usuario;
    setState(() => _guardando = true);

    // Construir params una sola vez — se reutilizan online y offline
    final now = DateTime.now();
    final fechaStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final params = <String, dynamic>{
      'placa':           _placaCtrl.text.trim(),
      'dni':             _dniCtrl.text.trim(),
      'nombre':          _nombreCtrl.text.trim(),
      'cargo':           _cargoPersonal ?? 'NO REGISTRADO',
      'area':            _areaPersonal ?? 'NO REGISTRADO',
      'dni_autoriza':    _personalEncontrado ? 'REGISTRADO' : _dniAutorizaCtrl.text.trim(),
      'nombre_autoriza': _personalEncontrado ? 'SISTEMA'    : _nombreAutorizaCtrl.text.trim(),
      'BASE':            usuario?.base ?? '',
      'base_origen':     usuario?.base ?? '',
      'Base_Dirigida':   usuario?.base ?? '',
      'km':              int.tryParse(_kmCtrl.text.trim()) ?? 0,
      'tipo':            tipoGuardado.toLowerCase(),
      'obs':             _obsCtrl.text.trim(),
      'destino':         _destino,
      'usuario_id':      usuario?.id ?? 0,
      'empresa':         _empresaCtrl.text.trim().isEmpty ? 'DOMINION' : _empresaCtrl.text.trim(),
      'fecha':           fechaStr,
    };

    MySQLConnection? conn;
    try {
      conn = await _abrirConexion();
      await conn.execute('''
        INSERT INTO registros_vehiculos
          (placa, dni_conductor, nombre_conductor, cargo_conductor, area_conductor,
           dni_autoriza, nombre_autoriza, BASE, base_origen, Base_Dirigida,
           km_actual, tipo, observacion, destino, usuario_id, empresa, fecha)
        VALUES
          (:placa, :dni, :nombre, :cargo, :area,
           :dni_autoriza, :nombre_autoriza, :BASE, :base_origen, :Base_Dirigida,
           :km, :tipo, :obs, :destino, :usuario_id, :empresa, NOW())
      ''', params);

      if (!mounted) return;
      final estacMsg = _estacionamiento;
      _limpiarFormulario();
      final mensaje = estacMsg != null && estacMsg.isNotEmpty
          ? '✅ Registro de $tipoGuardado guardado. Dirigirse al estacionamiento: $estacMsg'
          : 'Registro de $tipoGuardado guardado correctamente';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje)),
        ]),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ));
    } catch (_) {
      // Sin conexión: guardar en cola local
      if (!mounted) return;
      try {
        await OfflineQueueService.encolar(params);
        await _cargarPendientes();
        if (!mounted) return;
        final estacMsg = _estacionamiento;
        _limpiarFormulario();
        final msgOffline = estacMsg != null && estacMsg.isNotEmpty
            ? '📴 Sin conexión. Guardado localmente. Estacionamiento: $estacMsg'
            : '📴 Sin conexión. Guardado localmente — se sincronizará al recuperar internet.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msgOffline)),
          ]),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 6),
        ));
      } catch (e2) {
        if (mounted) setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar: $e2'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      await conn?.close();
    }
  }

  void _limpiarFormulario() {
    _placaTimer?.cancel();
    setState(() {
      _guardando = false;
      _placaCtrl.clear();
      _kmCtrl.clear();
      _kmAutoLlenado = false;
      _verificandoReg = false;
      _tipo = 'Entrada';
      _bloqueoMensaje = null;
      _bloqueado = false;
      _soatBloquea = false;
      _avisoNaranja = null;
      _avisoVerde = null;
      _avisoInspeccion = null;
      _avisoKm = null;
      _ultimoKmRegistrado = null;
      _kmDiferenciaMax = 200;
      _dniCtrl.clear();
      _nombreCtrl.clear();
      _cargoPersonal = null;
      _areaPersonal = null;
      _personalEncontrado = false;
      _dniAutorizaCtrl.clear();
      _nombreAutorizaCtrl.clear();
      _empresaCtrl.clear();
      _obsCtrl.clear();
      _destino = 'almacen';
      _errorConexion = null;
      _estacionamiento = null;
      _brevete = null;
      _buscandoBrevete = false;
    });
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final base = usuario?.base ?? '';
    final garita = usuario?.garita ?? '';
    final nombre = usuario?.nombreCompleto ?? 'Usuario';
    final esEntrada = _tipo == 'Entrada';
    final colorTipo = esEntrada ? AppColors.entrada : AppColors.salida;
    // SOAT solo bloquea SALIDA (igual que el backend: validar_soat + tipo == "salida")
    final soatBloquea = _soatBloquea && _tipo == 'Salida';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DOM_FLOTA',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Bienvenido, $nombre',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ],
        ),
        actions: [
          if (garita.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(garita,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('Base: $base',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber.shade300,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          if (_pendientes > 0)
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: _sincronizando
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 22),
                  tooltip: 'Sincronizar $_pendientes registro(s) pendiente(s)',
                  onPressed: _sincronizando ? null : _sincronizar,
                ),
                Positioned(
                  right: 6, top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.amber,
                    child: Text('$_pendientes',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 22),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            // ── Vehículo ──
            _seccion(
              titulo: 'DATOS DEL VEHÍCULO',
              color: AppColors.primary,
              icono: Icons.directions_car_rounded,
              hijos: [
                _campoEscaner(
                  ctrl: _placaCtrl,
                  label: 'PLACA',
                  onEscanear: _escanearPlaca,
                  formatters: [PlacaFormatter()],
                ),
                const SizedBox(height: 12),
                _dropdownTipo(colorTipo),
                const SizedBox(height: 12),
                _campoKm(),

                // ── Mensajes de la API ──
                if (_bloqueoMensaje != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _bloqueoMensaje!,
                    color: Colors.red.shade700,
                    fondo: Colors.red.shade50,
                    icono: Icons.block_rounded,
                  ),
                ],
                if (_avisoInspeccion != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _avisoInspeccion!,
                    color: Colors.orange.shade800,
                    fondo: Colors.orange.shade50,
                    icono: Icons.assignment_late_rounded,
                  ),
                ],
                if (_avisoNaranja != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _avisoNaranja!,
                    color: Colors.orange.shade800,
                    fondo: Colors.orange.shade50,
                    icono: Icons.warning_amber_rounded,
                  ),
                ],
                if (_avisoVerde != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _avisoVerde!,
                    color: Colors.green.shade700,
                    fondo: Colors.green.shade50,
                    icono: Icons.check_circle_outline_rounded,
                  ),
                ],
                if (_avisoKm != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _avisoKm!,
                    color: Colors.orange.shade800,
                    fondo: Colors.orange.shade50,
                    icono: Icons.speed_rounded,
                  ),
                ],
                if (_errorConexion != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _errorConexion!,
                    color: Colors.red.shade800,
                    fondo: Colors.red.shade50,
                    icono: Icons.wifi_off_rounded,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ── Conductor ──
            _seccion(
              titulo: 'DATOS DEL CONDUCTOR',
              color: const Color(0xFF00695C),
              icono: Icons.person_rounded,
              hijos: [
                _campoEscaner(
                  ctrl: _dniCtrl,
                  label: 'DNI CONDUCTOR',
                  onEscanear: _escanearDNI,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                _campoNombre(),

                // ── Brevete ──
                if (_buscandoBrevete) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    minHeight: 2,
                  ),
                ],
                if (_brevete != null &&
                    _brevete!.estado != 'NO_APLICA' &&
                    _brevete!.mensaje.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _brevete!.mensaje,
                    color: _brevete!.bloquea
                        ? Colors.red.shade700
                        : _brevete!.estado == 'VIGENTE'
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                    fondo: _brevete!.bloquea
                        ? Colors.red.shade50
                        : _brevete!.estado == 'VIGENTE'
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                    icono: _brevete!.bloquea
                        ? Icons.block_rounded
                        : _brevete!.estado == 'VIGENTE'
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                  ),
                  if (_brevete!.restriccionAviso != null) ...[
                    const SizedBox(height: 6),
                    _banner(
                      mensaje: '⚠ Restricción: ${_brevete!.restriccionAviso!}',
                      color: Colors.orange.shade800,
                      fondo: Colors.orange.shade50,
                      icono: Icons.info_outline_rounded,
                    ),
                  ],
                ],

                if (!_personalEncontrado &&
                    _dniCtrl.text.isNotEmpty &&
                    !_buscandoPersonal) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: 'DNI no registrado en personal. Requiere autorización.',
                    color: Colors.orange.shade800,
                    fondo: Colors.orange.shade50,
                    icono: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 12),
                  _dropdownAutoriza(),
                  const SizedBox(height: 12),
                  _campo(
                    ctrl: _dniAutorizaCtrl,
                    label: 'DNI AUTORIZA',
                    teclado: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  _campo(ctrl: _nombreAutorizaCtrl, label: 'NOMBRE AUTORIZA'),
                ],
                const SizedBox(height: 12),
                _campoFijo(label: 'BASE', valor: base),
              ],
            ),
            const SizedBox(height: 12),

            // ── Destino ──
            _seccion(
              titulo: 'DESTINO Y EMPRESA',
              color: const Color(0xFF6A1B9A),
              icono: Icons.location_on_rounded,
              hijos: [
                _dropdownDestino(),
                const SizedBox(height: 12),
                _campo(ctrl: _empresaCtrl, label: 'EMPRESA', obligatorio: false),
                const SizedBox(height: 12),
                _campo(
                  ctrl: _obsCtrl,
                  label: 'OBSERVACIÓN (opcional)',
                  obligatorio: false,
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Botón guardar ──
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_guardando || _bloqueado || soatBloquea || (_brevete?.bloquea ?? false))
                    ? null
                    : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : (_bloqueado || (_brevete?.bloquea ?? false))
                        ? const Icon(Icons.block_rounded)
                        : const Icon(Icons.save_rounded),
                label: Text(
                  _guardando
                      ? 'GUARDANDO...'
                      : _bloqueado
                          ? 'INGRESO BLOQUEADO'
                          : (_brevete?.bloquea ?? false)
                              ? 'BREVETE BLOQUEADO'
                              : 'GUARDAR REGISTRO',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bloqueado ? Colors.grey : colorTipo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────
  Widget _seccion({
    required String titulo,
    required Color color,
    required IconData icono,
    required List<Widget> hijos,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(icono, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(titulo,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.8)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: hijos),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required String mensaje,
    required Color color,
    required Color fondo,
    required IconData icono,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(mensaje,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _campoEscaner({
    required TextEditingController ctrl,
    required String label,
    required VoidCallback onEscanear,
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? formatters,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: teclado,
      inputFormatters: formatters,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: _deco(label).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner_rounded,
              color: AppColors.primary),
          onPressed: onEscanear,
        ),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
    );
  }

  Widget _campo({
    required TextEditingController ctrl,
    required String label,
    bool obligatorio = true,
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: teclado,
      inputFormatters: formatters,
      maxLines: maxLines,
      decoration: _deco(label),
      validator: obligatorio
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null
          : null,
    );
  }

  Widget _campoNombre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _nombreCtrl,
          readOnly: _buscandoPersonal || _personalEncontrado,
          decoration: _deco('NOMBRE Y APELLIDO').copyWith(
            filled: true,
            fillColor: _personalEncontrado
                ? Colors.green.shade50
                : Colors.grey.shade50,
            suffixIcon: _buscandoPersonal
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : _personalEncontrado
                    ? const Icon(Icons.check_circle,
                        color: AppColors.entrada, size: 20)
                    : null,
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
        ),
        if (_cargoPersonal != null && _cargoPersonal!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.badge_outlined,
                size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(_cargoPersonal!,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic)),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _dropdownAutoriza() {
    return DropdownButtonFormField<String>(
      decoration: _deco('AUTORIZADO POR').copyWith(
        prefixIcon: const Icon(Icons.verified_user_outlined,
            color: Colors.deepOrange, size: 20),
      ),
      hint: const Text('Seleccionar autorizador',
          style: TextStyle(fontSize: 13)),
      items: _autorizadores.entries.map((e) {
        return DropdownMenuItem(
          value: e.key,
          child: Text(e.value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (dni) {
        if (dni == null) return;
        setState(() {
          _dniAutorizaCtrl.text = dni;
          _nombreAutorizaCtrl.text = _autorizadores[dni] ?? '';
        });
      },
      validator: (v) => v == null ? 'Seleccione quien autoriza' : null,
    );
  }

  Widget _campoKm() {
    return TextFormField(
      controller: _kmCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: _deco('KM ACTUAL').copyWith(
        filled: true,
        fillColor: _kmAutoLlenado ? Colors.blue.shade50 : Colors.grey.shade50,
        suffixIcon: _verificandoReg
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              )
            : _kmAutoLlenado
                ? Icon(Icons.auto_fix_high, color: Colors.blue.shade700, size: 20)
                : null,
        helperText: _kmAutoLlenado
            ? 'KM del último registro de entrada'
            : _tipo == 'Entrada'
                ? 'Ingrese el KM actual del vehículo'
                : null,
        helperStyle: TextStyle(
            fontSize: 11,
            color:
                _kmAutoLlenado ? Colors.blue.shade700 : AppColors.textSecondary),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
    );
  }

  Widget _campoFijo({required String label, required String valor}) {
    return TextFormField(
      initialValue: valor,
      readOnly: true,
      style: const TextStyle(fontWeight: FontWeight.bold),
      decoration: _deco(label)
          .copyWith(filled: true, fillColor: Colors.grey.shade100),
    );
  }

  Widget _dropdownTipo(Color colorTipo) {
    return InputDecorator(
      decoration: _deco('TIPO').copyWith(
        suffixIcon: _verificandoReg
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              )
            : null,
      ),
      child: DropdownButton<String>(
        value: _tipo,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['Entrada', 'Salida'].map((t) {
          final c = t == 'Entrada' ? AppColors.entrada : AppColors.salida;
          return DropdownMenuItem(
            value: t,
            child: Row(children: [
              Icon(
                  t == 'Entrada'
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  color: c,
                  size: 18),
              const SizedBox(width: 8),
              Text(t,
                  style:
                      TextStyle(color: c, fontWeight: FontWeight.w600)),
            ]),
          );
        }).toList(),
        onChanged: (v) => setState(() => _tipo = v!),
      ),
    );
  }

  Widget _dropdownDestino() {
    return DropdownButtonFormField<String>(
      key: ValueKey(_destino),
      initialValue: _destino,
      decoration: _deco('DESTINO'),
      items: _destinosMap.entries
          .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key)))
          .toList(),
      onChanged: (v) => setState(() => _destino = v!),
      validator: (v) => v == null ? 'Seleccione destino' : null,
    );
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.4),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      );
}

class PlacaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (clean.isEmpty) {
      return newValue.copyWith(
          text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    String formatted;
    final startsWithLetter = RegExp(r'^[A-Z]').hasMatch(clean);

    if (startsWithLetter) {
      final s = clean.length > 6 ? clean.substring(0, 6) : clean;
      formatted = s.length <= 3 ? s : '${s.substring(0, 3)}-${s.substring(3)}';
    } else {
      final s = clean.length > 6 ? clean.substring(0, 6) : clean;
      formatted = s.length <= 4 ? s : '${s.substring(0, 4)}-${s.substring(4)}';
    }

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
