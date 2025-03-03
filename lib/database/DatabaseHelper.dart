import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // === 由原先 v2 or v3, 升級至 v4 ===
  static const int _dbVersion = 4;

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

  // ======================
  // 初次安裝 (onCreate)
  // ======================
  Future _onCreate(Database db, int version) async {
    // 1) watchlist (使用者自訂清單，只需要 code, name)
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL
      )
    ''');

    // 2) stocks (與後端同步: freq, signal, tdCount, tsCount, lastUpdate, serverId)
    await db.execute('''
      CREATE TABLE stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serverId INTEGER,         -- 對應後端 stockId
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        freq TEXT,
        signal TEXT,
        lastUpdate TEXT,
        tdCount INTEGER,
        tsCount INTEGER
      )
    ''');

    // 3) signals (儲存多筆 signal 記錄)
    await db.execute('''
      CREATE TABLE signals (
        id INTEGER PRIMARY KEY,   -- 直接使用後端的 signal id
        stockId INTEGER,          -- 後端的 stockId (對應 stocks.serverId)
        date TEXT,
        signal TEXT,
        tdCount INTEGER,
        tsCount INTEGER,
        createdAt TEXT
      )
    ''');
  }

  // ======================
  // 升級 (onUpgrade)
  // ======================
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 若舊版 < 3，則需建立 signals 表
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE signals (
          id INTEGER PRIMARY KEY,
          stockId INTEGER,
          date TEXT,
          signal TEXT,
          tdCount INTEGER,
          tsCount INTEGER,
          createdAt TEXT
        )
      ''');
    }

    // 若舊版 < 4，則需在 stocks 表加上 serverId 欄位
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE stocks ADD COLUMN serverId INTEGER');
      } catch (e) {
        print('ignore error: $e');
      }
    }
  }

  // ================================
  // watchlist 表: 供 SearchPage 用
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
  // stocks 表: 供 StockListPage 用
  // ================================
  // 新增 (含 freq, signal, tdCount, tsCount, lastUpdate, serverId)
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
  Future<int> updateStockSignal(
    int id, // 本地 stocks.id
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
      where: 'id=?',
      whereArgs: [id],
    );
  }

  // 批次更新 (for "updateAllStocks")
  // 需注意: 這裡傳入 item['id'] 是本地 stocks.id
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

  // 新增/更新 stocks 的 serverId
  Future<int> updateStockServerId(int localId, int serverId) async {
    final db = await database;
    return db.update(
      'stocks',
      {'serverId': serverId},
      where: 'id=?',
      whereArgs: [localId],
    );
  }

  // ================================
  // signals 表: 儲存多筆 signal 記錄
  // ================================
  // 單筆插入 (若想 upsert，可 conflictAlgorithm: replace)
  Future<int> insertSignal(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(
      'signals',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 批次插入 / 更新 signals
  Future<void> batchInsertSignals(List<Map<String, dynamic>> signalList) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var signalData in signalList) {
        await txn.insert(
          'signals',
          signalData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // 根據 stockId (後端 id) 刪除該股票所有 signals
  Future<int> deleteSignalsByStockId(int stockId) async {
    final db = await database;
    return db.delete('signals', where: 'stockId = ?', whereArgs: [stockId]);
  }

  // 讀取某個 stockId (後端 id) 的所有 signals
  Future<List<Map<String, dynamic>>> getSignalsByStockId(int stockId) async {
    final db = await database;
    return db.query('signals', where: 'stockId = ?', whereArgs: [stockId]);
  }

  // 範例: 依某些條件 (如 date, signal) 讀取 signals
  Future<List<Map<String, dynamic>>> getSignalsByFilter({
    int? stockId,
    String? signal,
    DateTime? date,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (stockId != null) {
      whereClauses.add('stockId = ?');
      whereArgs.add(stockId);
    }
    if (signal != null) {
      whereClauses.add('signal = ?');
      whereArgs.add(signal);
    }
    if (date != null) {
      // 比較日期 (不含時間) 的最簡易做法：直接比對 'yyyy-MM-dd'
      final dateStr = date.toIso8601String().split('T').first;
      whereClauses.add('date = ?');
      whereArgs.add(dateStr);
    }

    final whereString =
        whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    return db.query('signals', where: whereString, whereArgs: whereArgs);
  }

  // 關閉資料庫
  Future close() async {
    final db = await database;
    db.close();
  }
}
