import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
import 'package:intl/intl.dart';
import '../models/stock_data.dart'; // <-- 同一個StockData
import '../components/Char.dart'; // 你的KLineChart widget
// 若 KLineChart 需要 "StockData" 類，就在這裡定義或 import

class StockDetail extends StatefulWidget {
  final String stockCode; // e.g. "2330"
  final String stockName; // e.g. "台積電"
  final String freq; // "Day" or "Week"

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
  bool _loading = true; // 是否正在加載
  String? _errorMessage; // 若加載失敗，記錄錯誤
  List<StockData> _historyList = []; // FinMind 回傳的K線資料

  // 若 KLineChart 有計算到某些 signalDays, 透過callback傳回
  List<StockData> signalDays = [];
  void _handleSignalData(List<StockData> signals) {
    setState(() {
      signalDays = signals;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchHistoryFromFinMind();
  }

  // -----------------------------
  // 1) 從 FinMind API 抓取日/週歷史K線
  // -----------------------------
  Future<void> _fetchHistoryFromFinMind() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _historyList = [];
    });

    try {
      // 依 freq 選擇 dataset
      // freq == 'Week' => TaiwanStockWeekPrice
      // freq == 'Day'  => TaiwanStockPrice
      final dataset =
          (widget.freq == 'Week') ? 'TaiwanStockWeekPrice' : 'TaiwanStockPrice';

      // FinMind Token
      const finmindToken =
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkYXRlIjoiMjAyNS0wMS0yNyAxNjozNTo0NiIsInVzZXJfaWQiOiJsb2hjaGFuaGluIiwiaXAiOiIxLjE2MC4xNDUuNDUifQ.JHGsTKrthx2CKUcxJj1r9Yclk6KCh4y6IFqzrev9t2I';

      // 設定查詢區間: 例如抓最近 1 年
      final now = DateTime.now();
      final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
      final startDate = DateFormat('yyyy-MM-dd').format(oneYearAgo);

      final url = Uri.parse(
        'https://api.finmindtrade.com/api/v4/data?'
        'dataset=$dataset&'
        'data_id=${widget.stockCode}&'
        'start_date=$startDate&'
        'token=$finmindToken',
      );

      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final jsonBody = json.decode(resp.body);

        if (jsonBody['status'] != 200) {
          throw Exception(
              'FinMind API Error: ${jsonBody["msg"] ?? jsonBody["info"]}');
        }

        final List<dynamic> dataList = jsonBody['data'];
        if (dataList.isEmpty) {
          throw Exception('FinMind回傳空資料');
        }

        // 依 dataset 不同, 週線 volume 欄位是 "trading_volume", 日線 volume 欄位是 "Trading_Volume"
        final isWeek = (dataset == 'TaiwanStockWeekPrice');

        // 解析
        final List<StockData> parsed = [];
        for (var item in dataList) {
          final date = item['date'];
          final open = item['open'];
          final high = item['max'];
          final low = item['min'];
          final close = item['close'];
          final volume =
              isWeek ? item['trading_volume'] : item['Trading_Volume'];

          // 若任何為 null => 跳過
          if (date == null ||
              open == null ||
              high == null ||
              low == null ||
              close == null ||
              volume == null) {
            continue;
          }

          // FinMind 沒有 adjClose => 就直接用 close
          parsed.add(
            StockData(
              date: date.toString(),
              open: (open as num).toDouble(),
              high: (high as num).toDouble(),
              low: (low as num).toDouble(),
              close: (close as num).toDouble(),
              adjClose: (close as num).toDouble(),
              volume: (volume as num).toInt(),
            ),
          );
        }

        if (parsed.isEmpty) {
          throw Exception('解析後沒有有效的K線資料');
        }

        // FinMind 回傳順序大多是舊->新，也可能相反
        // 你可依需求决定是否 reversed
        // 這裡假設 KLineChart 需要「舊 => 新」的陣列
        parsed.sort((a, b) => a.date.compareTo(b.date));

        setState(() {
          _historyList = parsed;
          _loading = false;
        });
      } else {
        throw Exception('HTTP ${resp.statusCode} error');
      }
    } catch (e, st) {
      log('Error fetching data from FinMind: $e', stackTrace: st);
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  // -----------------------------
  // 2) UI
  // -----------------------------
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
                        // ★ 上半: Chart
                        Expanded(
                          flex: 1,
                          child: KLineChart(
                            stockData: _historyList,
                            onSignalData: _handleSignalData,
                          ),
                        ),
                        // ★ 下半: 顯示計算到的訊號列表
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
