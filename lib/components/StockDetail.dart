import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../components/Char.dart'; // 你的KLineChart
import 'dart:developer';

class StockDetail extends StatefulWidget {
  final String stockCode; // e.g. "2330"
  final String stockName; // e.g. "台積電"
  final String freq; // "Day" / "Week" (僅用來顯示，實際資料從後端拿)

  const StockDetail({
    Key? key,
    required this.stockCode,
    required this.stockName,
    required this.freq,
  }) : super(key: key);

  @override
  _StockDetailState createState() => _StockDetailState();
}

// 方便前端 Chart 繪圖的資料結構
class StockData {
  final String date;
  final double open, high, low, close, adjClose;
  final int volume;

  // 以下若 Chart 需要可加
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

class _StockDetailState extends State<StockDetail> {
  final ApiService api = ApiService();

  bool _loading = true;
  String? _errorMessage;
  List<StockData> _historyList = [];
  Map<String, dynamic>? _stockInfo; // 後端回傳的基本資訊 (可能含 signal, tdCount, tsCount)

  // Chart 回調：回傳計算到的訊號
  List<StockData> signalDays = [];
  void handleSignalData(List<StockData> signals) {
    setState(() {
      signalDays = signals;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchStockDetail();
  }

  // -------------------------
  // 1) 從後端 API 抓取資料
  // -------------------------
  Future<void> _fetchStockDetail() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _historyList = [];
      _stockInfo = null;
    });
    try {
      // 呼叫後端 /api/stocks/:code
      final detail = await api.getStockDetailByCode(widget.stockCode);
      // detail 預期是 { "stockInfo": {...}, "history": [...] }

      if (!detail.containsKey('history')) {
        throw Exception('No "history" field from server');
      }

      // 把 stockInfo 取出
      final info = detail['stockInfo'];
      // 把 history 轉成 List<StockData>
      final List historyJson = detail['history'];
      final List<StockData> parsedHistory = historyJson.map((item) {
        // 確保每個字段都能正確轉型 (double, int)
        return StockData(
          date: item['date'],
          open: (item['open'] as num).toDouble(),
          high: (item['high'] as num).toDouble(),
          low: (item['low'] as num).toDouble(),
          close: (item['close'] as num).toDouble(),
          adjClose: (item['adjClose'] as num).toDouble(),
          volume: (item['volume'] as num).toInt(),
        );
      }).toList();

      setState(() {
        _stockInfo = info;
        _historyList = parsedHistory;
        _loading = false;
      });
    } catch (e) {
      log('Error fetching stock detail: $e');
      setState(() {
        _errorMessage = '$e';
        _loading = false;
      });
    }
  }

  // -------------------------
  // 2) 界面
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stockName} (${widget.freq})'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : _historyList.isEmpty
                  ? Center(child: Text('沒有取得任何K線資料'))
                  : Column(
                      children: [
                        // 1) 顯示上方基本資訊
                        if (_stockInfo != null) ...[
                          ListTile(
                            title: Text(
                                'Signal: ${_stockInfo!['signal'] ?? '無'}  TD:${_stockInfo!['tdCount']}  TS:${_stockInfo!['tsCount']}'),
                            subtitle: Text(
                                'LastUpdate: ${_stockInfo!['lastUpdate']}'),
                          ),
                          Divider(),
                        ],

                        // 2) 上半部：KLine圖
                        Expanded(
                          flex: 1,
                          child: KLineChart(
                            stockData: _historyList,
                            onSignalData: handleSignalData,
                          ),
                        ),

                        // 3) 下半部：列出前端計算到的訊號 (若KLineChart有計算)
                        Expanded(
                          flex: 1,
                          child: signalDays.isEmpty
                              ? Center(child: Text('暫無任何TD/TS達9的訊號日'))
                              : ListView.builder(
                                  itemCount: signalDays.length,
                                  itemBuilder: (context, idx) {
                                    final sd = signalDays[idx];
                                    final signalStr = sd.isBullishSignal == true
                                        ? '閃電'
                                        : '鑽石';
                                    return ListTile(
                                      title: Text('${sd.date} - $signalStr'),
                                      subtitle: Text(
                                          'Open: ${sd.open}, Close: ${sd.close}'),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }
}
