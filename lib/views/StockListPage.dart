import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui' as ui; // 用於 BackdropFilter
import 'package:intl/intl.dart';

import '../database/DatabaseHelper.dart';
import '../components/StockDetail.dart';

// --------------------------
// Model: StockData
// --------------------------
class StockData {
  final String date;
  final double open, high, low, close, adjClose;
  final int volume;
  int? tdCount;
  bool? isBullishSignal;
  bool? isBearishSignal;

  StockData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.adjClose,
    required this.volume,
    this.tdCount,
    this.isBullishSignal,
    this.isBearishSignal,
  });
}

// --------------------------
// Page: StockListPage
// --------------------------
class StockListPage extends StatefulWidget {
  @override
  _StockListPageState createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  List<Map<String, dynamic>> _stocks = [];
  List<Map<String, dynamic>> _filteredStocks = [];

  String _filterSignal = 'All'; // 篩選條件: All, TD, TS
  String _filterFreq = 'Day'; // 篩選週期: Day, Week, All

  bool _isUpdating = false; // 是否正在更新
  int _updateProgress = 0; // 更新進度
  int _totalStocks = 0; // 總的股票數量

  @override
  void initState() {
    super.initState();
    _loadSavedStocks();
  }

  // 載入所有股票(含 freq)
  Future<void> _loadSavedStocks() async {
    final stocks = await DatabaseHelper.instance.getStocks();
    setState(() {
      _stocks = stocks;
      _applyFilter();
    });
  }

  // 依照 signal + freq 下拉的選擇，過濾出要顯示的股票
  void _applyFilter() {
    setState(() {
      // 1) 先依照 freq 過濾
      List<Map<String, dynamic>> temp;
      if (_filterFreq == 'All') {
        temp = _stocks;
      } else {
        temp = _stocks.where((s) => s['freq'] == _filterFreq).toList();
      }

      // 2) 再依照 signal 過濾
      if (_filterSignal == 'All') {
        _filteredStocks = temp;
      } else if (_filterSignal == 'TD') {
        _filteredStocks =
            temp.where((stock) => stock['signal'] == '闪电').toList();
      } else if (_filterSignal == 'TS') {
        _filteredStocks =
            temp.where((stock) => stock['signal'] == '钻石').toList();
      }
    });
  }

  void _removeStock(int id) async {
    await DatabaseHelper.instance.deleteStock(id);
    _loadSavedStocks();
  }

  // 格式化 "最後更新" 文字
  String _formatLastUpdate(String? lastUpdate) {
    if (lastUpdate == null) {
      return '未更新';
    } else {
      DateTime dateTime = DateTime.parse(lastUpdate);
      String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
      return '最後更新：$formattedDate';
    }
  }

  // 根據 signal 顯示 icon
  Widget _buildSignalIcon(String? signal) {
    if (signal == '闪电') {
      return Icon(Icons.flash_on, color: Colors.green);
    } else if (signal == '钻石') {
      return Icon(Icons.diamond, color: Colors.red);
    } else {
      return Icon(Icons.do_not_disturb, color: Colors.grey);
    }
  }

