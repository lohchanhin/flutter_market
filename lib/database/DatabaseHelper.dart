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

    // 将数据库版本号增加到3
    return await openDatabase(path,
        version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  // 创建数据库时的逻辑
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
  }

  // 升级数据库时的逻辑
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE stocks ADD COLUMN signal TEXT');
      await db.execute('ALTER TABLE stocks ADD COLUMN lastUpdate TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE stocks ADD COLUMN tdCount INTEGER');
      await db.execute('ALTER TABLE stocks ADD COLUMN tsCount INTEGER');
    }
  }

  // 添加股票
  Future<int> addStock(Map<String, dynamic> stock) async {
    final db = await database;
    return await db.insert('stocks', stock);
  }

  // 获取所有股票
  Future<List<Map<String, dynamic>>> getStocks() async {
    final db = await database;
    return await db.query('stocks');
  }

  // 更新股票的信号和更新时间
  Future<int> updateStockSignal(int id, String? signal, String lastUpdate,
      int tdCount, int tsCount) async {
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

  // 删除股票
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
