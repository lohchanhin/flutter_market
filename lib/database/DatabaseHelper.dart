import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const int _dbVersion = 2;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('my_stocks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    // 1) watchlist (使用者自訂清單，只需要 code, name)
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL
      )
    ''');

    // 2) stocks (與後端同步: freq, signal, tdCount, tsCount, lastUpdate)
    await db.execute('''
      CREATE TABLE stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        freq TEXT,
        signal TEXT,
        lastUpdate TEXT,
        tdCount INTEGER,
        tsCount INTEGER
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 若日後要擴充欄位或表，在此處加 if (oldVersion < X) ...
  }

  // ================================
  // ★ watchlist 表: 供 SearchPage 用
  // ================================
  Future<int> addToWatchlist(String code, String name) async {
    final db = await database;
    return db.insert('watchlist', {'code': code, 'name': name});
  }

  Future<List<Map<String, dynamic>>> getWatchlist() async {
    final db = await database;
    return db.query('watchlist');
  }

  Future<int> deleteWatchlistByCode(String code) async {
    final db = await database;
    return db.delete('watchlist', where: 'code=?', whereArgs: [code]);
  }

  // ================================
  // ★ stocks 表: 供 StockListPage 用
  // ================================
  // 新增 (含 freq, signal, tdCount, tsCount, lastUpdate)
  Future<int> addStock(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('stocks', row);
  }

  // 取得全部 stocks
  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return db.query('stocks');
  }

  // 用 id 刪除
  Future<int> deleteStock(int id) async {
    final db = await database;
    return db.delete('stocks', where: 'id=?', whereArgs: [id]);
  }

  // 用 code 刪除 (包含該 code 下的所有 freq)
  Future<int> deleteStockByCode(String code) async {
    final db = await database;
    return db.delete('stocks', where: 'code=?', whereArgs: [code]);
  }

  // 更新 signal, tdCount, tsCount, lastUpdate
  Future<int> updateStockSignal(int id, String? signal, String lastUpdate,
      int tdCount, int tsCount) async {
    final db = await database;
    return db.update(
      'stocks',
      {
        'signal': signal,
        'lastUpdate': lastUpdate,
        'tdCount': tdCount,
        'tsCount': tsCount,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  // 批次更新 (for "updateAllStocks")
  Future<void> batchUpdateStocks(List<Map<String, dynamic>> updates) async {
    final db = await database;
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
          where: 'id=?',
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
