import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
import 'package:intl/intl.dart';
import '../models/stock_data.dart'; // StockData 包含 date, open, high, low, close, adjClose, volume 與 isBullishSignal 屬性
import '../components/Char.dart'; // 你的 KLineChart widget

class StockDetail extends StatefulWidget {
  final String stockCode; // 例如 "2330"
  final String stockName; // 例如 "台積電"
  final String freq; // "Day" 或 "Week"

  const StockDetail({
    Key? key,
    required this.stockCode,
    required this.stockName,
    required this.freq,
  }) : super(key: key);

  @override
  _StockDetailState createState() => _StockDetailState();
}

class _StockDetailState extends State<StockDetail> {
  bool _loading = true;
  String? _errorMessage;
  List<StockData> _historyList = [];
  List<StockData> signalDays = [];

  // 請將下列 token 改成正確的 FinMind API Token
  final String finmindToken =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkYXRlIjoiMjAyNS0wMi0xOCAwMToyOTo1NyIsInVzZXJfaWQiOiJsb2hjaGFuaGluIiwiaXAiOiIzNi4yMjUuMTU3LjEwIn0.u03i4v1534gBBKs_PoiocZ7_M-R6pepZ8GBGaEKgwyA';

  @override
  void initState() {
    super.initState();
    _fetchHistoryFromFinMind();
  }

