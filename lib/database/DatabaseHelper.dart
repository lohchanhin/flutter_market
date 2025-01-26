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

    return await openDatabase(
      path,
      version: 5, // 版本
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 建立 stocks 表
    await db.execute('''
      CREATE TABLE stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        signal TEXT,
        lastUpdate TEXT,
        tdCount INTEGER,
        tsCount INTEGER
      )
    ''');
    // 建 freq 欄位
    await db.execute('ALTER TABLE stocks ADD COLUMN freq TEXT');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // ... 略（與你提供的一樣）
  }

  // 新增
  Future<int> addStock(Map<String, dynamic> stock) async {
    final db = await database;
    return db.insert('stocks', stock);
  }

  // 取得所有
  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return db.query('stocks');
  }

  // 更新 signal 等
  Future<int> updateStockSignal(
    int id,
    String? signal,
    String lastUpdate,
    int tdCount,
    int tsCount,
  ) async {
    final db = await database;
    return db.update(
      'stocks',
      {
        'signal': signal,
        'lastUpdate': lastUpdate,
        'tdCount': tdCount,
        'tsCount': tsCount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 刪除(用 id)
  Future<int> deleteStock(int id) async {
    final db = await database;
    return db.delete('stocks', where: 'id = ?', whereArgs: [id]);
  }

  // 刪除(用 code) => 刪除該 code 下所有 freq
  Future<int> deleteStockByCode(String code) async {
    final db = await database;
    return db.delete('stocks', where: 'code = ?', whereArgs: [code]);
  }

  // 批次更新
  Future<void> batchUpdateStocks(List<Map<String, dynamic>> updates) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (var item in updates) {
        await txn.update(
          'stocks',
          {
            'signal': item['signal'],
            'lastUpdate': item['lastUpdate'],
            'tdCount': item['tdCount'],
            'tsCount': item['tsCount'],
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }
    });
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
