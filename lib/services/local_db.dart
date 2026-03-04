import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDb {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'compleat.db');
    return openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE offline_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          endpoint TEXT,
          payload TEXT,
          created_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE cached_masters (
          type TEXT PRIMARY KEY,
          data TEXT,
          updated_at TEXT
        )
      ''');
    });
  }

  static Future<void> queueTransaction(String endpoint, String payload) async {
    final database = await db;
    await database.insert('offline_queue', {
      'endpoint': endpoint,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map>> getPendingQueue() async {
    final database = await db;
    return database.query('offline_queue', orderBy: 'created_at ASC');
  }

  static Future<void> clearQueueItem(int id) async {
    final database = await db;
    await database.delete('offline_queue', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> cacheMasters(String type, String data) async {
    final database = await db;
    await database.insert('cached_masters',
      {'type': type, 'data': data, 'updated_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getCachedMasters(String type) async {
    final database = await db;
    final result = await database.query('cached_masters', where: 'type = ?', whereArgs: [type]);
    if (result.isEmpty) return null;
    return result.first['data'] as String?;
  }
}
