import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _database;
  static final DatabaseHelper instance = DatabaseHelper._init();

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stocks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';

    await db.execute('''
CREATE TABLE stocks (
  id $idType,
  code $textType,
  name $textType
)
''');
  }

  Future<int> addStock(Map<String, dynamic> stock) async {
    final db = await database;
    return await db.insert('stocks', stock);
  }

  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return await db.query('stocks');
  }

  Future<int> deleteStock(int id) async {
    final db = await database;
    return await db.delete(
      'stocks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
