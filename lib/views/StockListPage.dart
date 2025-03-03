import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/DatabaseHelper.dart';
import '../services/api_service.dart';
import '../components/StockDetail.dart';

class StockListPage extends StatefulWidget {
  @override
  _StockListPageState createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  final dbHelper = DatabaseHelper.instance;
  final api = ApiService();

  /// 從本地 stocks 撈到的「已在 watchlist」的資料
  List<Map<String, dynamic>> _stocks = [];

  /// 篩選後要顯示在 ListView 的結果
  List<Map<String, dynamic>> _filteredStocks = [];

  /// 保存「serverId -> 該股票所有 signals」的對應
  Map<int, List<Map<String, dynamic>>> _allSignals = {};

  /// 若已選日期，記錄「本地 stocks.id -> 該日 matched signals」，
  /// 方便在 UI 中顯示多個圖示
  Map<int, List<Map<String, dynamic>>> _signalsForDate = {};

  bool _isUpdating = false;
  int _updateProgress = 0;
  int _totalStocks = 0;

  String _filterFreq = 'All'; // 篩選週期：All / Day / Week
  String _filterSignal = 'All'; // 篩選訊號：All / TD(闪电) / TS(钻石)
  DateTime? _selectedDate; // 若不為 null，則只顯示該日期有信號的股票

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  /// 一次把:
  ///   1) watchlist (取得 codes)
  ///   2) stocks (篩出 watchlist 中的股票)
  ///   3) signals (撈出這些股票對應的所有訊號)
  /// 都載入後，最後呼叫 _applyFilter()
  Future<void> _loadAllData() async {
    try {
      // 1) 取得 watchlist 中的股票 code
      final watchData = await dbHelper.getWatchlist();
      final watchCodes =
          watchData.map<String>((m) => m['code'] as String).toSet();

      // 2) 讀取所有 stocks，僅保留 code 在 watchlist 裏的
      final allStocks = await dbHelper.getStocks();
      final filtered = allStocks.where((s) => watchCodes.contains(s['code']));

      // 3) 建立一個 {serverId: [signal, ...]} 的 map
      final Map<int, List<Map<String, dynamic>>> signalsMap = {};
      for (var stock in filtered) {
        final sid = stock['serverId'] as int? ?? 0; // 後端 ID
        if (sid > 0) {
          // 撈取該 serverId 的所有 signals
          final sigList = await dbHelper.getSignalsByStockId(sid);
          signalsMap[sid] = sigList;
        } else {
          // 若沒設定 serverId，就給空陣列
          signalsMap[0] = [];
        }
      }

      setState(() {
        _stocks = filtered.toList();
        _allSignals = signalsMap;
      });
      _applyFilter();
    } catch (e) {
      print('Error in _loadAllData: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入資料失敗: $e')),
        );
      }
    }
  }

  /// 核心邏輯：
  /// - 若 _selectedDate == null => 僅依 stocks.freq + stocks.signal 做篩選 (顯示所有在 watchlist 的股票)
  /// - 若 _selectedDate != null => 從 signals 裏面找「符合該日期」的紀錄，
  ///   並且 (若 user 選 TD/TS) 要符合同樣訊號；最後再過濾 freq。
  /// - 若同一檔股票當日有多筆不同的 signal，都一併記錄，UI 顯示多個 icon
  void _applyFilter() {
    // 複製一份 stocks
    List<Map<String, dynamic>> temp = List.from(_stocks);

    // 清空當日 matched signals
    _signalsForDate.clear();

    // 未選日期 => 依 stocks 表中 freq, signal 篩選
    if (_selectedDate == null) {
      // 篩週期
      if (_filterFreq != 'All') {
        temp = temp.where((s) => s['freq'] == _filterFreq).toList();
      }
      // 篩訊號: TD=閃電, TS=鑽石
      if (_filterSignal == 'TD') {
        temp = temp.where((s) => s['signal'] == '闪电').toList();
      } else if (_filterSignal == 'TS') {
        temp = temp.where((s) => s['signal'] == '钻石').toList();
      }

      setState(() {
        _filteredStocks = temp;
      });
      return;
    }

    // 若已選日期 => 從 signals 查當天所有紀錄
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final result = <Map<String, dynamic>>[];

    for (var stock in temp) {
      final freq = stock['freq'] as String?;
      // 先檢查週期
      if (_filterFreq != 'All' && freq != _filterFreq) {
        continue;
      }

      final sid = stock['serverId'] as int? ?? 0;
      final signalList = _allSignals[sid] ?? [];

      // 依使用者選擇的訊號類型，過濾 signals
      List<Map<String, dynamic>> matched = signalList;
      if (_filterSignal == 'TD') {
        matched = matched.where((m) => m['signal'] == '闪电').toList();
      } else if (_filterSignal == 'TS') {
        matched = matched.where((m) => m['signal'] == '钻石').toList();
      }

      // 再依日期
      matched = matched.where((m) {
        if (m['date'] == null) return false;
        final signalDateStr = (m['date'] as String).split('T').first;
        return signalDateStr == dateStr;
      }).toList();

      if (matched.isNotEmpty) {
        result.add(stock);
        final localId = stock['id'] as int;
        _signalsForDate[localId] = matched; // 記錄當日的多筆 matched signals
      }
    }

    setState(() {
      _filteredStocks = result;
    });
  }

  /// 刪除本地 DB 中的股票記錄
  Future<void> _removeStock(int localId) async {
    try {
      await dbHelper.deleteStock(localId);
      await _loadAllData();
    } catch (e) {
      print('Error removing stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗: $e')),
        );
      }
    }
  }

  /// 模擬更新所有股票資料（例如呼叫後端 API、更新本地 DB）
  /// 此示範包含將後端返回的 signals 一併寫入本地
  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _filteredStocks.length;
    });

    try {
      // 1) 從後端取得最新資料 (確保這支 API 有帶入 signals 陣列)
      final remoteList = await api.getAllStocks();

      // 2) 取得本地 stocks，建立 { code|freq -> localStock } map
      final localAll = await dbHelper.getStocks();
      final Map<String, Map<String, dynamic>> codeFreqToLocal = {};
      for (var loc in localAll) {
        final key = '${loc['code']}|${loc['freq']}';
        codeFreqToLocal[key] = loc;
      }

      // 3) 同步後端資料 -> stocks & signals
      for (var remote in remoteList) {
        final serverId = remote['id'] as int; // 後端的 stockId
        final code = remote['code'] as String;
        final freq = remote['freq'] as String?;
        final key = '$code|$freq';

        // === 3-1. 若本地有該股票, 可更新 stocks (若需要) ===
        if (codeFreqToLocal.containsKey(key)) {
          // 例如更新 stocks.serverId, signal, lastUpdate, tdCount, tsCount 等
          final localStock = codeFreqToLocal[key]!;
          final localId = localStock['id'] as int;
          await dbHelper.updateStockServerId(localId, serverId);
          await dbHelper.updateStockSignal(
            localId,
            remote['signal'],
            remote['lastUpdate'] ?? DateTime.now().toString(),
            remote['tdCount'] ?? 0,
            remote['tsCount'] ?? 0,
          );
        }

        // === 3-2. 同步 signals ===
        final signals = remote['signals'] as List<dynamic>? ?? [];
        // 先刪除
        await dbHelper.deleteSignalsByStockId(serverId);
        // 再批次插入
        if (signals.isNotEmpty) {
          final toInsert = signals
              .map((sig) => {
                    'id': sig['id'],
                    'stockId': sig['stockId'], // 後端 stockId
                    'date': sig['date'],
                    'signal': sig['signal'],
                    'tdCount': sig['tdCount'] ?? 0,
                    'tsCount': sig['tsCount'] ?? 0,
                    'createdAt': sig['createdAt'] ?? '',
                  })
              .toList();
          await dbHelper.batchInsertSignals(toInsert);
        }
      }

      // 4) 同步完成，重新載入
      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有股票已更新，含 signals')),
        );
      }
    } catch (e) {
      print('Error updateAllStocks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗: $e')),
        );
      }
    }

    setState(() {
      _isUpdating = false;
    });
  }

  /// 用於顯示 stocks 裏的最後更新日期 (僅作參考)
  String _formatLastUpdate(String? lastUpdateStr, String freq) {
    if (lastUpdateStr == null) return '未更新';
    DateTime dt;
    try {
      dt = DateTime.parse(lastUpdateStr);
    } catch (e) {
      return '格式錯誤';
    }
    if (freq == 'Week') {
      DateTime monday = dt.subtract(Duration(days: dt.weekday - 1));
      return '最後更新：${DateFormat('yyyy-MM-dd').format(monday)}';
    } else {
      return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
    }
  }

  /// 根據「單一 signal」(如 "闪电" or "钻石") 顯示對應 icon
  Widget _buildSignalIcon(String? signal) {
    if (signal == '闪电') {
      return Icon(Icons.flash_on, color: Colors.green);
    } else if (signal == '钻石') {
      return Icon(Icons.diamond, color: Colors.red);
    }
    return Icon(Icons.do_not_disturb, color: Colors.grey);
  }

  /// 日期選擇器
  Future<void> _pickDate() async {
    DateTime initialDate = _selectedDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '選擇日期(僅顯示該日有信號的股票)',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _applyFilter();
    }
  }

  /// 清除所選日期 => 顯示所有股票(含無信號)
  void _clearDate() {
    setState(() {
      _selectedDate = null;
    });
    _applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: _isUpdating,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Stocks (只顯示 watchlist)'),
              actions: [
                // 一鍵更新
                IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
                // 週期篩選
                DropdownButton<String>(
                  value: _filterFreq,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部週期')),
                    DropdownMenuItem(value: 'Day', child: Text('日線')),
                    DropdownMenuItem(value: 'Week', child: Text('週線')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterFreq = val;
                      });
                      _applyFilter();
                    }
                  },
                  underline: SizedBox(),
                ),
                // 訊號篩選
                DropdownButton<String>(
                  value: _filterSignal,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部信號')),
                    DropdownMenuItem(value: 'TD', child: Text('TD')),
                    DropdownMenuItem(value: 'TS', child: Text('TS')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterSignal = val;
                      });
                      _applyFilter();
                    }
                  },
                  underline: SizedBox(),
                ),
                SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                // 上方：日曆選擇 & 符合條件的數量
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.calendar_today),
                        label: Text(
                          _selectedDate == null
                              ? '選擇日期'
                              : DateFormat('yyyy-MM-dd').format(_selectedDate!),
                        ),
                        onPressed: _pickDate,
                      ),
                      if (_selectedDate != null)
                        IconButton(
                          icon: Icon(Icons.clear),
                          onPressed: _clearDate,
                        ),
                      Spacer(),
                      Text('符合條件: ${_filteredStocks.length}'),
                    ],
                  ),
                ),

                // 下方列表
                Expanded(
                  child: _filteredStocks.isEmpty
                      ? Center(child: Text('沒有符合篩選的股票'))
                      : ListView.builder(
                          itemCount: _filteredStocks.length,
                          itemBuilder: (ctx, i) {
                            final s = _filteredStocks[i];
                            final localId = s['id'] as int;
                            final freq = s['freq'] ?? 'Day';
                            final formattedLastUpdate =
                                _formatLastUpdate(s['lastUpdate'], freq);

                            // 若沒選日期 => 顯示 stocks.signal
                            // 若有選日期 => 顯示當日 matched signals (可能多筆)
                            Widget leadingWidget;
                            if (_selectedDate == null) {
                              // 單一 icon (stocks.signal)
                              leadingWidget = _buildSignalIcon(s['signal']);
                            } else {
                              // 多筆 icon
                              final matchedSignals =
                                  _signalsForDate[localId] ?? [];
                              if (matchedSignals.isEmpty) {
                                // 理論上不會發生，因為 matched.isNotEmpty 才留在清單
                                leadingWidget = Icon(Icons.do_not_disturb,
                                    color: Colors.grey);
                              } else {
                                final iconList = matchedSignals.map((ms) {
                                  final sig = ms['signal'] as String?;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2.0),
                                    child: _buildSignalIcon(sig),
                                  );
                                }).toList();
                                leadingWidget = Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: iconList,
                                );
                              }
                            }

                            return ListTile(
                              leading: leadingWidget,
                              title: Text('${s['name']} ($freq)'),
                              subtitle: Text(
                                '${s['code']} / '
                                'TD:${s['tdCount'] ?? 0}, TS:${s['tsCount'] ?? 0}\n'
                                '$formattedLastUpdate',
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete),
                                onPressed: () => _removeStock(localId),
                              ),
                              onTap: () {
                                // 進入詳細頁
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockDetail(
                                      stockCode: s['code'],
                                      stockName: s['name'],
                                      freq: freq,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_isUpdating)
          ModalBarrier(dismissible: false, color: Colors.black45),
        if (_isUpdating)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  value:
                      _totalStocks > 0 ? _updateProgress / _totalStocks : null,
                ),
                SizedBox(height: 16),
                Text(
                  '更新中 $_updateProgress / $_totalStocks',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