  /// 取得歷史資料 (TaiwanStockPrice)
  Future<List<StockData>> _fetchHistoricalData() async {
    const String histDataset = "TaiwanStockPrice";
    final now = DateTime.now();
    // 此處抓取過去 5 年的資料
    final startDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(now.year - 5, now.month, now.day));
    final url = Uri.parse(
      'https://api.finmindtrade.com/api/v4/data?dataset=$histDataset&data_id=${widget.stockCode}&start_date=$startDate&token=$finmindToken',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} error (歷史資料)');
    }
    final histJson = json.decode(response.body);
    if (histJson['status'] != 200) {
      throw Exception(
          'FinMind API Error (TaiwanStockPrice): ${histJson["msg"] ?? histJson["info"]}');
    }
    final List<dynamic> dataList = histJson['data'];
    if (dataList.isEmpty) {
      throw Exception('FinMind 回傳空的歷史資料');
    }
    List<StockData> historical = [];
    for (var item in dataList) {
      if (item['date'] == null ||
          item['open'] == null ||
          item['max'] == null ||
          item['min'] == null ||
          item['close'] == null ||
          item['Trading_Volume'] == null) {
        continue;
      }
      historical.add(
        StockData(
          date: item['date'].toString(),
          open: (item['open'] as num).toDouble(),
          high: (item['max'] as num).toDouble(),
          low: (item['min'] as num).toDouble(),
          close: (item['close'] as num).toDouble(),
          adjClose: (item['close'] as num).toDouble(),
          volume: (item['Trading_Volume'] as num).toInt(),
          isBullishSignal: null,
        ),
      );
    }
    return historical;
  }

  /// 取得即時資料，使用官方 endpoint "taiwan_stock_tick_snapshot"
  /// 若非開盤時間或發生錯誤，則回傳空陣列
  Future<List<StockData>> _fetchRealtimeData() async {
    final url = Uri.parse(
      'https://api.finmindtrade.com/api/v4/taiwan_stock_tick_snapshot?data_id=${widget.stockCode}&token=$finmindToken',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} error (即時資料)');
      }
      final realtimeJson = json.decode(response.body);
      if (realtimeJson['status'] != 200) {
        throw Exception(
            'FinMind API Error (taiwan_stock_tick_snapshot): ${realtimeJson["msg"] ?? realtimeJson["info"]}');
      }
      final List<dynamic> dataList = realtimeJson['data'];
      List<StockData> realtime = [];
      for (var item in dataList) {
        if (item['date'] == null ||
            item['open'] == null ||
            item['high'] == null ||
            item['low'] == null ||
            item['close'] == null ||
            item['volume'] == null) {
          continue;
        }
        realtime.add(
          StockData(
            date: item['date'].toString(),
            open: (item['open'] as num).toDouble(),
            high: (item['high'] as num).toDouble(),
            low: (item['low'] as num).toDouble(),
            close: (item['close'] as num).toDouble(),
            adjClose: (item['close'] as num).toDouble(),
            volume: (item['volume'] as num).toInt(),
            isBullishSignal: null,
          ),
        );
      }
      return realtime;
    } catch (e) {
      log('Warning: 即時資料取得失敗，僅使用歷史資料。錯誤訊息: $e');
      return [];
    }
  }

  /// 取得歷史與即時資料後合併、排序並處理（依日或週模式）
  Future<void> _fetchHistoryFromFinMind() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _historyList = [];
      signalDays = [];
    });
    try {
      final historical = await _fetchHistoricalData();
      final realtime = await _fetchRealtimeData();
      // 合併資料
      List<StockData> combined = [...historical, ...realtime];
      combined.sort((a, b) => a.date.compareTo(b.date));

      // 若為週模式，根據 ISO 週進行分組並計算平均值
      List<StockData> finalData;
      if (widget.freq == 'Week') {
        Map<String, List<StockData>> groups = {};
        for (var data in combined) {
          DateTime dt = DateTime.parse(data.date);
          // 以該週的週一作為代表日期
          DateTime monday = dt.subtract(Duration(days: dt.weekday - 1));
          String mondayStr = DateFormat('yyyy-MM-dd').format(monday);
          groups.putIfAbsent(mondayStr, () => []);
          groups[mondayStr]!.add(data);
        }
        List<StockData> weeklyData = [];
        groups.forEach((week, stocks) {
          int count = stocks.length;
          double sumOpen = stocks.fold(0.0, (sum, s) => sum + s.open);
          double sumHigh = stocks.fold(0.0, (sum, s) => sum + s.high);
          double sumLow = stocks.fold(0.0, (sum, s) => sum + s.low);
          double sumClose = stocks.fold(0.0, (sum, s) => sum + s.close);
          int sumVolume = stocks.fold(0, (sum, s) => sum + s.volume);
          weeklyData.add(
            StockData(
              date: week,
              open: sumOpen / count,
              high: sumHigh / count,
              low: sumLow / count,
              close: sumClose / count,
              adjClose: sumClose / count,
              volume: (sumVolume / count).round(),
              isBullishSignal: null,
            ),
          );
        });
        weeklyData.sort((a, b) => a.date.compareTo(b.date));
        finalData = weeklyData;
      } else {
        finalData = combined;
      }

      // 計算 TD/TS 訊號 (以收盤價作為判斷標準)
      List<StockData> computedSignals = _calculateSignals(finalData);

      setState(() {
        _historyList = finalData;
        signalDays = computedSignals;
        _loading = false;
      });
    } catch (e, st) {
      log('Error fetching data from FinMind: $e', stackTrace: st);
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  /// 根據資料依 TD/TS 演算法計算訊號
  /// 條件：以第 i 根資料的收盤價與第 i-4 根比較，
  ///       若大於則累加 TD (若 TD[i-1] < 9，則 TD[i] = TD[i-1] + 1，否則重置為 1)；反之累加 TS
  ///       當某序列累計達 9 時，分別觸發賣訊號 (TD==9，isBullishSignal = false) 或買訊號 (TS==9，isBullishSignal = true)
  List<StockData> _calculateSignals(List<StockData> data) {
    List<int> td = List.filled(data.length, 0);
    List<int> ts = List.filled(data.length, 0);
    List<StockData> signals = [];
    for (int i = 0; i < data.length; i++) {
      if (i < 4) {
        td[i] = 0;
        ts[i] = 0;
        continue;
      }
      double currentClose = data[i].close;
      double close4Ago = data[i - 4].close;
      if (currentClose > close4Ago) {
        td[i] = (td[i - 1] < 9) ? td[i - 1] + 1 : 1;
      } else {
        td[i] = 0;
      }
      if (currentClose < close4Ago) {
        ts[i] = (ts[i - 1] < 9) ? ts[i - 1] + 1 : 1;
      } else {
        ts[i] = 0;
      }
      if (td[i] == 9) {
        signals.add(data[i].copyWith(isBullishSignal: false));
      }
      if (ts[i] == 9) {
        signals.add(data[i].copyWith(isBullishSignal: true));
      }
    }
    return signals;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stockName} (${widget.freq})'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchHistoryFromFinMind,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : (_errorMessage != null)
              ? Center(child: Text('Error: $_errorMessage'))
              : _historyList.isEmpty
                  ? Center(child: Text('無資料'))
                  : Column(
                      children: [
                        // 上半部：K 線圖
                        Expanded(
                          flex: 1,
                          child: KLineChart(
                            stockData: _historyList,
                            onSignalData: (signals) {
                              setState(() {
                                signalDays = signals;
                              });
                            },
                          ),
                        ),
                        // 下半部：訊號列表
                        Expanded(
                          flex: 1,
                          child: signalDays.isEmpty
                              ? Center(child: Text('無任何達成訊號日'))
                              : ListView.builder(
                                  itemCount: signalDays.length,
                                  itemBuilder: (_, idx) {
                                    final sd = signalDays[idx];
                                    final signalStr = sd.isBullishSignal == true
                                        ? '閃電'
                                        : '鑽石';
                                    return ListTile(
                                      title: Text('${sd.date} => $signalStr'),
                                      subtitle: Text(
                                          'O=${sd.open}, C=${sd.close}, V=${sd.volume}'),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }
}
