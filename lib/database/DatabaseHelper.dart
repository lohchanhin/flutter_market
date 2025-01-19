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
      version: 4, // <-- 版本升級到 4
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
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
    // 第一次建表就加 freq 欄位
    await db.execute('ALTER TABLE stocks ADD COLUMN freq TEXT');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE stocks ADD COLUMN signal TEXT');
      await db.execute('ALTER TABLE stocks ADD COLUMN lastUpdate TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE stocks ADD COLUMN tdCount INTEGER');
      await db.execute('ALTER TABLE stocks ADD COLUMN tsCount INTEGER');
    }
    if (oldVersion < 4) {
      // 加 freq 欄位
      await db.execute('ALTER TABLE stocks ADD COLUMN freq TEXT');
    }
  }

  // 新增股票（單筆）
  Future<int> addStock(Map<String, dynamic> stock) async {
    final db = await database;
    return await db.insert('stocks', stock);
  }

  // 取得所有股票
  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return await db.query('stocks');
  }

  // 更新股票的 signal/lastUpdate/tdCount/tsCount
  Future<int> updateStockSignal(
    int id,
    String? signal,
    String lastUpdate,
    int tdCount,
    int tsCount,
  ) async {
    final db = await database;
    return await db.update(
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

  // 刪除 (用 id)
  Future<int> deleteStock(int id) async {
    final db = await database;
    return await db.delete(
      'stocks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 刪除 (用 code)
  Future<int> deleteStockByCode(String code) async {
    final db = await database;
    return await db.delete(
      'stocks',
      where: 'code = ?',
      whereArgs: [code],
    );
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
