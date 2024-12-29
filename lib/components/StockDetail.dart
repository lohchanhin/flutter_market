// ignore_for_file: depend_on_referenced_packages, unused_local_variable

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart'; // 用于格式化日期
import '../components/Char.dart'; // 确保路径正确

class StockDetail extends StatefulWidget {
  final String stockCode;
  final String stockName;

  const StockDetail(
      {Key? key, required this.stockCode, required this.stockName})
      : super(key: key);

  @override
  _StockDetailState createState() => _StockDetailState();
}

class _StockDetailState extends State<StockDetail> {
  late Future<List<StockData>> futureStockData;
  List<StockData> signalDays = []; // 保存含有信號的股票數據

  void handleSignalData(List<StockData> signals) {
    setState(() {
      signalDays = signals; // 更新含有信號的股票數據
    });
  }

  @override
  void initState() {
    super.initState();
    futureStockData = fetchStockHistory(widget.stockCode);
  }

  Future<List<StockData>> fetchStockHistory(String stockCode) async {
    String url = 'https://finance.yahoo.com/quote/$stockCode.TW/history/';
    var headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'
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
            StockData stockData = StockData(
                date: cells[0].text.trim(),
                open: double.parse(cells[1].text.trim()),
                high: double.parse(cells[2].text.trim()),
                low: double.parse(cells[3].text.trim()),
                close: double.parse(cells[4].text.trim()),
                adjClose: double.parse(cells[5].text.trim()),
                volume: int.parse(cells[6].text.trim().replaceAll(',', '')));
            stockDataList.add(stockData);
          } catch (e) {
            print('Error parsing data for row: ${row.innerHtml}');
          }
        }
      }
      return stockDataList.reversed.toList();
    } else {
      throw Exception('Failed to load stock history data');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stockName),
      ),
      body: FutureBuilder<List<StockData>>(
        future: futureStockData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (snapshot.hasData) {
              return Column(
                children: [
                  Expanded(
                      flex: 1,
                      child: KLineChart(
                          stockData: snapshot.data!,
                          onSignalData: handleSignalData)),
                  Expanded(
                    flex: 1,
                    child: ListView(
                      children: signalDays
                          .map((data) => ListTile(
                                title: Text(
                                    '${data.date} ${data.isBullishSignal! ? "閃電" : "鑽石"}'),
                                subtitle: Text(
                                    'Open: ${data.open}, Close: ${data.close}'),
                              ))
                          .toList(),
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

class StockDataWidget extends StatelessWidget {
  final StockData data;

  const StockDataWidget(this.data, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(data.date),
      subtitle: Text('Open: ${data.open}, Close: ${data.close}'),
    );
  }
}
