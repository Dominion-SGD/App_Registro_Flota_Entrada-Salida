class Usuario {
  final int id;
  final String username;
  final String nombreCompleto;
  final String rol;

  Usuario({
    required this.id,
    required this.username,
    required this.nombreCompleto,
    this.rol = 'operador',
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? json['username'] ?? '',
      rol: json['rol'] ?? 'operador',
    );
  }

  factory Usuario.fromRow(Map<String, String?> row) {
    return Usuario(
      id: int.tryParse(row['id'] ?? '0') ?? 0,
      username: row['username'] ?? '',
      nombreCompleto: row['nombre_completo'] ?? row['username'] ?? '',
      rol: row['rol'] ?? 'operador',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nombre_completo': nombreCompleto,
        'rol': rol,
      };

  // Extrae la base según el nombre del usuario/garita
  String get base {
    final n = nombreCompleto.toLowerCase();
    if (n.contains('argentina')) return 'ARGENTINA';
    if (n.contains('minka')) return 'MINKA';
    if (n.contains('callao')) return 'CALLAO';
    if (n.contains('lima')) return 'LIMA';
    // Fallback: última palabra del nombre
    final parts = nombreCompleto.trim().split(' ');
    return parts.last.toUpperCase();
  }

  String get garita => nombreCompleto;
}
