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

  // 從 assets/stocks_data.json 載入的股票清單 (只含 { "代號", "名稱" })
  List<dynamic> _stocks = [];

  // 經過搜尋 / 篩選後顯示
  List<dynamic> _filteredStocks = [];

  // watchlist 表中已添加的 code 列表 (用於判斷「已添加 / 未添加」)
  List<String> _addedStockCodes = [];

  // 用於多選添加
  List<String> _selectedStocks = [];

  // 篩選條件: 'All' / 'Added' / 'NotAdded'
  String _filter = 'All';

  bool _isProcessing = false; // 用於顯示「處理中」遮罩

  @override
  void initState() {
    super.initState();
    _loadStockData(); // 載入 JSON
    _loadWatchlist(); // 載入 watchlist (code)
  }

  // 1) 載入 JSON
  Future<void> _loadStockData() async {
    try {
      final response = await rootBundle.loadString('assets/stocks_data.json');
      if (!mounted) return;
      final data = json.decode(response);

      setState(() {
        _stocks = data;
        _filteredStocks = _stocks;
      });
      _applyFilter();
    } catch (e) {
      print('Error in _loadStockData: $e');
    }
  }

  // 2) 載入 watchlist (使用者已添加的 code)
  Future<void> _loadWatchlist() async {
    try {
      final watchData = await DatabaseHelper.instance.getWatchlist();
      if (!mounted) return;

      // watchData => [ { id, code, name }, ... ]
      final codes = watchData.map<String>((m) => m['code'] as String).toSet();
      setState(() {
        _addedStockCodes = codes.toList();
      });
      _applyFilter();
    } catch (e) {
      print('Error in _loadWatchlist: $e');
    }
  }

  // 搜尋
  void _handleSearch(String query) {
    if (query.isEmpty) {
      setState(() => _filteredStocks = _stocks);
      _applyFilter();
      return;
    }
    final results = _stocks.where((s) {
      final name = (s['名稱'] ?? '').toLowerCase();
      final code = (s['代號'] ?? '').toLowerCase();
      return name.contains(query.toLowerCase()) ||
          code.contains(query.toLowerCase());
    }).toList();

    setState(() {
      _filteredStocks = results;
      _applyFilter();
    });
  }

  // 篩選: 'All' / 'Added' / 'NotAdded'
  void _applyFilter() {
    List<dynamic> results;
    if (_filter == 'All') {
      results = _filteredStocks;
    } else if (_filter == 'Added') {
      results = _filteredStocks
          .where((s) => _addedStockCodes.contains(s['代號']))
          .toList();
    } else {
      // NotAdded
      results = _filteredStocks
          .where((s) => !_addedStockCodes.contains(s['代號']))
          .toList();
    }
    setState(() {
      _filteredStocks = results;
    });
  }

  // 顯示訊息
  void _showSnackbar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: Duration(seconds: 2)),
      );
    }
  }

  // 多選切換
  void _toggleSelection(String code) {
    setState(() {
      if (_selectedStocks.contains(code)) {
        _selectedStocks.remove(code);
      } else {
        _selectedStocks.add(code);
      }
    });
  }

  // === 單支添加 => watchlist + stocks(Day/Week) ===
  Future<void> _addSingle(String code, String name) async {
    try {
      if (_addedStockCodes.contains(code)) return; // 已添加 => 不重複

      // 1) 加到 watchlist
      await DatabaseHelper.instance.addToWatchlist(code, name);

      // 2) 在 stocks 表中，檢查 (code, freq=Day/Week) 是否已存在，若無則新增
      final localStocks = await DatabaseHelper.instance.getStocks();
      final hasDay =
          localStocks.any((row) => row['code'] == code && row['freq'] == 'Day');
      final hasWeek = localStocks
          .any((row) => row['code'] == code && row['freq'] == 'Week');

      if (!hasDay) {
        await DatabaseHelper.instance.addStock({
          'code': code,
          'name': name,
          'freq': 'Day',
          'signal': null,
          'tdCount': 0,
          'tsCount': 0,
          'lastUpdate': null,
        });
      }
      if (!hasWeek) {
        await DatabaseHelper.instance.addStock({
          'code': code,
          'name': name,
          'freq': 'Week',
          'signal': null,
          'tdCount': 0,
          'tsCount': 0,
          'lastUpdate': null,
        });
      }

      // 3) 重新載入 watchlist => 更新UI
      await _loadWatchlist();
      _showSnackbar('已添加 $code (Day/Week)');
    } catch (e) {
      print('Error in _addSingle: $e');
    }
  }

  // === 全部添加 => 一次對 _filteredStocks 中未添加的做同樣流程 ===
  Future<void> _addAllStocks() async {
    setState(() => _isProcessing = true);
    try {
      int addedCount = 0;
      for (var s in _filteredStocks) {
        final code = s['代號'];
        final name = s['名稱'] ?? '';

        if (!_addedStockCodes.contains(code)) {
          // watchlist
          await DatabaseHelper.instance.addToWatchlist(code, name);

          // stocks => day/week
          final localStocks = await DatabaseHelper.instance.getStocks();
          final hasDay =
              localStocks.any((r) => r['code'] == code && r['freq'] == 'Day');
          final hasWeek =
              localStocks.any((r) => r['code'] == code && r['freq'] == 'Week');

          if (!hasDay) {
            await DatabaseHelper.instance.addStock({
              'code': code,
              'name': name,
              'freq': 'Day',
              'signal': null,
              'tdCount': 0,
              'tsCount': 0,
              'lastUpdate': null,
            });
          }
          if (!hasWeek) {
            await DatabaseHelper.instance.addStock({
              'code': code,
              'name': name,
              'freq': 'Week',
              'signal': null,
              'tdCount': 0,
              'tsCount': 0,
              'lastUpdate': null,
            });
          }

          addedCount++;
        }
      }
      // 重讀 watchlist => UI
      await _loadWatchlist();

      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar(
          addedCount > 0 ? '成功添加 $addedCount 個股票 (Day/Week)' : '沒有可添加的股票');
    } catch (e) {
      print('Error in _addAllStocks: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  // === 全部移除 (在 watchlist) => 不一定要刪 stocks => 看需求
  Future<void> _removeAllStocks() async {
    setState(() => _isProcessing = true);
    try {
      int removedCount = 0;
      for (var s in _filteredStocks) {
        final code = s['代號'];
        if (_addedStockCodes.contains(code)) {
          // 移除 watchlist
          await DatabaseHelper.instance.deleteWatchlistByCode(code);
          removedCount++;

          // (可選) 若你也想刪 stocks, freq=Day/Week => un-comment:
          // await DatabaseHelper.instance.deleteStockByCode(code);
        }
      }
      await _loadWatchlist();

      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar(removedCount > 0 ? '成功移除 $removedCount 個股票' : '沒有可移除的股票');
    } catch (e) {
      print('Error in _removeAllStocks: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  // === 單支移除 (如果你需要)
  Future<void> _removeSingle(String code) async {
    setState(() => _isProcessing = true);
    try {
      // watchlist
      await DatabaseHelper.instance.deleteWatchlistByCode(code);

      // (可選) 若也想刪 stocks
      // await DatabaseHelper.instance.deleteStockByCode(code);

      await _loadWatchlist();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar('已移除 $code');
    } catch (e) {
      print('Error in _removeSingle: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  // === 批量添加「選定」 ===
  Future<void> _addSelected() async {
    setState(() => _isProcessing = true);
    try {
      int addedCount = 0;
      for (var code in _selectedStocks) {
        if (!_addedStockCodes.contains(code)) {
          final item = _stocks.firstWhere((m) => m['代號'] == code);
          final name = item['名稱'] ?? '';

          // 加到 watchlist
          await DatabaseHelper.instance.addToWatchlist(code, name);

          // 加到 stocks => day/week
          final localStocks = await DatabaseHelper.instance.getStocks();
          final hasDay =
              localStocks.any((r) => r['code'] == code && r['freq'] == 'Day');
          final hasWeek =
              localStocks.any((r) => r['code'] == code && r['freq'] == 'Week');
          if (!hasDay) {
            await DatabaseHelper.instance.addStock({
              'code': code,
              'name': name,
              'freq': 'Day',
              'signal': null,
              'tdCount': 0,
              'tsCount': 0,
              'lastUpdate': null,
            });
          }
          if (!hasWeek) {
            await DatabaseHelper.instance.addStock({
              'code': code,
              'name': name,
              'freq': 'Week',
              'signal': null,
              'tdCount': 0,
              'tsCount': 0,
              'lastUpdate': null,
            });
          }

          addedCount++;
        }
      }
      _selectedStocks.clear();
      await _loadWatchlist();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackbar('已批量添加選定的股票 ($addedCount)');
    } catch (e) {
      print('Error in _addSelected: $e');
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
            title: Text('股票搜尋 (WatchList)'),
            actions: [
              IconButton(
                icon: Icon(Icons.add),
                onPressed: _addAllStocks,
                tooltip: '全部添加',
              ),
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: _removeAllStocks,
                tooltip: '全部移除',
              ),
              DropdownButton<String>(
                value: _filter,
                items: [
                  DropdownMenuItem(value: 'All', child: Text('顯示全部')),
                  DropdownMenuItem(value: 'Added', child: Text('已添加')),
                  DropdownMenuItem(value: 'NotAdded', child: Text('未添加')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _filter = val;
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
                padding: EdgeInsets.all(8.0),
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
                        itemBuilder: (_, index) {
                          final s = _filteredStocks[index];
                          final code = s['代號'];
                          final name = s['名稱'] ?? '';
                          final isSelected = _selectedStocks.contains(code);
                          final isAdded = _addedStockCodes.contains(code);

                          return ListTile(
                            title: Text(name),
                            subtitle: Text(code),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 已添加 => check, 未添加 => add
                                IconButton(
                                  icon: Icon(
                                    isAdded ? Icons.check : Icons.add,
                                    color: isAdded ? Colors.green : null,
                                  ),
                                  onPressed: isAdded
                                      ? null
                                      : () => _addSingle(code, name),
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
                            onLongPress: () async {
                              // 範例: 長按移除單個 => watchlist
                              // (可自己改 UI)
                              if (isAdded) {
                                // 單個移除
                                setState(() => _isProcessing = true);
                                await DatabaseHelper.instance
                                    .deleteWatchlistByCode(code);
                                // (可選) 一併刪 stocks =>
                                // await DatabaseHelper.instance.deleteStockByCode(code);
                                await _loadWatchlist();
                                setState(() => _isProcessing = false);
                                _showSnackbar('已移除 $code');
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: _selectedStocks.isNotEmpty
              ? FloatingActionButton(
                  onPressed: _addSelected,
                  child: Icon(Icons.done),
                )
              : null,
        ),

        // 遮罩
        if (_isProcessing)
          ModalBarrier(dismissible: false, color: Colors.black54),
        if (_isProcessing)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在處理，請稍候...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
      ],
    );
  }
}
