import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql_client/mysql_client.dart';

class DbService {
  MySQLConnection? _conn;

  Future<MySQLConnection> get connection async {
    if (_conn != null && !_conn!.connected) _conn = null;
    if (_conn == null) {
      _conn = await MySQLConnection.createConnection(
        host: dotenv.env['DB_HOST'] ?? '161.132.128.4',
        port: int.parse(dotenv.env['DB_PORT'] ?? '3306'),
        userName: dotenv.env['DB_USER'] ?? 'root',
        password: dotenv.env['DB_PASS'] ?? '',
        databaseName: dotenv.env['DB_NAME'] ?? 'dominion_gpd_energia',
        secure: true,
      );
      await _conn!.connect();
    }
    return _conn!;
  }

  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }
}

final dbService = DbService();
