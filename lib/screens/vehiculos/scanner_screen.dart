import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/constants.dart';

class ScannerScreen extends StatefulWidget {
  final String titulo;
  final String instruccion;

  const ScannerScreen({
    super.key,
    required this.titulo,
    required this.instruccion,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _escaneado = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_escaneado) return;
    final barcode = capture.barcodes.firstOrNull;
    final valor = barcode?.rawValue;
    if (valor != null && valor.isNotEmpty) {
      setState(() => _escaneado = true);
      Navigator.of(context).pop(valor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? Colors.yellow : Colors.white,
            ),
            onPressed: () {
              _ctrl.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          _buildOverlay(),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              widget.instruccion,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Center(
      child: Container(
        width: 260,
        height: 160,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primaryLight, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            _corner(0, 0, true, true),
            _corner(0, null, true, false),
            _corner(null, 0, false, true),
            _corner(null, null, false, false),
          ],
        ),
      ),
    );
  }

  Widget _corner(double? top, double? left, bool borderTop, bool borderLeft) {
    return Positioned(
      top: top,
      left: left,
      right: left == null ? 0 : null,
      bottom: top == null ? 0 : null,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: borderTop
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            bottom: !borderTop
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            left: borderLeft
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            right: !borderLeft
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
