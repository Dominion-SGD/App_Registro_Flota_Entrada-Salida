import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey  = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass         = true;
  bool _guardarCredenciales = false;

  // Animación de entrada
  late AnimationController _animCtrl;
  late Animation<double>  _fadeAnim;
  late Animation<Offset>  _slideAnim;

  // Slideshow de fondo
  static const _fondos = [
    'assets/images/fondo_login.webp',
    'assets/images/fondo2_login.webp',
    'assets/images/fondo3_login.webp',
  ];
  int   _fondoIndex = 0;
  Timer? _fondoTimer;

  static const _keyUser    = 'saved_email';
  static const _keyPass    = 'saved_pass';
  static const _keyGuardar = 'guardar_credenciales';

  @override
  void initState() {
    super.initState();
    _setupAnimaciones();
    _cargarCredenciales();
    _iniciarSlideshow();
  }

  void _setupAnimaciones() {
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  void _iniciarSlideshow() {
    _fondoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _fondoIndex = (_fondoIndex + 1) % _fondos.length);
    });
  }

  Future<void> _cargarCredenciales() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyGuardar) ?? false) {
      setState(() {
        _guardarCredenciales = true;
        _userCtrl.text = prefs.getString(_keyUser) ?? '';
        _passCtrl.text = prefs.getString(_keyPass) ?? '';
      });
    }
  }

  Future<void> _guardarOLimpiar() async {
    final prefs = await SharedPreferences.getInstance();
    if (_guardarCredenciales) {
      await prefs.setBool(_keyGuardar, true);
      await prefs.setString(_keyUser, _userCtrl.text.trim());
      await prefs.setString(_keyPass, _passCtrl.text);
    } else {
      await prefs.remove(_keyGuardar);
      await prefs.remove(_keyUser);
      await prefs.remove(_keyPass);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await _guardarOLimpiar();
    if (!mounted) return;
    final ok = await context.read<AuthProvider>().login(
      _userCtrl.text.trim(),
      _passCtrl.text,
    );
    if (ok && mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _fondoTimer?.cancel();
    _animCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth       = context.watch<AuthProvider>();
    final mq         = MediaQuery.of(context);
    final screenH    = mq.size.height;
    final topPad     = mq.padding.top;
    final botPad     = mq.padding.bottom + mq.viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Fondo animado ─────────────────────────────────────
          _buildFondo(),

          // ── Capa oscura sobre el fondo ─────────────────────────
          Container(color: Colors.black.withValues(alpha: 0.45)),

          // ── Contenido scrollable (siempre visible aunque se aumente el zoom)
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenH - topPad - botPad,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: topPad + 24,
                  bottom: botPad + 24,
                  left: 24,
                  right: 24,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLogo(screenH),
                        SizedBox(height: screenH * 0.04),
                        _buildCard(auth),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fondo: slideshow entre 3 imágenes con crossfade ──────────
  Widget _buildFondo() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      child: Image.asset(
        _fondos[_fondoIndex],
        key: ValueKey(_fondoIndex),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Container(color: AppColors.primaryDark),
      ),
    );
  }

  // ── Logo SVG + nombre de app ───────────────────────────────────
  Widget _buildLogo(double screenH) {
    final logoSize = (screenH * 0.14).clamp(80.0, 140.0);
    return Column(
      children: [
        SvgPicture.asset(
          'assets/images/logo.svg',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Icon(
            Icons.directions_car_rounded,
            size: logoSize * 0.7,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'DOM · FLOTA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Control de vehículos',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Tarjeta de formulario ─────────────────────────────────────
  Widget _buildCard(AuthProvider auth) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Iniciar sesión',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Ingresa tus credenciales',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Campo usuario
            TextFormField(
              controller: _userCtrl,
              textInputAction: TextInputAction.next,
              decoration: _inputDeco(label: 'Usuario', icon: Icons.person_outline),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 14),

            // Campo contraseña
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: _inputDeco(
                label: 'Contraseña',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Campo requerido';
                if (v.length < 4) return 'Mínimo 4 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Guardar contraseña
            InkWell(
              onTap: () => setState(() => _guardarCredenciales = !_guardarCredenciales),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _guardarCredenciales ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                          color: _guardarCredenciales ? AppColors.primary : Colors.grey.shade400,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: _guardarCredenciales
                          ? const Icon(Icons.check, color: Colors.white, size: 13)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Guardar contraseña',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

            // Error de login
            if (auth.error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        auth.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Botón INGRESAR — altura fija mínima para que siempre sea tappable
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: auth.isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: auth.isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'INGRESAR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // Indicadores del slideshow
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_fondos.length, (i) {
                final activo = i == _fondoIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: activo ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: activo ? AppColors.primary : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
