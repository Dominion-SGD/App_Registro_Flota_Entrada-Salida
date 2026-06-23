import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import 'scanner_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();

  // Vehículo
  final _placaCtrl = TextEditingController();
  String _tipo = 'Entrada';
  final _kmCtrl = TextEditingController();

  // Conductor
  final _dniCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();

  // Destino
  String _destino = 'Almacén';
  final _empresaCtrl = TextEditingController(text: 'DOMINION');
  final _obsCtrl = TextEditingController();

  bool _guardando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments as String?;
    if (arg != null) {
      _tipo = arg == 'salida' ? 'Salida' : 'Entrada';
    }
  }

  static const _destinos = [
    'Almacén', 'Oficina', 'Taller', 'Comedor',
    'Planta', 'Garita', 'Laboratorio', 'Otro',
  ];

  @override
  void dispose() {
    _placaCtrl.dispose();
    _kmCtrl.dispose();
    _dniCtrl.dispose();
    _nombreCtrl.dispose();
    _empresaCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _escanearQR() async {
    final resultado = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          titulo: 'Escanear Placa / QR',
          instruccion: 'Apunta al código QR o código de barras de la placa',
        ),
      ),
    );
    if (resultado != null) {
      setState(() => _placaCtrl.text = resultado.toUpperCase());
    }
  }

  Future<void> _escanearDNI() async {
    final resultado = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(
          titulo: 'Escanear DNI',
          instruccion: 'Apunta al código de barras del DNI',
        ),
      ),
    );
    if (resultado != null && mounted) {
      final partes = resultado.split('@');
      setState(() {
        if (partes.length >= 4) {
          _dniCtrl.text = partes[4].trim();
          final apellido = partes[1].trim();
          final nombre = partes[2].trim();
          _nombreCtrl.text = '$nombre $apellido';
        } else {
          _dniCtrl.text = resultado;
        }
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 10),
          Text('Registro guardado correctamente'),
        ]),
        backgroundColor: AppColors.entrada,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthProvider>().usuario;
    final base = usuario?.base ?? '';
    final garita = usuario?.garita ?? '';
    final esEntrada = _tipo == 'Entrada';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: esEntrada ? AppColors.entrada : AppColors.salida,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GESTIÓN DOMINION',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Vehículos',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(garita,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Base: $base',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade300,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _seccion(
              titulo: 'DATOS DEL VEHÍCULO',
              color: AppColors.primary,
              icono: Icons.directions_car_rounded,
              hijos: [
                _campoConEscaner(
                  ctrl: _placaCtrl,
                  label: 'PLACA',
                  obligatorio: true,
                  onEscanear: _escanearQR,
                  inputFormatters: [UpperCaseFormatter()],
                ),
                const SizedBox(height: 14),
                _dropdownTipo(esEntrada),
                const SizedBox(height: 14),
                _campo(
                  ctrl: _kmCtrl,
                  label: 'KM ACTUAL',
                  obligatorio: true,
                  teclado: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _seccion(
              titulo: 'DATOS DEL CONDUCTOR',
              color: const Color(0xFF00695C),
              icono: Icons.person_rounded,
              hijos: [
                _campoConEscaner(
                  ctrl: _dniCtrl,
                  label: 'DNI CONDUCTOR',
                  obligatorio: true,
                  onEscanear: _escanearDNI,
                  teclado: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 14),
                _campo(ctrl: _nombreCtrl, label: 'NOMBRE Y APELLIDO', obligatorio: true),
                const SizedBox(height: 14),
                _campoReadOnly(label: 'BASE', valor: base),
              ],
            ),
            const SizedBox(height: 14),
            _seccion(
              titulo: 'DESTINO Y EMPRESA',
              color: const Color(0xFF6A1B9A),
              icono: Icons.location_on_rounded,
              hijos: [
                _dropdownDestino(),
                const SizedBox(height: 14),
                _campo(ctrl: _empresaCtrl, label: 'EMPRESA', obligatorio: true),
                const SizedBox(height: 14),
                _campo(
                  ctrl: _obsCtrl,
                  label: 'OBSERVACIÓN (opcional)',
                  obligatorio: false,
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _botonGuardar(esEntrada),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _seccion({
    required String titulo,
    required Color color,
    required IconData icono,
    required List<Widget> hijos,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icono, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
          ),
        ],
      ),
    );
  }

  Widget _campoConEscaner({
    required TextEditingController ctrl,
    required String label,
    required bool obligatorio,
    required VoidCallback onEscanear,
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: teclado,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      decoration: _deco(label).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
          onPressed: onEscanear,
          tooltip: 'Escanear',
        ),
      ),
      validator: obligatorio
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null
          : null,
    );
  }

  Widget _campo({
    required TextEditingController ctrl,
    required String label,
    required bool obligatorio,
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: teclado,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: _deco(label),
      validator: obligatorio
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null
          : null,
    );
  }

  Widget _campoReadOnly({required String label, required String valor}) {
    return TextFormField(
      initialValue: valor,
      readOnly: true,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      decoration: _deco(label).copyWith(
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
    );
  }

  Widget _dropdownTipo(bool esEntrada) {
    return DropdownButtonFormField<String>(
      key: ValueKey(_tipo),
      initialValue: _tipo,
      decoration: _deco('TIPO'),
      items: ['Entrada', 'Salida'].map((t) {
        final color = t == 'Entrada' ? AppColors.entrada : AppColors.salida;
        return DropdownMenuItem(
          value: t,
          child: Row(children: [
            Icon(t == 'Entrada' ? Icons.login_rounded : Icons.logout_rounded,
                color: color, size: 18),
            const SizedBox(width: 8),
            Text(t, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ]),
        );
      }).toList(),
      onChanged: (v) => setState(() => _tipo = v!),
    );
  }

  Widget _dropdownDestino() {
    return DropdownButtonFormField<String>(
      key: ValueKey(_destino),
      initialValue: _destino,
      decoration: _deco('DESTINO'),
      items: _destinos
          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
          .toList(),
      onChanged: (v) => setState(() => _destino = v!),
      validator: (v) => v == null ? 'Seleccione destino' : null,
    );
  }

  Widget _botonGuardar(bool esEntrada) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _guardando ? null : _guardar,
        icon: _guardando
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_rounded),
        label: Text(
          _guardando ? 'GUARDANDO...' : 'GUARDAR REGISTRO',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: esEntrada ? AppColors.entrada : AppColors.salida,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 3,
        ),
      ),
    );
  }

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) =>
      nv.copyWith(text: nv.text.toUpperCase());
}