  // --------------------------
  // (按「更新全部」) -> 更新當前篩選後的股票
  // --------------------------
  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
    });

    // 只更新當前 _filteredStocks 中的股票
    final updatingStocks = List<Map<String, dynamic>>.from(_filteredStocks);
    setState(() {
      _totalStocks = updatingStocks.length;
    });

    // 暫存更新結果
    List<Map<String, dynamic>> updateResults = [];

    for (var stock in updatingStocks) {
      // 1) 只做網路或邏輯計算，先不要直接寫 DB
      var result = await _fetchAndCalculateSignal(
        stock['code'],
        stock['freq'] ?? 'Day',
      );
      String lastUpdate = DateTime.now().toString();
      updateResults.add({
        'id': stock['id'],
        'signal': result['signal'],
        'lastUpdate': lastUpdate,
        'tdCount': result['tdCount'],
        'tsCount': result['tsCount'],
      });

      // 可用 setState() 顯示進度
      setState(() {
        _updateProgress++;
      });
    }

    // 2) 統一寫入資料庫
    await DatabaseHelper.instance.batchUpdateStocks(updateResults);

    // 3) 重新載入
    await _loadSavedStocks();

    setState(() {
      _isUpdating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('所有股票已更新')),
    );
  }

  // (可選) 更新單一支股票
  Future<void> _updateSingleStock(Map<String, dynamic> stock) async {
    int id = stock['id'];
    String code = stock['code'];
    String freq = stock['freq'] ?? 'Day';

    var result = await _fetchAndCalculateSignal(code, freq);
    String lastUpdate = DateTime.now().toString();

    await DatabaseHelper.instance.updateStockSignal(
      id,
      result['signal'],
      lastUpdate,
      result['tdCount'],
      result['tsCount'],
    );

    setState(() {
      _updateProgress++;
    });
  }

  // ---------------------------------------------------
  // 核心：抓 FinMind API (日 or 週) -> TD/TS 計算
  // ---------------------------------------------------
  Future<Map<String, dynamic>> _fetchAndCalculateSignal(
    String stockCode,
    String freq,
  ) async {
    try {
      // 1) 計算一年前的日期，格式化成 yyyy-MM-dd
      final now = DateTime.now();
      final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
      final formattedStartDate = DateFormat('yyyy-MM-dd').format(oneYearAgo);

      // 2) 根據 freq 決定要用 day or week dataset
      final dataset =
          (freq == 'Week') ? 'TaiwanStockWeekPrice' : 'TaiwanStockPrice';

      // 3) 撈 FinMind 資料
      const token =
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkYXRlIjoiMjAyNS0wMS0xMCAwMTo0ODoyNyIsInVzZXJfaWQiOiJsb2hjaGFuaGluIiwiaXAiOiIxLjE2MC4xNjkuMTAwIn0.PWmTcSC8DeZsspyTOZf6qMXO6GjlhGNG655IBxByfWs'; // <-- 請換成你的 token
      final stockData = await fetchStockHistoryFromFinMind(
        stockCode: stockCode,
        dataset: dataset,
        token: token,
        startDate: formattedStartDate,
      );

      // 4) TD/TS 計算
      List<int> tdCounts = List.filled(stockData.length, 0);
      List<int> tsCounts = List.filled(stockData.length, 0);
      _calculateTDTSCounts(stockData, tdCounts, tsCounts);

      int lastIndex = stockData.length - 1;
      int currentTDCount = tdCounts[lastIndex];
      int currentTSCount = tsCounts[lastIndex];

      String? signal;
      if (currentTDCount == 9) {
        signal = '闪电';
      } else if (currentTSCount == 9) {
        signal = '钻石';
      }

      return {
        'signal': signal,
        'tdCount': currentTDCount,
        'tsCount': currentTSCount,
      };
    } catch (e) {
      print('Error fetching or calculating signal for $stockCode: $e');
      return {
        'signal': null,
        'tdCount': 0,
        'tsCount': 0,
      };
    }
  }

  // ---------------------------------------------------
  // 用 FinMind API 撈資料 (處理日/週欄位差異 + null 檢查)
  // ---------------------------------------------------
  Future<List<StockData>> fetchStockHistoryFromFinMind({
    required String stockCode,
    required String dataset, // TaiwanStockPrice / TaiwanStockWeekPrice
    required String token,
    required String startDate,
  }) async {
    final url = Uri.parse(
      'https://api.finmindtrade.com/api/v4/data?'
      'dataset=$dataset&'
      'data_id=$stockCode&'
      'start_date=$startDate&'
      'token=$token',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
      if (jsonResponse['status'] == 200) {
        final List<dynamic> dataList = jsonResponse['data'];
        List<StockData> stockDataList = [];

        // 判斷週線 / 日線，對應不同欄位
        final bool isWeek = (dataset == 'TaiwanStockWeekPrice');

        for (var item in dataList) {
          final date = item['date'];
          final open = item['open'];
          final high = item['max'];
          final low = item['min'];
          final close = item['close'];

          // 週線: 'trading_volume' / 日線: 'Trading_Volume'
          final volume =
              isWeek ? item['trading_volume'] : item['Trading_Volume'];

          // (1) 先檢查欄位是否為 null
          if (date == null ||
              open == null ||
              high == null ||
              low == null ||
              close == null ||
              volume == null) {
            // 若任何關鍵數值是 null，就跳過這筆
            // （或你可以選擇給預設值 0.0 / 0）
            print('跳過 null 資料: $item');
            continue;
          }

          // (2) 開始轉型
          final dateStr = date as String;
          final openVal = (open as num).toDouble();
          final highVal = (high as num).toDouble();
          final lowVal = (low as num).toDouble();
          final closeVal = (close as num).toDouble();
          final volVal = (volume as num).toInt();

          // (3) 加入清單
          stockDataList.add(
            StockData(
              date: dateStr,
              open: openVal,
              high: highVal,
              low: lowVal,
              close: closeVal,
              adjClose: closeVal, // FinMind 沒有提供 adjClose，就用 close
              volume: volVal,
            ),
          );
        }

        // FinMind 回傳通常是由舊到新，不需要 reversed()，視你 TD/TS 計算邏輯需求而定
        return stockDataList;
      } else {
        throw Exception('FinMind 回傳異常: ${jsonResponse['info']}');
      }
    } else {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------
  // TD/TS 計算邏輯
  // ---------------------------------------------------
  void _calculateTDTSCounts(
    List<StockData> data,
    List<int> tdCounts,
    List<int> tsCounts,
  ) {
    for (int i = 4; i < data.length; i++) {
      final close_i = data[i].close;
      final close_i4 = data[i - 4].close;
      final condition = close_i > close_i4;

      // Debug: 看看運算流程
      print(
          '[i=$i] close_i=$close_i, close_i4=$close_i4, condition=$condition');

      if (condition) {
        // TD
        if (tsCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          tdCounts[i] = 1;
        } else {
          tdCounts[i] = (tdCounts[i - 1] >= 9) ? 1 : tdCounts[i - 1] + 1;
        }
        tsCounts[i] = 0;
      } else {
        // TS
        if (tdCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          tsCounts[i] = 1;
        } else {
          tsCounts[i] = (tsCounts[i - 1] >= 9) ? 1 : tsCounts[i - 1] + 1;
        }
        tdCounts[i] = 0;
      }
    }
  }

  // ---------------------------------------------------
  // UI: Build
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 主內容
        IgnorePointer(
          ignoring: _isUpdating,
          child: Scaffold(
            appBar: AppBar(
              title: Text('已保存的股票'),
              actions: [
                // 更新按鈕
                IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
                SizedBox(width: 8),
                // 篩選週期 (Day, Week, All)
                DropdownButton<String>(
                  value: _filterFreq,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部週期')),
                    DropdownMenuItem(value: 'Day', child: Text('日線')),
                    DropdownMenuItem(value: 'Week', child: Text('週線')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _filterFreq = value!;
                      _applyFilter();
                    });
                  },
                  underline: SizedBox(),
                ),
                SizedBox(width: 8),
                // 篩選信號 (All, TD, TS)
                DropdownButton<String>(
                  value: _filterSignal,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部信號')),
                    DropdownMenuItem(value: 'TD', child: Text('TD 信號')),
                    DropdownMenuItem(value: 'TS', child: Text('TS 信號')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _filterSignal = value!;
                      _applyFilter();
                    });
                  },
                  underline: SizedBox(),
                ),
                SizedBox(width: 8),
              ],
            ),
            body: ListView.builder(
              itemCount: _filteredStocks.length,
              itemBuilder: (context, index) {
                final stock = _filteredStocks[index];
                return ListTile(
                  leading: _buildSignalIcon(stock['signal']),
                  title: Text('${stock['name']} (${stock['freq'] ?? 'Day'})'),
                  subtitle: Text(
                    '${stock['code']} - TD: ${stock['tdCount'] ?? 0}, '
                    'TS: ${stock['tsCount'] ?? 0} - '
                    '${_formatLastUpdate(stock['lastUpdate'])}',
                  ),
                  onTap: () {
                    // 進入詳細頁
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => StockDetail(
                          stockCode: stock['code'],
                          stockName: stock['name'],
                          freq: stock['freq'] ?? 'Day', // <= 把freq也傳過去
                        ),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _removeStock(stock['id']),
                  ),
                );
              },
            ),
          ),
        ),

        // 遮罩 + 進度指示器
        if (_isUpdating) ...[
          ModalBarrier(
            dismissible: false,
            color: Colors.black45,
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(color: Colors.black12),
            ),
          ),
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
      ],
    );
  }
}
