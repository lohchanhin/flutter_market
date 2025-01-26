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
  List<String> _addedStockCodes = []; // 已經加入 (只看 code)
  List<String> _selectedStocks = [];
  String _filter = 'All';
  bool _isProcessing = false; // 用於控制是否顯示處理中提示框

  @override
  void initState() {
    super.initState();
    _loadStockData();
    _loadAddedStockCodes();
  }

  // (1) 載入本地 JSON: stocks_data.json
  Future<void> _loadStockData() async {
    try {
      final String response =
          await rootBundle.loadString('assets/stocks_data.json');
      // 假如 user 很快離開此頁，這時 widget 可能已 dispose
      if (!mounted) return;
      final data = json.decode(response);
      setState(() {
        _stocks = data;
      });
      _applyFilter(); // 有需要也可直接 setState 內部呼叫
    } catch (e) {
      // 可做錯誤處理
      print('Error in _loadStockData: $e');
    }
  }

  // (2) 從資料庫抓已添加的股票代號
  Future<void> _loadAddedStockCodes() async {
    try {
      final addedStocks = await DatabaseHelper.instance.getStocks();
      if (!mounted) return;
      final codes = addedStocks.map<String>((s) => s['code'] as String).toSet();
      setState(() {
        _addedStockCodes = codes.toList();
      });
    } catch (e) {
      print('Error in _loadAddedStockCodes: $e');
    }
  }

  // 搜尋處理
  void _handleSearch(String query) {
    if (query.isEmpty) {
      setState(() => _filteredStocks = _stocks);
      _applyFilter();
      return;
    }
    List<dynamic> results = _stocks.where((stock) {
      final String name = stock['名稱'].toLowerCase();
      final String code = stock['代號'].toLowerCase();
      return name.contains(query.toLowerCase()) ||
          code.contains(query.toLowerCase());
    }).toList();
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
      results =
          _stocks.where((s) => _addedStockCodes.contains(s['代號'])).toList();
    } else {
      // 'NotAdded'
      results =
          _stocks.where((s) => !_addedStockCodes.contains(s['代號'])).toList();
    }
    setState(() {
      _filteredStocks = results;
    });
  }

  // 顯示 Snackbar
  void _showSnackbar(String message) {
    // 若要保險，也可先檢查 mounted
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 2)),
      );
    }
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

  // 一次建立「Day + Week」
  Future<void> _addStockDayWeek(String code, String name) async {
    try {
      final dbStocks = await DatabaseHelper.instance.getStocks();
      if (!mounted) return;

      final alreadyHasDay =
          dbStocks.any((s) => s['code'] == code && s['freq'] == 'Day');
      final alreadyHasWeek =
          dbStocks.any((s) => s['code'] == code && s['freq'] == 'Week');

      if (!alreadyHasDay) {
        await DatabaseHelper.instance.addStock({
          'code': code,
          'name': name,
          'freq': 'Day',
        });
      }
      if (!alreadyHasWeek) {
        await DatabaseHelper.instance.addStock({
          'code': code,
          'name': name,
          'freq': 'Week',
        });
      }
      // 重新載入
      await _loadAddedStockCodes();
    } catch (e) {
      print('Error in _addStockDayWeek: $e');
    }
  }

  // 全部添加
  Future<void> _addAllStocks() async {
    setState(() => _isProcessing = true);
    try {
      int addedCount = 0;
      for (var stock in _filteredStocks) {
        final code = stock['代號'];
        if (!_addedStockCodes.contains(code)) {
          // 新增 (Day+Week)
          await _addStockDayWeek(code, stock['名稱']);
          addedCount++;
        }
      }
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar(addedCount > 0 ? '成功添加 $addedCount 個股票(含日/週)' : '沒有可添加的股票');
    } catch (e) {
      print('Error in _addAllStocks: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  // 全部移除
  Future<void> _removeAllStocks() async {
    setState(() => _isProcessing = true);
    try {
      int removedCount = 0;
      for (var stock in _filteredStocks) {
        final code = stock['代號'];
        if (_addedStockCodes.contains(code)) {
          await DatabaseHelper.instance.deleteStockByCode(code);
          removedCount++;
        }
      }
      // 刪完後重新載入
      await _loadAddedStockCodes();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar(removedCount > 0 ? '成功移除 $removedCount 個股票' : '沒有可移除的股票');
    } catch (e) {
      print('Error in _removeAllStocks: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                  if (value != null) {
                    setState(() {
                      _filter = value;
                      _applyFilter();
                    });
                  }
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
                                // 多選
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
          floatingActionButton: _selectedStocks.isNotEmpty
              ? FloatingActionButton(
                  onPressed: () async {
                    // 批量添加選定
                    for (var code in _selectedStocks) {
                      final stock = _stocks.firstWhere((s) => s['代號'] == code);
                      await _addStockDayWeek(stock['代號'], stock['名稱']);
                    }
                    if (!mounted) return;
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
