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

  /// 從本地 stocks 撈到的(且在 watchlist 裏)資料
  List<Map<String, dynamic>> _stocks = [];

  /// 要顯示在 ListView 的最終結果
  List<Map<String, dynamic>> _filteredStocks = [];

  /// 是否正在「更新 / 抓資料」
  bool _isUpdating = false;
  int _updateProgress = 0;
  int _totalStocks = 0;

  /// 篩選週期
  String _filterFreq = 'All'; // All / Day / Week

  /// 篩選訊號
  String _filterSignal = 'All'; // All / TD / TS

  /// 若不為 null => 從後端查當天訊號
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadAllData(); // 初始先載入本地 watchlist 資料
  }

  /// [A] 載入本地 watchlist 資料 (不含 signals)
  ///    然後套用週期 / 信號篩選
  Future<void> _loadAllData() async {
    try {
      // 1) 拿到 watchlist 中的股票 code
      final watchData = await dbHelper.getWatchlist();
      final watchCodes =
          watchData.map<String>((m) => m['code'] as String).toSet();

      // 2) 撈出本地 stocks，僅保留屬於 watchlist 的
      final allStocks = await dbHelper.getStocks();
      final filtered = allStocks.where((s) => watchCodes.contains(s['code']));

      // [篩選] freq / signal
      List<Map<String, dynamic>> temp = filtered.toList();

      // 週期篩選
      if (_filterFreq != 'All') {
        temp = temp.where((s) => s['freq'] == _filterFreq).toList();
      }
      // 信號篩選
      if (_filterSignal == 'TD') {
        temp = temp.where((s) => s['signal'] == '闪电').toList();
      } else if (_filterSignal == 'TS') {
        temp = temp.where((s) => s['signal'] == '钻石').toList();
      }

      setState(() {
        _stocks = filtered.toList(); // watchlist 全部
        _filteredStocks = temp; // 篩選後結果
      });
    } catch (e) {
      print('Error loadAllData: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入本地資料失敗: $e')),
        );
      }
    }
  }

  /// [B] 從伺服器抓「指定日期」有訊號的股票
  ///    注意：後端可能一次回傳多筆(同股票不同signal)，這裡合併成單一筆
  Future<void> _fetchStocksBySelectedDate() async {
    if (_selectedDate == null) return; // 若尚未選日期，直接略過

    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = 0;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      // freq=All 就不傳; signal=All 就不傳
      String? freqParam = (_filterFreq != 'All') ? _filterFreq : null;
      String? signalParam;
      if (_filterSignal == 'TD') {
        signalParam = 'TD';
      } else if (_filterSignal == 'TS') {
        signalParam = 'TS';
      }

      // 呼叫後端 API
      final rawList = await api.getStocksByDate(
        date: dateStr,
        freq: freqParam,
        signalType: signalParam,
      ); // 可能結構: [{stockId, code, name, freq, date, signal, tdCount, tsCount}, ...]

      // 同一股票若有多筆(多個訊號)，合併只顯示一個圖示
      // 先用 stockId 當 key，彙整
      final Map<int, Map<String, dynamic>> merged = {};

      for (var r in rawList) {
        final stockId = r['stockId'] as int;
        if (!merged.containsKey(stockId)) {
          // 第一筆
          merged[stockId] = {
            ...r,
            // 用 Set 來裝可能的 signals
            'signalSet': <String>{if (r['signal'] != null) r['signal']},
          };
        } else {
          // 已存在 => 加入新的 signal
          final exist = merged[stockId]!;
          final sigSet = exist['signalSet'] as Set<String>;
          if (r['signal'] != null) {
            sigSet.add(r['signal']);
          }
        }
      }

      // 整理 => 若同時有 "闪电" "钻石" 就給某個特殊圖示 or 二擇一
      final List<Map<String, dynamic>> finalList = [];
      merged.forEach((stockId, item) {
        final sigSet = item['signalSet'] as Set<String>;
        String finalSignal;
        if (sigSet.contains('闪电') && sigSet.contains('钻石')) {
          // 例如統一用 'both' 或自己決定
          finalSignal = 'both';
        } else if (sigSet.contains('闪电')) {
          finalSignal = '闪电';
        } else if (sigSet.contains('钻石')) {
          finalSignal = '钻石';
        } else {
          finalSignal = ''; // 沒有特殊訊號
        }
        item['signal'] = finalSignal;
        item.remove('signalSet'); // 移除臨時欄位
        finalList.add(item);
      });

      setState(() {
        _filteredStocks = finalList;
      });
    } catch (e) {
      print('Error fetchStocksBySelectedDate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('查詢伺服器失敗: $e')),
        );
      }
    }

    setState(() {
      _isUpdating = false;
    });
  }

  /// [C] 更新(一鍵更新)
  /// - 若未選日期 => 還是舊有 "getAllStocks" -> 同步本地
  /// - 若已選日期 => 直接重新抓當日訊號
  Future<void> _updateAllStocks() async {
    if (_selectedDate != null) {
      // 已選日期 => 直接抓當日訊號
      await _fetchStocksBySelectedDate();
      return;
    }

    // 未選日期 => 舊有流程
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _filteredStocks.length;
    });

    try {
      final remoteList = await api.getAllStocks(); // 舊有(全部)
      // 同步到本地 ...
      final localAll = await dbHelper.getStocks();
      final Map<String, Map<String, dynamic>> codeFreqToLocal = {};
      for (var loc in localAll) {
        final key = '${loc['code']}|${loc['freq']}';
        codeFreqToLocal[key] = loc;
      }

      for (var remote in remoteList) {
        final serverId = remote['id'] as int;
        final code = remote['code'] as String;
        final freq = remote['freq'] as String? ?? 'Day';
        final key = '$code|$freq';

        if (codeFreqToLocal.containsKey(key)) {
          final localStock = codeFreqToLocal[key]!;
          final localId = localStock['id'] as int;
          // 更新 stocks
          await dbHelper.updateStockServerId(localId, serverId);
          await dbHelper.updateStockSignal(
            localId,
            remote['signal'],
            remote['lastUpdate'] ?? DateTime.now().toString(),
            remote['tdCount'] ?? 0,
            remote['tsCount'] ?? 0,
          );
        }

        // 同步 signals (先刪再插)
        final signals = remote['signals'] as List<dynamic>? ?? [];
        await dbHelper.deleteSignalsByStockId(serverId);
        if (signals.isNotEmpty) {
          final toInsert = signals
              .map((sig) => {
                    'id': sig['id'],
                    'stockId': sig['stockId'],
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

      // 重新載入本地 watchlist
      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有股票已更新 (本地模式)')),
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

  /// 點擊日期選擇器 => 選了日期 => 直接從後端抓「當日有信號」列表
  Future<void> _pickDate() async {
    final initialDate = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
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
      // 從伺服器抓當日訊號
      await _fetchStocksBySelectedDate();
    }
  }

  /// 清除日期 => 回到本地 watchlist 資料
  void _clearDate() async {
    setState(() {
      _selectedDate = null;
    });
    await _loadAllData();
  }

  /// 顯示 stocks 的 lastUpdate
  String _formatLastUpdate(String? lastUpdateStr, String freq) {
    if (lastUpdateStr == null) return '未更新';
    DateTime dt;
    try {
      dt = DateTime.parse(lastUpdateStr);
    } catch (e) {
      return '格式錯誤';
    }
    if (freq == 'Week') {
      final monday = dt.subtract(Duration(days: dt.weekday - 1));
      return '最後更新：${DateFormat('yyyy-MM-dd').format(monday)}';
    } else {
      return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
    }
  }

  /// 依 signal 顯示對應 icon
  /// 如果同時有閃電+鑽石，就傳回 'both' => 用自訂 icon
  Widget _buildSignalIcon(String? signal) {
    switch (signal) {
      case '闪电':
        return Icon(Icons.flash_on, color: Colors.green);
      case '钻石':
        return Icon(Icons.diamond, color: Colors.red);
      case 'both':
        // 同時有閃電+鑽石 => 用 stars
        return Icon(Icons.stars, color: Colors.purple);
      default:
        return Icon(Icons.do_not_disturb, color: Colors.grey);
    }
  }

  /// 刪除本地 DB 中的股票
  Future<void> _removeStock(int localId) async {
    try {
      await dbHelper.deleteStock(localId);
      if (_selectedDate == null) {
        // 未選日期 => 重新載本地
        await _loadAllData();
      } else {
        // 已選日期 => 再次抓當日
        await _fetchStocksBySelectedDate();
      }
    } catch (e) {
      print('Error removing stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 半透明遮罩區 (若 _isUpdating)
        IgnorePointer(
          ignoring: _isUpdating,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Stocks (只顯示 watchlist)'),
              actions: [
                // 「更新」按鈕
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
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() {
                        _filterFreq = val;
                      });
                      // 若未選日期 => 套用本地
                      if (_selectedDate == null) {
                        await _loadAllData();
                      } else {
                        // 已選日期 => 重新抓當日
                        await _fetchStocksBySelectedDate();
                      }
                    }
                  },
                  underline: SizedBox(),
                ),
                // 訊號篩選
                DropdownButton<String>(
                  value: _filterSignal,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部信號')),
                    DropdownMenuItem(value: 'TD', child: Text('TD(閃電)')),
                    DropdownMenuItem(value: 'TS', child: Text('TS(鑽石)')),
                  ],
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() {
                        _filterSignal = val;
                      });
                      if (_selectedDate == null) {
                        await _loadAllData();
                      } else {
                        await _fetchStocksBySelectedDate();
                      }
                    }
                  },
                  underline: SizedBox(),
                ),
                SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                // 上方選擇日期 & 數量
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

                            // 若是本地 stocks => 會有 id; 伺服器回傳 => 可能沒有 localId
                            final localId = s['id'] as int?;
                            final freq = (s['freq'] ?? 'Day').toString();
                            final code = (s['code'] ?? '').toString();
                            final name = (s['name'] ?? '').toString();
                            final signal = s['signal']?.toString() ?? '';
                            final tdCount = s['tdCount'] ?? 0;
                            final tsCount = s['tsCount'] ?? 0;

                            // lastUpdate 可能只有本地 stocks 才有
                            final lastUpdateStr = s['lastUpdate']?.toString();
                            final formattedLastUpdate =
                                _formatLastUpdate(lastUpdateStr, freq);

                            return ListTile(
                              leading: _buildSignalIcon(signal),
                              title: Text('$name ($freq)'),
                              subtitle: Text(
                                '$code / TD:$tdCount, TS:$tsCount\n$formattedLastUpdate',
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete),
                                onPressed: () {
                                  if (localId != null) {
                                    _removeStock(localId);
                                  } else {
                                    // 伺服器回傳、但本地不存在 => 不能刪
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('此股票不存在本地DB，無法刪除'),
                                      ),
                                    );
                                  }
                                },
                              ),
                              onTap: () {
                                // 進入詳細頁
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockDetail(
                                      stockCode: code,
                                      stockName: name,
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
