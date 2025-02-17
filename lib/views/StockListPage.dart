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

  List<Map<String, dynamic>> _stocks = []; // 本地 DB 所有股票資料
  List<Map<String, dynamic>> _filteredStocks = []; // 篩選後的結果

  Set<String> _watchlistCodes = {}; // watchlist 內的股票 code
  bool _isUpdating = false;
  int _updateProgress = 0;
  int _totalStocks = 0;

  String _filterFreq = 'All'; // 篩選週期：All / Day / Week
  String _filterSignal = 'All'; // 篩選訊號：All / TD(闪电) / TS(钻石)

  DateTime? _selectedDate; // 若不為 null，依此日期進行篩選

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  /// 比較兩個日期是否為同一天（忽略時間部分）
  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 從資料庫讀取 watchlist 與股票資料，並僅保留 watchlist 內的股票
  Future<void> _loadAllData() async {
    try {
      // 取得 watchlist 中的股票 code
      final watchData = await dbHelper.getWatchlist();
      final codes = watchData.map<String>((m) => m['code'] as String).toSet();

      // 讀取所有股票資料，並僅保留 code 在 watchlist 內的記錄
      final allStocks = await dbHelper.getStocks();
      final filtered =
          allStocks.where((s) => codes.contains(s['code'])).toList();

      setState(() {
        _watchlistCodes = codes;
        _stocks = filtered;
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

  /// 篩選邏輯：
  /// 1. 依週期（_filterFreq）篩選
  /// 2. 依訊號（_filterSignal）篩選
  /// 3. 若有選擇日期，則：
  ///    - signal 為「闪电」的股票必須其 lastUpdate 與選擇日期同一天
  ///    - signal 為「钻石」或其他的則不受日期限制
  void _applyFilter() {
    List<Map<String, dynamic>> temp = List.from(_stocks);

    // 依週期篩選
    if (_filterFreq != 'All') {
      temp = temp.where((s) => s['freq'] == _filterFreq).toList();
    }

    // 依訊號篩選：TD 表示闪电，TS 表示 钻石
    if (_filterSignal == 'TD') {
      temp = temp.where((s) => s['signal'] == '闪电').toList();
    } else if (_filterSignal == 'TS') {
      temp = temp.where((s) => s['signal'] == '钻石').toList();
    }

    // 日期篩選：僅對 signal 為闪电的股票進行日期比對
    if (_selectedDate != null) {
      temp = temp.where((s) {
        if (s['lastUpdate'] == null) return false;
        DateTime lastUpdate;
        try {
          lastUpdate = DateTime.parse(s['lastUpdate']);
        } catch (e) {
          return false;
        }
        if (s['signal'] == '闪电') {
          return isSameDate(lastUpdate, _selectedDate!);
        }
        return true;
      }).toList();
    }

    setState(() {
      _filteredStocks = temp;
    });
  }

  /// 根據頻率對最後更新時間進行格式化：
  /// - 日線直接顯示原日期
  /// - 週線則以該日期所屬週的「週一」作為代表日期
  String _formatLastUpdate(String? lastUpdateStr, String freq) {
    if (lastUpdateStr == null) return '未更新';
    DateTime dt;
    try {
      dt = DateTime.parse(lastUpdateStr);
    } catch (e) {
      return '格式錯誤';
    }
    if (freq == 'Week') {
      // 以該日期所屬週的週一為代表
      DateTime monday = dt.subtract(Duration(days: dt.weekday - 1));
      return '最後更新：${DateFormat('yyyy-MM-dd').format(monday)}';
    } else {
      return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
    }
  }

  /// 根據 signal 顯示對應圖示
  Widget _buildSignalIcon(String? signal) {
    if (signal == '闪电') {
      return Icon(Icons.flash_on, color: Colors.green);
    } else if (signal == '钻石') {
      return Icon(Icons.diamond, color: Colors.red);
    }
    return Icon(Icons.do_not_disturb, color: Colors.grey);
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
  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _filteredStocks.length;
    });

    try {
      // 範例：先從後端取得最新資料
      final remoteList = await api.getAllStocks();

      // 取得本地所有股票，用以進行 batch 更新
      final localAll = await dbHelper.getStocks();
      final Map<String, int> codeFreqToLocalId = {};
      for (var loc in localAll) {
        final key = '${loc['code']}|${loc['freq']}';
        codeFreqToLocalId[key] = loc['id'];
      }

      final updates = <Map<String, dynamic>>[];
      for (var remote in remoteList) {
        final code = remote['code'];
        final freq = remote['freq'];
        final key = '$code|$freq';
        if (codeFreqToLocalId.containsKey(key)) {
          final localId = codeFreqToLocalId[key];
          updates.add({
            'id': localId,
            'signal': remote['signal'],
            'lastUpdate': remote['lastUpdate'] ?? DateTime.now().toString(),
            'tdCount': remote['tdCount'] ?? 0,
            'tsCount': remote['tsCount'] ?? 0,
          });
        }
      }

      if (updates.isNotEmpty) {
        await dbHelper.batchUpdateStocks(updates);
      }

      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有股票已更新')),
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

  /// 日曆選擇器，讓使用者選取日期進行篩選
  Future<void> _pickDate() async {
    DateTime initialDate = _selectedDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '選擇日期',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _applyFilter();
    }
  }

  /// 清除所選日期
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
                IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
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
                // 上方 Row：日曆選擇與符合條件的股票數量
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.calendar_today),
                        label: Text(_selectedDate == null
                            ? '選擇日期'
                            : DateFormat('yyyy-MM-dd').format(_selectedDate!)),
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
                Expanded(
                  child: _filteredStocks.isEmpty
                      ? Center(child: Text('沒有在 watchlist 中的股票，或篩選無資料'))
                      : ListView.builder(
                          itemCount: _filteredStocks.length,
                          itemBuilder: (ctx, i) {
                            final s = _filteredStocks[i];
                            // 依據股票週期，格式化 lastUpdate 日期
                            final formattedLastUpdate = _formatLastUpdate(
                              s['lastUpdate'],
                              s['freq'] ?? 'Day',
                            );
                            return ListTile(
                              leading: _buildSignalIcon(s['signal']),
                              title: Text('${s['name']} (${s['freq']})'),
                              subtitle: Text(
                                '${s['code']} / '
                                'TD:${s['tdCount'] ?? 0}, TS:${s['tsCount'] ?? 0}\n'
                                '$formattedLastUpdate',
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete),
                                onPressed: () => _removeStock(s['id']),
                              ),
                              onTap: () {
                                // 點擊進入詳細頁面，傳入正確的股票代號、名稱與週期
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockDetail(
                                      stockCode: s['code'],
                                      stockName: s['name'],
                                      freq: s['freq'],
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
