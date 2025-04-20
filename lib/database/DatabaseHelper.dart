// lib/database/DatabaseHelper.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // === 資料庫版本 ===
  static const int _dbVersion = 5;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('my_stocks.db');
    return _database!;
  }

  // ─────────────────────────────────────────────────────────
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

  // ============ 建表 ============
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE watchlist (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT    NOT NULL,
        name TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stocks (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        serverId   INTEGER,
        code       TEXT NOT NULL,
        name       TEXT NOT NULL,
        freq       TEXT,
        signal     TEXT,
        lastUpdate TEXT,
        tdCount    INTEGER,
        tsCount    INTEGER,
        pai        REAL,
        paiSignal  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE signals (
        id         INTEGER PRIMARY KEY,
        stockId    INTEGER,
        date       TEXT,
        signal     TEXT,
        tdCount    INTEGER,
        tsCount    INTEGER,
        pai        REAL,
        paiSignal  TEXT,
        createdAt  TEXT
      )
    ''');

    /// 建立索引提升查詢速度
    await db.execute('CREATE INDEX idx_signals_stockId ON signals(stockId)');
    await db.execute('CREATE INDEX idx_signals_date    ON signals(date)');
  }

  // ============ 升級 ============
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // signals 表（舊版無 createdAt / PAI 欄位，先建最基本）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS signals (
          id        INTEGER PRIMARY KEY,
          stockId   INTEGER,
          date      TEXT,
          signal    TEXT,
          tdCount   INTEGER,
          tsCount   INTEGER,
          createdAt TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      await _safeSql(db, "ALTER TABLE stocks ADD COLUMN serverId INTEGER");
    }

    if (oldVersion < 5) {
      await _safeSql(db, "ALTER TABLE stocks  ADD COLUMN pai REAL");
      await _safeSql(db, "ALTER TABLE stocks  ADD COLUMN paiSignal TEXT");
      await _safeSql(db, "ALTER TABLE signals ADD COLUMN pai REAL");
      await _safeSql(db, "ALTER TABLE signals ADD COLUMN paiSignal TEXT");
    }
  }

  /// 安全執行 ALTER，已存在欄位時忽略錯誤
  Future<void> _safeSql(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  /// ===== Watchlist =====
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
    return db.delete('watchlist', where: 'code = ?', whereArgs: [code]);
  }

  // ─────────────────────────────────────────────────────────
  /// ===== Stocks =====
  Future<int> addStock(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('stocks', row);
  }

  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return db.query('stocks');
  }

  Future<int> deleteStock(int id) async {
    final db = await database;
    return db.delete('stocks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStockByCode(String code) async {
    final db = await database;
    return db.delete('stocks', where: 'code = ?', whereArgs: [code]);
  }

  /// *** 修正版：7 個位置參數，和 UI 端呼叫一致 ***
  Future<int> updateStockSignal(
    int id,
    String? signal,
    String lastUpdate,
    int tdCount,
    int tsCount,
    num? pai,
    String? paiSignal,
  ) async {
    final db = await database;
    return db.update(
      'stocks',
      {
        'signal': signal,
        'lastUpdate': lastUpdate,
        'tdCount': tdCount,
        'tsCount': tsCount,
        if (pai != null) 'pai': pai,
        if (paiSignal != null) 'paiSignal': paiSignal,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

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
            if (item['pai'] != null) 'pai': item['pai'],
            if (item['paiSignal'] != null) 'paiSignal': item['paiSignal'],
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }
    });
  }

  Future<int> updateStockServerId(int localId, int serverId) async {
    final db = await database;
    return db.update(
      'stocks',
      {'serverId': serverId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // ─────────────────────────────────────────────────────────
  /// ===== Signals =====
  Future<int> insertSignal(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('signals', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> batchInsertSignals(List<Map<String, dynamic>> list) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var row in list) {
        await txn.insert('signals', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> deleteSignalsByStockId(int stockId) async {
    final db = await database;
    return db.delete('signals', where: 'stockId = ?', whereArgs: [stockId]);
  }

  Future<List<Map<String, dynamic>>> getSignalsByStockId(int stockId) async {
    final db = await database;
    return db.query('signals', where: 'stockId = ?', whereArgs: [stockId]);
  }

  /// 取得指定股票 code 最近 N 筆 TD / TS
  Future<List<Map<String, dynamic>>> getRecentTDTSByCode(
    String code, {
    int limit = 7,
  }) async {
    final db = await database;
    final rows = await db.query(
      'stocks',
      columns: ['serverId', 'id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return [];

    final serverId = rows.first['serverId'] as int?;
    final idToUse = serverId ?? rows.first['id'];

    return db.rawQuery(
      '''
      SELECT * FROM signals
      WHERE stockId = ?
        AND (signal = '闪电' OR signal = '钻石')
      ORDER BY date DESC
      LIMIT ?
      ''',
      [idToUse, limit],
    );
  }

  Future<List<Map<String, dynamic>>> getSignalsByFilter({
    int? stockId,
    String? signal,
    DateTime? date,
  }) async {
    final db = await database;

    final where = <String>[];
    final args = <dynamic>[];

    if (stockId != null) {
      where.add('stockId = ?');
      args.add(stockId);
    }
    if (signal != null) {
      where.add('signal = ?');
      args.add(signal);
    }
    if (date != null) {
      where.add('date = ?');
      args.add(date.toIso8601String().split('T').first);
    }

    final whereStr = where.isEmpty ? null : where.join(' AND ');
    return db.query('signals', where: whereStr, whereArgs: args);
  }

  // 新增
  /// 回傳最近一次 TD / TS 信號日期
  Future<DateTime?> getLatestTDTSDateByCode(String code) async {
    final db = await database;
    final rows = await db.query(
      'stocks',
      columns: ['serverId', 'id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final stockId = rows.first['serverId'] ?? rows.first['id'];
    final res = await db.rawQuery(
      '''
    SELECT date FROM signals
    WHERE stockId = ?
      AND (signal = '闪电' OR signal = '钻石')
    ORDER BY date DESC
    LIMIT 1
    ''',
      [stockId],
    );
    if (res.isEmpty) return null;
    return DateTime.parse(res.first['date'] as String);
  }

  // ─────────────────────────────────────────────────────────
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
