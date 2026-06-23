class Registro {
  final int? id;
  final int vehiculoId;
  final String placa;
  final String? vehiculoDescripcion;
  final String tipoMovimiento; // entrada, salida
  final DateTime fechaHora;
  final String? conductor;
  final String? observaciones;
  final int usuarioId;
  final String? usuarioNombre;
  final String? fotoUrl;

  Registro({
    this.id,
    required this.vehiculoId,
    required this.placa,
    this.vehiculoDescripcion,
    required this.tipoMovimiento,
    required this.fechaHora,
    this.conductor,
    this.observaciones,
    required this.usuarioId,
    this.usuarioNombre,
    this.fotoUrl,
  });

  factory Registro.fromJson(Map<String, dynamic> json) {
    return Registro(
      id: json['id'],
      vehiculoId: json['vehiculo_id'] ?? 0,
      placa: json['placa'] ?? '',
      vehiculoDescripcion: json['vehiculo_descripcion'],
      tipoMovimiento: json['tipo_movimiento'] ?? 'entrada',
      fechaHora: json['fecha_hora'] != null
          ? DateTime.parse(json['fecha_hora'])
          : DateTime.now(),
      conductor: json['conductor'],
      observaciones: json['observaciones'],
      usuarioId: json['usuario_id'] ?? 0,
      usuarioNombre: json['usuario_nombre'],
      fotoUrl: json['foto_url'],
    );
  }

  Map<String, dynamic> toJson() => {
        'vehiculo_id': vehiculoId,
        'placa': placa,
        'tipo_movimiento': tipoMovimiento,
        'fecha_hora': fechaHora.toIso8601String(),
        'conductor': conductor,
        'observaciones': observaciones,
        'usuario_id': usuarioId,
        'foto_url': fotoUrl,
      };

  bool get esEntrada => tipoMovimiento == 'entrada';
}
