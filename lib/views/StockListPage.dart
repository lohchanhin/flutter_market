import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import '../database/DatabaseHelper.dart';
import '../services/api_service.dart';
import '../components/StockDetail.dart';

class StockListPage extends StatefulWidget {
  @override
  _StockListPageState createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  // 本地 DB
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  // 後端 API
  final ApiService api = ApiService();

  List<Map<String, dynamic>> _stocks = []; // 本地 DB 所有股票
  List<Map<String, dynamic>> _filteredStocks = []; // 篩選後列表

  String _filterSignal = 'All'; // 篩選信號: All, TD(=闪电), TS(=钻石)
  String _filterFreq = 'All'; // 篩選週期: All, Day, Week

  bool _isUpdating = false; // 是否正在更新
  int _updateProgress = 0;
  int _totalStocks = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedStocks();
  }

  // 1) 從本地 SQLite 載入
  Future<void> _loadSavedStocks() async {
    try {
      final localStocks = await dbHelper.getStocks();
      setState(() {
        _stocks = localStocks;
      });
      _applyFilter();
    } catch (e) {
      print('Error loading local stocks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入本地股票失敗: $e')),
        );
      }
    }
  }

  // 2) 前端篩選
  void _applyFilter() {
    List<Map<String, dynamic>> temp = _stocks;
    if (_filterFreq != 'All') {
      temp = temp.where((s) => s['freq'] == _filterFreq).toList();
    }
    if (_filterSignal == 'TD') {
      temp = temp.where((stock) => stock['signal'] == '闪电').toList();
    } else if (_filterSignal == 'TS') {
      temp = temp.where((stock) => stock['signal'] == '钻石').toList();
    }
    setState(() {
      _filteredStocks = temp;
    });
  }

  // 3) 刪除本地資料
  Future<void> _removeStock(int localId) async {
    try {
      await dbHelper.deleteStock(localId);
      await _loadSavedStocks();
    } catch (e) {
      print('Error removing local stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗: $e')),
        );
      }
    }
  }

  // 4) 按下「全部更新」=> 後端批次 => 拿最新 => 同步到本地
  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _filteredStocks.length; // 可作假進度
    });

    try {
      // (A) 呼叫後端「更新全部」
      // await api.updateAllStocks();

      // (B) 從後端取得最新列表
      final remoteList = await api.getAllStocks();
      // remoteList: [ { id, code, name, freq, signal, tdCount, tsCount, lastUpdate }, ... ]

      // (C) 與本地對照 (code+freq)
      final updates = <Map<String, dynamic>>[];
      final localAll = await dbHelper.getStocks(); // 重新抓取全部
      final Map<String, int> mapCodeFreqToId = {};
      for (var loc in localAll) {
        final c = loc['code'];
        final f = loc['freq'];
        final lid = loc['id'];
        final key = '$c|$f';
        mapCodeFreqToId[key] = lid;
      }

      for (var remote in remoteList) {
        final code = remote['code'];
        final freq = remote['freq'];
        final key = '$code|$freq';
        if (mapCodeFreqToId.containsKey(key)) {
          final localId = mapCodeFreqToId[key];
          updates.add({
            'id': localId,
            'signal': remote['signal'],
            'lastUpdate': remote['lastUpdate'] ?? DateTime.now().toString(),
            'tdCount': remote['tdCount'] ?? 0,
            'tsCount': remote['tsCount'] ?? 0,
          });
        }
      }

      // (D) batchUpdateStocks
      if (updates.isNotEmpty) {
        await dbHelper.batchUpdateStocks(updates);
      }

      // (E) 重新載入 + 提示
      await _loadSavedStocks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有股票已更新')),
        );
      }
    } catch (e) {
      print('Error in _updateAllStocks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗: $e')),
        );
      }
    }

    setState(() {
      _isUpdating = false;
    });
  }

  // 幫助函式：格式化日期
  String _formatLastUpdate(String? lastUpdate) {
    if (lastUpdate == null) return '未更新';
    final dt = DateTime.parse(lastUpdate);
    return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
  }

  // 幫助函式：根據 signal 顯示 icon
  Widget _buildSignalIcon(String? signal) {
    if (signal == '闪电') {
      return Icon(Icons.flash_on, color: Colors.green);
    } else if (signal == '钻石') {
      return Icon(Icons.diamond, color: Colors.red);
    }
    return Icon(Icons.do_not_disturb, color: Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: _isUpdating,
          child: Scaffold(
            appBar: AppBar(
              title: Text('已保存的股票 (本地 DB)'),
              actions: [
                IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
                // freq下拉
                DropdownButton<String>(
                  value: _filterFreq,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部週期')),
                    DropdownMenuItem(value: 'Day', child: Text('日線')),
                    DropdownMenuItem(value: 'Week', child: Text('週線')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterFreq = val;
                        _applyFilter();
                      });
                    }
                  },
                  underline: SizedBox(),
                ),
                // signal下拉
                DropdownButton<String>(
                  value: _filterSignal,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部信號')),
                    DropdownMenuItem(value: 'TD', child: Text('TD 信號')),
                    DropdownMenuItem(value: 'TS', child: Text('TS 信號')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterSignal = val;
                        _applyFilter();
                      });
                    }
                  },
                  underline: SizedBox(),
                ),
                SizedBox(width: 8),
              ],
            ),
            body: _filteredStocks.isEmpty
                ? Center(child: Text('目前沒有股票或篩選條件無資料'))
                : ListView.builder(
                    itemCount: _filteredStocks.length,
                    itemBuilder: (context, idx) {
                      final stock = _filteredStocks[idx];
                      // stock = {id, code, name, freq, signal, tdCount, tsCount, lastUpdate}
                      return ListTile(
                        leading: _buildSignalIcon(stock['signal']),
                        title: Text('${stock['name']} (${stock['freq']})'),
                        subtitle: Text(
                          '${stock['code']} - '
                          'TD:${stock['tdCount'] ?? 0}, '
                          'TS:${stock['tsCount'] ?? 0}\n'
                          '${_formatLastUpdate(stock['lastUpdate'])}',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockDetail(
                                stockCode: stock['code'],
                                stockName: stock['name'],
                                freq: stock['freq'],
                              ),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 單支更新 => 直接呼叫API
                            IconButton(
                              icon: Icon(Icons.refresh),
                              onPressed: () =>
                                  api.updateSingleStock(stock['id']),
                            ),
                            // 刪除(本地)
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => _removeStock(stock['id']),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),

        // 遮罩 + 進度指示器
        if (_isUpdating)
          ModalBarrier(dismissible: false, color: Colors.black45),
        if (_isUpdating)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 假進度或不顯示實際進度也可
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
    );
  }
}
