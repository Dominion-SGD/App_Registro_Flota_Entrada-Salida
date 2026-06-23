class Vehiculo {
  final int id;
  final String placa;
  final String marca;
  final String modelo;
  final String anio;
  final String color;
  final String? propietario;
  final String estado; // activo, inactivo

  Vehiculo({
    required this.id,
    required this.placa,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.color,
    this.propietario,
    this.estado = 'activo',
  });

  factory Vehiculo.fromJson(Map<String, dynamic> json) {
    return Vehiculo(
      id: json['id'] ?? 0,
      placa: json['placa'] ?? '',
      marca: json['marca'] ?? '',
      modelo: json['modelo'] ?? '',
      anio: json['anio']?.toString() ?? '',
      color: json['color'] ?? '',
      propietario: json['propietario'],
      estado: json['estado'] ?? 'activo',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'placa': placa,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'color': color,
        'propietario': propietario,
        'estado': estado,
      };

  String get descripcion => '$marca $modelo ($placa)';
}
