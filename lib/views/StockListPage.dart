import 'package:flutter/material.dart';
import '../database/DatabaseHelper.dart';
import '../components/StockDetail.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';

class StockListPage extends StatefulWidget {
  @override
  _StockListPageState createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  List<Map<String, dynamic>> _stocks = [];
  List<Map<String, dynamic>> _filteredStocks = [];
  String _filter = 'All'; // 篩選條件: All, TD, TS
  bool _isUpdating = false; // 是否正在更新
  int _updateProgress = 0; // 更新进度
  int _totalStocks = 0; // 总的股票数量

  @override
  void initState() {
    super.initState();
    _loadSavedStocks();
  }

  Future<void> _loadSavedStocks() async {
    final stocks = await DatabaseHelper.instance.getStocks();
    setState(() {
      _stocks = stocks;
      _applyFilter(); // 應用篩選條件
    });
  }

  void _applyFilter() {
    setState(() {
      if (_filter == 'All') {
        _filteredStocks = _stocks;
      } else if (_filter == 'TD') {
        _filteredStocks =
            _stocks.where((stock) => stock['signal'] == '闪电').toList();
      } else if (_filter == 'TS') {
        _filteredStocks =
            _stocks.where((stock) => stock['signal'] == '钻石').toList();
      }
    });
  }

  void _removeStock(int id) async {
    await DatabaseHelper.instance.deleteStock(id);
    _loadSavedStocks();
  }

  String _formatLastUpdate(String? lastUpdate) {
    if (lastUpdate == null) {
      return '未更新';
    } else {
      DateTime dateTime = DateTime.parse(lastUpdate);
      String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
      return '最后更新：$formattedDate';
    }
  }

  Widget _buildSignalIcon(String? signal) {
    if (signal == '闪电') {
      return Icon(Icons.flash_on, color: Colors.green);
    } else if (signal == '钻石') {
      return Icon(Icons.diamond, color: Colors.red);
    } else {
      return Icon(Icons.do_not_disturb, color: Colors.grey);
    }
  }

  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _stocks.length;
    });

    List<Future<void>> futures = [];
    for (var stock in _stocks) {
      futures.add(_updateSingleStock(stock));
    }

    await Future.wait(futures);

    await _loadSavedStocks();

    setState(() {
      _isUpdating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('所有股票已更新')),
    );
  }

  Future<void> _updateSingleStock(Map<String, dynamic> stock) async {
    int id = stock['id'];
    String code = stock['code'];

    var result = await _fetchAndCalculateSignal(code);
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

  Future<Map<String, dynamic>> _fetchAndCalculateSignal(
      String stockCode) async {
    try {
      List<StockData> stockData = await fetchStockHistory(stockCode);
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
            // ignore: unused_local_variable
            DateTime date = format.parse(cells[0].text.trim());
            StockData stockData = StockData(
                date: cells[0].text.trim(),
                open: double.parse(cells[1].text.trim().replaceAll(',', '')),
                high: double.parse(cells[2].text.trim().replaceAll(',', '')),
                low: double.parse(cells[3].text.trim().replaceAll(',', '')),
                close: double.parse(cells[4].text.trim().replaceAll(',', '')),
                adjClose:
                    double.parse(cells[5].text.trim().replaceAll(',', '')),
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

  void _calculateTDTSCounts(
      List<StockData> data, List<int> tdCounts, List<int> tsCounts) {
    for (int i = 4; i < data.length; i++) {
      if (data[i].close > data[i - 4].close) {
        // TD 条件满足
        if (tsCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          // 从 TS 切换到 TD，或初始状态，TD 计数从 1 开始
          tdCounts[i] = 1;
        } else {
          // 继续 TD 趋势，计数 +1
          tdCounts[i] = (tdCounts[i - 1] >= 9) ? 1 : tdCounts[i - 1] + 1;
        }
        tsCounts[i] = 0; // 重置 TS 计数器
      } else {
        // TS 条件满足或等于
        if (tdCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          // 从 TD 切换到 TS，或初始状态，TS 计数从 1 开始
          tsCounts[i] = 1;
        } else {
          // 继续 TS 趋势，计数 +1
          tsCounts[i] = (tsCounts[i - 1] >= 9) ? 1 : tsCounts[i - 1] + 1;
        }
        tdCounts[i] = 0; // 重置 TD 计数器
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('已保存的股票'),
        actions: [
          _isUpdating
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                )
              : IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
          // 篩選下拉選單
          DropdownButton<String>(
            value: _filter,
            items: [
              DropdownMenuItem(value: 'All', child: Text('顯示全部')),
              DropdownMenuItem(value: 'TD', child: Text('TD 信號')),
              DropdownMenuItem(value: 'TS', child: Text('TS 信號')),
            ],
            onChanged: (value) {
              setState(() {
                _filter = value!;
                _applyFilter();
              });
            },
            underline: SizedBox(), // 移除下劃線
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isUpdating)
            LinearProgressIndicator(
              value: _totalStocks > 0 ? _updateProgress / _totalStocks : null,
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredStocks.length,
              itemBuilder: (context, index) {
                final stock = _filteredStocks[index];
                return ListTile(
                  leading: _buildSignalIcon(stock['signal']),
                  title: Text(stock['name']),
                  subtitle: Text(
                    '${stock['code']} - TD: ${stock['tdCount'] ?? 0}, TS: ${stock['tsCount'] ?? 0} - ${_formatLastUpdate(stock['lastUpdate'])}',
                  ),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => StockDetail(
                        stockCode: stock['code'],
                        stockName: stock['name'],
                      ),
                    ));
                  },
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _removeStock(stock['id']),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 定义 StockData 类
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
