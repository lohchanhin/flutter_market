import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import '../database/DatabaseHelper.dart';
import '../components/SearchBar.dart';

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _stocks = [];
  List<dynamic> _filteredStocks = [];
  List<String> _addedStockCodes = []; // 已經加入 (可能包含 day/week？這裡只是看 code)
  List<String> _selectedStocks = [];
  String _filter = 'All';
  bool _isProcessing = false; // 用於控制是否顯示處理中提示框

  @override
  void initState() {
    super.initState();
    _loadStockData();
    _loadAddedStockCodes(); // 只會存放 'code'
  }

  // (1) 載入本地 JSON: stocks_data.json
  Future<void> _loadStockData() async {
    final String response =
        await rootBundle.loadString('assets/stocks_data.json');
    final data = await json.decode(response);
    setState(() {
      _stocks = data;
      _applyFilter();
    });
  }

  // (2) 從資料庫抓到已添加的股票代號 (不分 freq)
  Future<void> _loadAddedStockCodes() async {
    final addedStocks = await DatabaseHelper.instance.getStocks();
    // 注意：這裡可能會抓到日/週兩筆，但我們只記 code，後面用來判斷「是否已添加」
    final codes =
        addedStocks.map<String>((stock) => stock['code'] as String).toSet();
    setState(() {
      _addedStockCodes = codes.toList();
    });
  }

  // 搜尋處理
  void _handleSearch(String query) {
    List<dynamic> results = [];
    if (query.isEmpty) {
      results = _stocks;
    } else {
      results = _stocks.where((stock) {
        final String name = stock['名稱'].toLowerCase();
        final String code = stock['代號'].toLowerCase();
        return name.contains(query.toLowerCase()) ||
            code.contains(query.toLowerCase());
      }).toList();
    }
    setState(() {
      _filteredStocks = results;
      _applyFilter();
    });
  }

  // 篩選處理
  void _applyFilter() {
    List<dynamic> results;
    if (_filter == 'All') {
      results = _stocks;
    } else if (_filter == 'Added') {
      results = _stocks
          .where((stock) => _addedStockCodes.contains(stock['代號']))
          .toList();
    } else {
      // NotAdded
      results = _stocks
          .where((stock) => !_addedStockCodes.contains(stock['代號']))
          .toList();
    }
    setState(() {
      _filteredStocks = results;
    });
  }

  // 顯示 Snackbar
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 2)),
    );
  }

  // 切換選擇
  void _toggleSelection(String stockCode) {
    setState(() {
      if (_selectedStocks.contains(stockCode)) {
        _selectedStocks.remove(stockCode);
      } else {
        _selectedStocks.add(stockCode);
      }
    });
  }

  // ---------------------------
  // 核心：一次建立「Day + Week」兩筆
  // ---------------------------
  Future<void> _addStockDayWeek(String code, String name) async {
    // (1) 先查資料庫：有沒有同 (code, freq='Day') ?
    final dbStocks = await DatabaseHelper.instance.getStocks();
    final alreadyHasDay = dbStocks.any(
      (s) => s['code'] == code && s['freq'] == 'Day',
    );
    final alreadyHasWeek = dbStocks.any(
      (s) => s['code'] == code && s['freq'] == 'Week',
    );

    // (2) 若沒有，就插入
    if (!alreadyHasDay) {
      await DatabaseHelper.instance.addStock({
        'code': code,
        'name': name,
        'freq': 'Day', // 關鍵
      });
    }
    if (!alreadyHasWeek) {
      await DatabaseHelper.instance.addStock({
        'code': code,
        'name': name,
        'freq': 'Week', // 關鍵
      });
    }

    // (3) 重新載入 => 更新 _addedStockCodes
    await _loadAddedStockCodes();
  }

  // ---------------------------
  // 全部添加
  // ---------------------------
  Future<void> _addAllStocks() async {
    setState(() => _isProcessing = true);

    int addedCount = 0;
    for (var stock in _filteredStocks) {
      if (!_addedStockCodes.contains(stock['代號'])) {
        // 新增 (Day+Week)
        await _addStockDayWeek(stock['代號'], stock['名稱']);
        addedCount++;
      }
    }

    setState(() => _isProcessing = false);
    _showSnackbar(addedCount > 0 ? '成功添加 $addedCount 個股票(含日/週)' : '沒有可添加的股票');
  }

  // ---------------------------
  // 全部移除
  // ---------------------------
  Future<void> _removeAllStocks() async {
    setState(() => _isProcessing = true);

    int removedCount = 0;
    for (var stock in _filteredStocks) {
      final code = stock['代號'];
      // 直接把這個 code 全部刪掉 (包含日/週)
      if (_addedStockCodes.contains(code)) {
        await DatabaseHelper.instance.deleteStockByCode(code);
        removedCount++;
      }
    }

    // 刪完後重新載入
    await _loadAddedStockCodes();
    setState(() => _isProcessing = false);
    _showSnackbar(removedCount > 0 ? '成功移除 $removedCount 個股票' : '沒有可移除的股票');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text('股票搜尋'),
            actions: [
              IconButton(
                icon: Icon(Icons.add),
                onPressed: _addAllStocks,
                tooltip: '全部添加(含日/週)',
              ),
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: _removeAllStocks,
                tooltip: '全部移除(含日/週)',
              ),
              DropdownButton<String>(
                value: _filter,
                items: [
                  DropdownMenuItem(value: 'All', child: Text('顯示全部')),
                  DropdownMenuItem(value: 'Added', child: Text('已添加')),
                  DropdownMenuItem(value: 'NotAdded', child: Text('未添加')),
                ],
                onChanged: (value) {
                  setState(() {
                    _filter = value!;
                    _applyFilter();
                  });
                },
                underline: SizedBox(),
              ),
            ],
          ),
          body: Column(
            children: [
              // 搜尋框
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SearchBar2(
                  controller: _controller,
                  onSearch: _handleSearch,
                ),
              ),
              // 結果清單
              Expanded(
                child: _filteredStocks.isEmpty
                    ? Center(child: Text('沒有找到相關的股票'))
                    : ListView.builder(
                        itemCount: _filteredStocks.length,
                        itemBuilder: (context, index) {
                          final stock = _filteredStocks[index];
                          final code = stock['代號'];
                          final name = stock['名稱'];

                          final isSelected = _selectedStocks.contains(code);
                          final isAdded = _addedStockCodes.contains(code);

                          return ListTile(
                            title: Text(name),
                            subtitle: Text(code),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 單支加入(含日/週)
                                IconButton(
                                  icon: Icon(
                                    isAdded ? Icons.check : Icons.add,
                                    color: isAdded ? Colors.green : null,
                                  ),
                                  onPressed: isAdded
                                      ? null
                                      : () async {
                                          await _addStockDayWeek(code, name);
                                          _showSnackbar('已添加 $code (日/週)');
                                        },
                                ),
                                // 勾選選擇
                                IconButton(
                                  icon: Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                  ),
                                  onPressed: () => _toggleSelection(code),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          // 浮動按鈕：批量添加選定
          floatingActionButton: _selectedStocks.isNotEmpty
              ? FloatingActionButton(
                  onPressed: () async {
                    for (var code in _selectedStocks) {
                      final stock = _stocks.firstWhere((s) => s['代號'] == code);
                      await _addStockDayWeek(stock['代號'], stock['名稱']);
                    }
                    setState(() {
                      _selectedStocks.clear();
                    });
                    _showSnackbar('已批量添加選定的股票(含日/週)');
                  },
                  child: Icon(Icons.done),
                )
              : null,
        ),
        // 遮罩與進度指示器
        if (_isProcessing)
          ModalBarrier(
            dismissible: false,
            color: Colors.black54,
          ),
        if (_isProcessing)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '正在處理，請稍候...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
