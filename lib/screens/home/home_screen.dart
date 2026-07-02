import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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
  bool _bloqueado = false;
  bool _soatBloquea = false;
  bool _combustibleBloquea = false;
  String? _avisoVerde;
  String? _avisoKm;
  int? _ultimoKmRegistrado;
  int _kmDiferenciaMax = 200;
  String? _errorConexion;
  int _pendientes = 0;
  bool _sincronizando = false;

  // Brevete conductor
  BreveteInfo? _brevete;
  bool _buscandoBrevete = false;

  // Modal KM
  Timer? _kmModalTimer;
  String? _lastKmAviso;
  bool _esPrimeraSalidaDia = false;

  // Autorización (solo si no está en personal)
  final _dniAutorizaCtrl = TextEditingController();
  final _nombreAutorizaCtrl = TextEditingController();

  // Destino
  static const _destinosMap = <String, String>{
    'Almacén':        'almacen',
    'SOMA':           'soma',
    'Parquear':       'parquear',
    'Reunión':        'reunion',
    'Campo':          'Campo',
    'Obras':          'Obras',
    'Taller':         'Taller',
    'Base Minka':     'Base Minka',
    'Base Argentina': 'Base Argentina',
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
    '41187576': 'JIMENEZ FLORES JULIO MARTIN - JEFE DE AREA DE LOGISTICA',
  };

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
    _kmModalTimer?.cancel();
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
        _brevete = null;
      });
    }
  }

  void _onPlacaChanged() {
    _placaTimer?.cancel();
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
    _kmModalTimer?.cancel();
    _lastKmAviso = null;
    setState(() {
      _tipo = 'Entrada';
      _kmCtrl.clear();
      _kmAutoLlenado = false;
      _esPrimeraSalidaDia = false;
      _bloqueado = false;
      _soatBloquea = false;
      _combustibleBloquea = false;
      _avisoVerde = null;
      _avisoKm = null;
      _ultimoKmRegistrado = null;
      _kmDiferenciaMax = 200;
      _verificandoReg = false;
      _errorConexion = null;
    });
  }

  void _onKmChanged() {
    _kmModalTimer?.cancel();
    if (_ultimoKmRegistrado == null) return;
    final km = int.tryParse(_kmCtrl.text.trim());
    if (km == null) {
      if (_avisoKm != null) setState(() => _avisoKm = null);
      _lastKmAviso = null;
      return;
    }
    final diff = km - _ultimoKmRegistrado!;
    String? aviso;
    if (diff < 0) {
      aviso = 'El KM ingresado ($km) es menor al último registrado ($_ultimoKmRegistrado km).\n\nPor favor, ACÉRQUESE AL TABLERO DEL VEHÍCULO Y VERIFIQUE EL KM CORRECTO.';
    } else if (diff > _kmDiferenciaMax) {
      aviso = 'La diferencia de KM ingresado ($km) con el último registrado ($_ultimoKmRegistrado km) es de $diff km, superando el máximo esperado de $_kmDiferenciaMax km.\n\nPor favor, ACÉRQUESE AL TABLERO DEL VEHÍCULO Y VERIFIQUE EL KM CORRECTO.';
    }
    if (aviso != _avisoKm) setState(() => _avisoKm = aviso);
    if (aviso != null && aviso != _lastKmAviso) {
      _kmModalTimer = Timer(const Duration(milliseconds: 900), () {
        _lastKmAviso = aviso;
        _mostrarModal(titulo: 'KILOMETRAJE INCORRECTO', mensaje: aviso!, esError: false);
      });
    }
  }

  // ── Respuestas mock para pruebas sin servidor ─────────────────
  static const _mockPlacas = <String, Map<String, dynamic>>{
    // Salida normal — KM pre-llenado
    'TST-001': {
      'tipo_recomendado': 'salida', 'ultimo_km': 54200, 'ultimo_km_registrado': 54200,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': false,
      'soat_bloquea': false, 'soat_mensaje': '',
      'puede_ingresar': true, 'motivo_bloqueo': null,
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
    },
    // Entrada — sin KM previo
    'TST-002': {
      'tipo_recomendado': 'entrada', 'ultimo_km': null, 'ultimo_km_registrado': 48900,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': false,
      'soat_bloquea': false, 'soat_mensaje': '',
      'puede_ingresar': true, 'motivo_bloqueo': null,
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
    },
    // SOAT vencido — bloquea salida
    'TST-003': {
      'tipo_recomendado': 'salida', 'ultimo_km': 31000, 'ultimo_km_registrado': 31000,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': false,
      'soat_bloquea': true, 'soat_mensaje': '⛔ SOAT VENCIDO el 15/03/2025 (hace 109 días). El vehículo NO PUEDE SALIR.',
      'puede_ingresar': true, 'motivo_bloqueo': null,
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
    },
    // Placa personal bloqueada por grupo
    'TST-004': {
      'tipo_recomendado': 'entrada', 'ultimo_km': null, 'ultimo_km_registrado': null,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': false,
      'soat_bloquea': false, 'soat_mensaje': '',
      'puede_ingresar': false,
      'motivo_bloqueo': 'El vehículo Dominion CHO-135 aún no ha salido. TST-004 no puede ingresar mientras el vehículo de empresa esté adentro.',
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
    },
    // Primera salida del día — KM naranja
    'TST-005': {
      'tipo_recomendado': 'salida', 'ultimo_km': null, 'ultimo_km_registrado': 67500,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': true,
      'soat_bloquea': false, 'soat_mensaje': '',
      'puede_ingresar': true, 'motivo_bloqueo': null,
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
    },
    // Combustible EBT (simula bloqueo nocturno)
    'TST-006': {
      'tipo_recomendado': 'entrada', 'ultimo_km': null, 'ultimo_km_registrado': 12400,
      'km_diferencia_maxima': 200, 'inspeccion_aplica': false,
      'soat_bloquea': false, 'soat_mensaje': '',
      'puede_ingresar': true, 'motivo_bloqueo': null,
      'aviso_personal_dentro': null, 'aviso_recojo_materiales': null,
      '_mock_combustible_bloquea': true,
    },
  };

  // ── Consulta placa vía REST API ───────────────────────────────
  Future<void> _procesarPlacaCompleta(String placa) async {
    if (_verificandoReg) return;
    setState(() {
      _verificandoReg = true;
      _errorConexion = null;
      _bloqueado = false;
      _soatBloquea = false;
      _combustibleBloquea = false;
      _avisoVerde = null;
      _avisoKm = null;
      _ultimoKmRegistrado = null;
    });

    final List<Map<String, dynamic>> pendingModals = [];

    try {
      // Placa mock (TST-XXX): responde sin llamar al servidor
      final mock = _mockPlacas[placa.toUpperCase()];
      final data = mock != null
          ? Map<String, dynamic>.from(mock)
          : await apiService.post('/mobile/vehiculo/consultar-por-placa', {'placa': placa});

      if (!mounted) return;

      // ── Tipo recomendado ──────────────────────────────────────
      final tipoRecomendado = (data['tipo_recomendado'] ?? 'entrada').toString();
      final tipoUI = tipoRecomendado == 'salida' ? 'Salida' : 'Entrada';

      final ultimoKm         = data['ultimo_km'] as int?;
      final ultimoKmReg      = data['ultimo_km_registrado'] as int?;
      final kmDifMax         = (data['km_diferencia_maxima'] as num?)?.toInt() ?? 200;
      // inspeccion_aplica → true = primera salida del día (sin importar si hay checklist)
      final inspeccionAplica = data['inspeccion_aplica'] as bool? ?? false;
      // INSPECCIONES DESHABILITADAS POR AHORA — cuando se reactiven:
      // final inspeccionKm       = data['inspeccion_km'] as int?;
      // final inspeccionEncontrada = data['inspeccion_encontrada'] as bool? ?? false;

      setState(() {
        _tipo                = tipoUI;
        _ultimoKmRegistrado  = ultimoKmReg;
        _kmDiferenciaMax     = kmDifMax;
        _esPrimeraSalidaDia  = inspeccionAplica;
        if (ultimoKm != null) {
          _kmCtrl.text   = ultimoKm.toString();
          _kmAutoLlenado = true;
        } else {
          _kmCtrl.clear();
          _kmAutoLlenado = false;
        }
      });

      // ── SOAT ─────────────────────────────────────────────────
      final soatBloquea = data['soat_bloquea'] as bool? ?? false;
      final soatMensaje = (data['soat_mensaje'] ?? '').toString();
      if (soatBloquea && mounted) {
        setState(() => _soatBloquea = true);
        if (soatMensaje.isNotEmpty) {
          pendingModals.add({'titulo': 'SOAT VENCIDO', 'mensaje': soatMensaje, 'esError': true});
        }
      }

      // ── Placa personal / Dominion / grupo ────────────────────
      final puedeIngresar        = data['puede_ingresar'] as bool? ?? true;
      final motivoBloqueo        = data['motivo_bloqueo'] as String?;
      final avisoPersonalDentro  = data['aviso_personal_dentro'] as String?;
      final avisoRecojo          = data['aviso_recojo_materiales'] as String?;

      if (!puedeIngresar && motivoBloqueo != null && mounted) {
        setState(() => _bloqueado = true);
        pendingModals.add({'titulo': 'INGRESO BLOQUEADO', 'mensaje': motivoBloqueo, 'esError': true});
      } else if (avisoRecojo != null && mounted) {
        setState(() => _avisoVerde = avisoRecojo);
      } else if (avisoPersonalDentro != null && mounted) {
        pendingModals.add({'titulo': 'AVISO DE GRUPO', 'mensaje': avisoPersonalDentro, 'esError': false});
      }

      // ── Combustible EBT (control nocturno 21:00–05:00) ───────
      if (!_bloqueado && tipoRecomendado == 'entrada') {
        // Mock: TST-006 simula bloqueo EBT nocturno
        final mockFuelBloquea = data['_mock_combustible_bloquea'] as bool? ?? false;
        if (mockFuelBloquea && mounted) {
          setState(() => _combustibleBloquea = true);
          pendingModals.add({
            'titulo': 'CONTROL DE COMBUSTIBLE',
            'mensaje': '⛽ Debe cargar combustible antes de ingresar (control nocturno EBT)',
            'esError': true,
          });
        } else {
          try {
            final fuelData = await apiService.get(
              '/combustible/verificar?placa=${Uri.encodeComponent(placa)}',
            );
            final esEbt         = fuelData['es_ebt'] as bool? ?? false;
            final combustibleOk = fuelData['puede_ingresar'] as bool? ?? true;
            final fuelMsg       = (fuelData['mensaje'] ?? '').toString();
            if (esEbt && !combustibleOk && mounted) {
              setState(() => _combustibleBloquea = true);
              pendingModals.add({'titulo': 'CONTROL DE COMBUSTIBLE', 'mensaje': fuelMsg, 'esError': true});
            }
          } catch (_) {
            // Fuera de ventana nocturna o sin respuesta → no bloquear
          }
        }
      }

      // ── Inspecciones — DESHABILITADAS POR AHORA ──────────────
      // Se reactivarán cuando estén listos los checklists.
      // Campos disponibles en la respuesta: inspeccion_aplica, inspeccion_encontrada,
      // inspeccion_km, inspeccion_dni, inspeccion_tipo_vehiculo, inspeccion_mensaje.

    } catch (e) {
      debugPrint('❌ _procesarPlacaCompleta: $e');
      if (mounted) setState(() => _errorConexion = 'Sin conexión a la API — verificar red');
    } finally {
      if (mounted) setState(() => _verificandoReg = false);
    }

    for (final m in pendingModals) {
      if (!mounted) break;
      await _mostrarModal(
        titulo: m['titulo'] as String,
        mensaje: m['mensaje'] as String,
        esError: m['esError'] as bool? ?? false,
      );
    }
  }

  // ── Búsqueda conductor vía API (incluye brevete) ──────────────
  Future<void> _buscarPersonal(String dni) async {
    if (_buscandoPersonal) return;
    setState(() {
      _buscandoPersonal    = true;
      _buscandoBrevete     = true;
      _personalEncontrado  = false;
      _cargoPersonal       = null;
      _areaPersonal        = null;
      _dniAutorizaCtrl.clear();
      _nombreAutorizaCtrl.clear();
      _brevete = null;
    });

    try {
      final data = await apiService.post('/mobile/search-personal', {
        'documento': dni.trim(),
        'placa':     _placaCtrl.text.trim(),
      });

      if (!mounted) return;

      if (data['success'] == true) {
        final nombre   = (data['nombre']   ?? '').toString();
        final apellido = (data['apellido'] ?? '').toString();
        setState(() {
          _nombreCtrl.text    = '$nombre $apellido'.trim();
          _cargoPersonal      = data['cargo'] as String?;
          _areaPersonal       = data['area'] as String?;
          _personalEncontrado = true;
          _empresaCtrl.text   = 'DOMINION';
        });

        // Brevete incluido en la respuesta del backend
        final brevete = BreveteInfo(
          estado:           (data['brevete_estado'] ?? 'NO_APLICA').toString(),
          bloquea:          data['brevete_bloquea'] as bool? ?? false,
          mensaje:          (data['brevete_mensaje'] ?? '').toString(),
          fechaVenc:        data['brevete_fecha_venc'] as String?,
          diasRestantes:    data['brevete_dias_restantes'] as int?,
          restricciones:    data['brevete_restricciones'] as String?,
          restriccionAviso: data['brevete_restriccion_aviso'] as String?,
          categoria:        data['brevete_categoria'] as String?,
        );
        if (mounted) setState(() => _brevete = brevete);

        if (brevete.estado != 'NO_APLICA') {
          if (brevete.bloquea || (brevete.estado != 'VIGENTE' && brevete.mensaje.isNotEmpty)) {
            final titulo = brevete.bloquea ? 'BREVETE BLOQUEADO' : 'AVISO DE BREVETE';
            String msg = brevete.mensaje;
            if (brevete.restriccionAviso != null) {
              msg += '\n\nRestricción: ${brevete.restriccionAviso}';
            }
            await _mostrarModal(titulo: titulo, mensaje: msg, esError: brevete.bloquea);
          } else if (brevete.estado == 'VIGENTE' && brevete.restriccionAviso != null) {
            await _mostrarModal(
              titulo: 'RESTRICCIÓN DE BREVETE',
              mensaje: '⚠ ${brevete.restriccionAviso!}',
              esError: false,
            );
          }
        }
      } else {
        setState(() {
          _nombreCtrl.clear();
          _cargoPersonal      = null;
          _areaPersonal       = null;
          _personalEncontrado = false;
          _empresaCtrl.clear();
          _brevete            = null;
        });
      }
    } catch (e) {
      debugPrint('❌ _buscarPersonal: $e');
      // Sin conexión — operador puede escribir manualmente
    } finally {
      if (mounted) {
        setState(() {
          _buscandoPersonal = false;
          _buscandoBrevete  = false;
        });
      }
    }
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
        _dniCtrl.text   = dni;
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

  // ── Guardar: POST /mobile/guardar_registro; si falla → offline ─
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bloqueado || _combustibleBloquea) return;

    final tipoGuardado = _tipo;
    final usuario = context.read<AuthProvider>().usuario;
    setState(() => _guardando = true);

    final body = <String, dynamic>{
      'placa':            _placaCtrl.text.trim(),
      'dni_conductor':    _dniCtrl.text.trim(),
      'nombre_conductor': _nombreCtrl.text.trim(),
      'cargo_conductor':  _cargoPersonal ?? 'NO REGISTRADO',
      'area_conductor':   _areaPersonal ?? 'NO REGISTRADO',
      'dni_autoriza':     (tipoGuardado == 'PermisoSalida' || !_personalEncontrado)
          ? _dniAutorizaCtrl.text.trim() : 'REGISTRADO',
      'nombre_autoriza':  (tipoGuardado == 'PermisoSalida' || !_personalEncontrado)
          ? _nombreAutorizaCtrl.text.trim() : 'SISTEMA',
      'BASE':             usuario?.base ?? '',
      'base_origen':      usuario?.base ?? '',
      'Base_Dirigida':    usuario?.base ?? '',
      'km_actual':        int.tryParse(_kmCtrl.text.trim()) ?? 0,
      'tipo':             tipoGuardado.toLowerCase(),
      'observacion':      _obsCtrl.text.trim(),
      'destino':          _destino,
      'usuario_id':       usuario?.id ?? 0,
      'empresa':          _empresaCtrl.text.trim().isEmpty ? 'DOMINION' : _empresaCtrl.text.trim(),
    };

    try {
      final data = await apiService.post('/mobile/guardar_registro', body);
      if (!mounted) return;
      _limpiarFormulario();
      final mensaje = (data['message'] ?? 'Registro de $tipoGuardado guardado correctamente').toString();
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
      // Sin conexión → cola local
      if (!mounted) return;
      try {
        await OfflineQueueService.encolar(body);
        await _cargarPendientes();
        if (!mounted) return;
        _limpiarFormulario();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.cloud_off_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text('📴 Sin conexión. Guardado localmente — se sincronizará al recuperar red.')),
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
    }
  }

  void _limpiarFormulario() {
    _placaTimer?.cancel();
    _kmModalTimer?.cancel();
    _lastKmAviso = null;
    setState(() {
      _guardando          = false;
      _placaCtrl.clear();
      _kmCtrl.clear();
      _kmAutoLlenado      = false;
      _esPrimeraSalidaDia = false;
      _verificandoReg     = false;
      _tipo               = 'Entrada';
      _bloqueado          = false;
      _soatBloquea        = false;
      _combustibleBloquea = false;
      _avisoVerde         = null;
      _avisoKm            = null;
      _ultimoKmRegistrado = null;
      _kmDiferenciaMax    = 200;
      _dniCtrl.clear();
      _nombreCtrl.clear();
      _cargoPersonal      = null;
      _areaPersonal       = null;
      _personalEncontrado = false;
      _dniAutorizaCtrl.clear();
      _nombreAutorizaCtrl.clear();
      _empresaCtrl.clear();
      _obsCtrl.clear();
      _destino            = 'almacen';
      _errorConexion      = null;
      _brevete            = null;
      _buscandoBrevete    = false;
    });
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  Future<void> _mostrarModal({
    required String titulo,
    required String mensaje,
    bool esError = false,
  }) async {
    if (!mounted) return;
    final color    = esError ? Colors.red.shade700 : Colors.orange.shade700;
    final msgLimpio = mensaje.replaceAll('⛔ ', '').replaceAll('⚠ ', '');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final screenH = MediaQuery.of(ctx).size.height;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: screenH * 0.82,
            child: Column(
              children: [
                Flexible(
                  flex: 40,
                  child: Container(
                    width: double.infinity,
                    color: color,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          esError ? Icons.block_rounded : Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 80,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          titulo,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold,
                            color: Colors.white, letterSpacing: 0.8, height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  flex: 40,
                  child: Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Center(
                      child: Text(
                        msgLimpio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 19, height: 1.65,
                          color: Colors.black87, fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: 20,
                  child: Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: double.infinity,
                        height: 68,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'ENTENDIDO',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final base    = usuario?.base ?? '';
    final garita  = usuario?.garita ?? '';
    final nombre  = usuario?.nombreCompleto ?? 'Usuario';

    final esEntrada       = _tipo == 'Entrada';
    final esPermisoSalida = _tipo == 'PermisoSalida';
    const colorPermiso    = Color(0xFF6A1B9A);
    final colorTipo = esEntrada ? AppColors.entrada
        : esPermisoSalida ? colorPermiso
        : AppColors.salida;

    // SOAT solo bloquea SALIDA; PermisoSalida lo omite
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
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
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
                  Text(garita, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('Base: $base',
                      style: TextStyle(fontSize: 10, color: Colors.amber.shade300, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          if (_pendientes > 0)
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: _sincronizando
                      ? const SizedBox(width: 20, height: 20,
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
                        style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
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

                if (_avisoVerde != null) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: _avisoVerde!,
                    color: Colors.green.shade700,
                    fondo: Colors.green.shade50,
                    icono: Icons.check_circle_outline_rounded,
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
                if (_combustibleBloquea) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: '⛽ Vehículo EBT sin carga de combustible en ventana nocturna (21:00–05:00). No puede ingresar.',
                    color: Colors.deepOrange.shade700,
                    fondo: Colors.deepOrange.shade50,
                    icono: Icons.local_gas_station_rounded,
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

                if (esPermisoSalida ||
                    (!_personalEncontrado &&
                        _dniCtrl.text.isNotEmpty &&
                        !_buscandoPersonal)) ...[
                  const SizedBox(height: 10),
                  _banner(
                    mensaje: esPermisoSalida
                        ? 'PERMISO DE SALIDA — Registrar obligatoriamente quien autoriza la salida del vehículo.'
                        : 'DNI no registrado en personal. Requiere autorización.',
                    color: esPermisoSalida ? const Color(0xFF6A1B9A) : Colors.orange.shade800,
                    fondo: esPermisoSalida ? const Color(0xFFF3E5F5) : Colors.orange.shade50,
                    icono: esPermisoSalida ? Icons.assignment_ind_rounded : Icons.warning_amber_rounded,
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
                  label: esPermisoSalida
                      ? 'MOTIVO / OBSERVACIÓN (requerido)'
                      : 'OBSERVACIÓN (opcional)',
                  obligatorio: esPermisoSalida,
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Botón guardar ──
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_guardando ||
                        (!esPermisoSalida &&
                            (_bloqueado || _combustibleBloquea || soatBloquea ||
                                (_brevete?.bloquea ?? false))))
                    ? null
                    : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : esPermisoSalida
                        ? const Icon(Icons.assignment_turned_in_rounded)
                        : (_bloqueado || _combustibleBloquea || (_brevete?.bloquea ?? false))
                            ? const Icon(Icons.block_rounded)
                            : const Icon(Icons.save_rounded),
                label: Text(
                  _guardando
                      ? 'GUARDANDO...'
                      : esPermisoSalida
                          ? 'GUARDAR PERMISO DE SALIDA'
                          : _bloqueado
                              ? 'INGRESO BLOQUEADO'
                              : _combustibleBloquea
                                  ? 'SIN COMBUSTIBLE — NO PUEDE INGRESAR'
                                  : (_brevete?.bloquea ?? false)
                                      ? 'BREVETE BLOQUEADO'
                                      : 'GUARDAR REGISTRO',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: (!esPermisoSalida && (_bloqueado || _combustibleBloquea))
                      ? Colors.grey
                      : colorTipo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(icono, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(titulo,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold,
                      fontSize: 12, letterSpacing: 0.8)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
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
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
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
          icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
          onPressed: onEscanear,
        ),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
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
            fillColor: _personalEncontrado ? Colors.green.shade50 : Colors.grey.shade50,
            suffixIcon: _buscandoPersonal
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                : _personalEncontrado
                    ? const Icon(Icons.check_circle, color: AppColors.entrada, size: 20)
                    : null,
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
        ),
        if (_cargoPersonal != null && _cargoPersonal!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.badge_outlined, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(_cargoPersonal!,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _dropdownAutoriza() {
    return DropdownButtonFormField<String>(
      decoration: _deco('AUTORIZADO POR').copyWith(
        prefixIcon: const Icon(Icons.verified_user_outlined, color: Colors.deepOrange, size: 20),
      ),
      hint: const Text('Seleccionar autorizador', style: TextStyle(fontSize: 13)),
      items: _autorizadores.entries.map((e) {
        return DropdownMenuItem(
          value: e.key,
          child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (dni) {
        if (dni == null) return;
        setState(() {
          _dniAutorizaCtrl.text   = dni;
          _nombreAutorizaCtrl.text = _autorizadores[dni] ?? '';
        });
      },
      validator: (v) => v == null ? 'Seleccione quien autoriza' : null,
    );
  }

  Widget _campoKm() {
    final bool primeraSalidaConKm = _esPrimeraSalidaDia && _kmAutoLlenado;
    final bool primeraSalidaSinKm = _esPrimeraSalidaDia && !_kmAutoLlenado;

    final Color kmFill = primeraSalidaConKm
        ? Colors.green.shade50
        : primeraSalidaSinKm
            ? Colors.orange.shade50
            : _kmAutoLlenado
                ? Colors.blue.shade50
                : Colors.grey.shade50;

    final String? kmHelper = primeraSalidaConKm
        ? 'KM de la inspección de hoy'
        : primeraSalidaSinKm
            ? 'Primera salida del día — revisar el tablero e ingresar el KM'
            : _kmAutoLlenado
                ? 'Pre-llenado con último KM — actualizar si es diferente'
                : null;

    final Color helperColor = primeraSalidaConKm
        ? Colors.green.shade700
        : primeraSalidaSinKm
            ? Colors.orange.shade700
            : Colors.blue.shade700;

    final Widget? kmSuffix = _verificandoReg
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
        : primeraSalidaConKm
            ? Icon(Icons.fact_check_rounded, color: Colors.green.shade700, size: 20)
            : primeraSalidaSinKm
                ? Icon(Icons.directions_car_rounded, color: Colors.orange.shade700, size: 20)
                : _kmAutoLlenado
                    ? Icon(Icons.auto_fix_high, color: Colors.blue.shade700, size: 20)
                    : null;

    return TextFormField(
      controller: _kmCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: _deco('KM ACTUAL').copyWith(
        filled: true,
        fillColor: kmFill,
        suffixIcon: kmSuffix,
        helperText: kmHelper,
        helperStyle: TextStyle(fontSize: 11, color: helperColor),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
    );
  }

  Widget _campoFijo({required String label, required String valor}) {
    return TextFormField(
      initialValue: valor,
      readOnly: true,
      style: const TextStyle(fontWeight: FontWeight.bold),
      decoration: _deco(label).copyWith(filled: true, fillColor: Colors.grey.shade100),
    );
  }

  Widget _dropdownTipo(Color colorTipo) {
    return InputDecorator(
      decoration: _deco('TIPO').copyWith(
        suffixIcon: _verificandoReg
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
            : null,
      ),
      child: DropdownButton<String>(
        value: _tipo,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          DropdownMenuItem(
            value: 'Entrada',
            child: Row(children: [
              const Icon(Icons.login_rounded, color: AppColors.entrada, size: 18),
              const SizedBox(width: 8),
              const Text('Entrada', style: TextStyle(color: AppColors.entrada, fontWeight: FontWeight.w600)),
            ]),
          ),
          DropdownMenuItem(
            value: 'Salida',
            child: Row(children: [
              const Icon(Icons.logout_rounded, color: AppColors.salida, size: 18),
              const SizedBox(width: 8),
              const Text('Salida', style: TextStyle(color: AppColors.salida, fontWeight: FontWeight.w600)),
            ]),
          ),
          DropdownMenuItem(
            value: 'PermisoSalida',
            child: Row(children: [
              const Icon(Icons.assignment_ind_rounded, color: Color(0xFF6A1B9A), size: 18),
              const SizedBox(width: 8),
              const Text('Permiso Salida', style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          setState(() {
            _tipo = v!;
            if (v == 'PermisoSalida') {
              _bloqueado          = false;
              _soatBloquea        = false;
              _combustibleBloquea = false;
            }
          });
          // Inspecciones deshabilitadas — sin chequeo manual al cambiar tipo
        },
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
            fontSize: 12, fontWeight: FontWeight.w600,
            color: AppColors.textSecondary, letterSpacing: 0.4),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      );
}

class PlacaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
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
