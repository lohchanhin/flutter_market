// ignore_for_file: depend_on_referenced_packages, unused_local_variable

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse; // Yahoo 爬蟲需要
import 'package:intl/intl.dart'; // 格式化日期
import '../components/Char.dart'; // 你自己的K線圖widget
import 'dart:convert';

class StockDetail extends StatefulWidget {
  final String stockCode;
  final String stockName;
  final String freq; // 'Day' or 'Week'

  const StockDetail({
    Key? key,
    required this.stockCode,
    required this.stockName,
    required this.freq, // 新增 freq
  }) : super(key: key);

  @override
  _StockDetailState createState() => _StockDetailState();
}

class _StockDetailState extends State<StockDetail> {
  late Future<List<StockData>> futureStockData;
  List<StockData> signalDays = []; // 保存含有信號的數據

  // 用於接收 Chart widget 回傳的信號資料
  void handleSignalData(List<StockData> signals) {
    setState(() {
      signalDays = signals;
    });
  }

  @override
  void initState() {
    super.initState();
    // 根據 freq 決定要抓日線 or 週線
    if (widget.freq == 'Week') {
      futureStockData = fetchWeeklyFinMindHistory(widget.stockCode);
    } else {
      futureStockData = fetchDailyYahooHistory(widget.stockCode);
    }
  }

  // ---------------------------------------------------
  // A. 抓「日線」(Yahoo Finance) 爬蟲
  // ---------------------------------------------------
  Future<List<StockData>> fetchDailyYahooHistory(String stockCode) async {
    String url = 'https://finance.yahoo.com/quote/$stockCode.TW/history/';
    var headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'
    };
    var response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode == 200) {
      var document = parse(response.body);
      var rows = document.querySelectorAll('table tbody tr');
      List<StockData> stockDataList = [];
      DateFormat format = DateFormat('MMM dd, yyyy');
      for (var row in rows) {
        var cells = row.querySelectorAll('td');
        if (cells.length > 6) {
          try {
            DateTime date = format.parse(cells[0].text.trim());
            final openVal =
                double.tryParse(cells[1].text.trim().replaceAll(',', ''));
            final highVal =
                double.tryParse(cells[2].text.trim().replaceAll(',', ''));
            final lowVal =
                double.tryParse(cells[3].text.trim().replaceAll(',', ''));
            final closeVal =
                double.tryParse(cells[4].text.trim().replaceAll(',', ''));
            final adjVal =
                double.tryParse(cells[5].text.trim().replaceAll(',', ''));
            final volVal =
                int.tryParse(cells[6].text.trim().replaceAll(',', ''));
            // 如果有任何欄位是 null，就跳過
            if (openVal == null ||
                highVal == null ||
                lowVal == null ||
                closeVal == null ||
                adjVal == null ||
                volVal == null) {
              continue;
            }
            StockData stockData = StockData(
              date: cells[0].text.trim(),
              open: openVal,
              high: highVal,
              low: lowVal,
              close: closeVal,
              adjClose: adjVal,
              volume: volVal,
            );
            stockDataList.add(stockData);
          } catch (e) {
            print('Error parsing data for row: ${row.innerHtml}, $e');
          }
        }
      }
      // Yahoo 回傳順序是由最近到最舊，所以 reversed() 變成「舊 -> 新」
      return stockDataList.reversed.toList();
    } else {
      throw Exception('Failed to load daily data from Yahoo');
    }
  }

  // ---------------------------------------------------
  // B. 抓「週線」(FinMind API)
  // ---------------------------------------------------
  Future<List<StockData>> fetchWeeklyFinMindHistory(String stockCode) async {
    final now = DateTime.now();
    final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
    final startDate = DateFormat('yyyy-MM-dd').format(oneYearAgo);

    const token =
        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkYXRlIjoiMjAyNS0wMS0xMCAwMTo0ODoyNyIsInVzZXJfaWQiOiJsb2hjaGFuaGluIiwiaXAiOiIxLjE2MC4xNjkuMTAwIn0.PWmTcSC8DeZsspyTOZf6qMXO6GjlhGNG655IBxByfWs'; // 改成你的 token
    final url = Uri.parse(
      'https://api.finmindtrade.com/api/v4/data?'
      'dataset=TaiwanStockWeekPrice&'
      'data_id=$stockCode&'
      'start_date=$startDate&'
      'token=$token',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final jsonObj = jsonDecode(response.body);
      if (jsonObj['status'] == 200) {
        final dataList = jsonObj['data'] as List;
        List<StockData> stockDataList = [];

        for (var item in dataList) {
          final date = item['date'];
          final open = item['open'];
          final high = item['max'];
          final low = item['min'];
          final close = item['close'];
          final volume = item['trading_volume']; // 週線是小寫

          if (date == null ||
              open == null ||
              high == null ||
              low == null ||
              close == null ||
              volume == null) {
            // 任何欄位是 null 就跳過
            continue;
          }
          stockDataList.add(
            StockData(
              date: date.toString(),
              open: (open as num).toDouble(),
              high: (high as num).toDouble(),
              low: (low as num).toDouble(),
              close: (close as num).toDouble(),
              adjClose:
                  (close as num).toDouble(), // FinMind 沒有給 adjClose，用 close
              volume: (volume as num).toInt(),
            ),
          );
        }
        // FinMind 回傳通常是「舊 -> 新」
        // 如果你的 chart 需要「舊 -> 新」就直接用，不用 reversed()
        return stockDataList;
      } else {
        throw Exception('FinMind: ${jsonObj['info']}');
      }
    } else {
      throw Exception('FinMind HTTP error: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stockName} (${widget.freq})'),
      ),
      body: FutureBuilder<List<StockData>>(
        future: futureStockData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (snapshot.hasData) {
              // 有資料就顯示K線 + 信號列表
              return Column(
                children: [
                  // 上半: 圖表
                  Expanded(
                    flex: 1,
                    child: KLineChart(
                      stockData: snapshot.data!,
                      onSignalData: handleSignalData,
                    ),
                  ),
                  // 下半: 信號清單
                  Expanded(
                    flex: 1,
                    child: ListView(
                      children: signalDays.map((data) {
                        final signalText = data.isBullishSignal == true
                            ? '閃電'
                            : '鑽石'; // 你可以自行判斷
                        return ListTile(
                          title: Text('${data.date} $signalText'),
                          subtitle:
                              Text('Open: ${data.open}, Close: ${data.close}'),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            } else {
              return Text('No data found');
            }
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

// 你的 StockData 類 (可複用)
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
