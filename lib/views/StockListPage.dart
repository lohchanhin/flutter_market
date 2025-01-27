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
  final dbHelper = DatabaseHelper.instance;
  final api = ApiService();

  List<Map<String, dynamic>> _stocks = []; // 來自本地 DB (僅顯示那些 watchlist 也有的)
  List<Map<String, dynamic>> _filteredStocks = [];

  Set<String> _watchlistCodes = {}; // 當前 watchlist 內的 code
  bool _isUpdating = false;
  int _updateProgress = 0;
  int _totalStocks = 0;

  String _filterFreq = 'All'; // 篩 freq: All / Day / Week
  String _filterSignal = 'All'; // 篩 signal: All / TD(=闪电) / TS(=钻石)

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // 一次讀 watchlist + stocks
  Future<void> _loadAllData() async {
    try {
      // 1) 讀 watchlist => 拿 codes
      final watchData = await dbHelper.getWatchlist();
      final codes = watchData.map<String>((m) => m['code'] as String).toSet();

      // 2) 讀 stocks => 只留 code 在 watchlist 的
      final allStocks = await dbHelper.getStocks();
      // => [ {id, code, name, freq, signal, tdCount, tsCount, lastUpdate}, ...]

      // 過濾: 只顯示 code 在 watchlist 內
      final filtered =
          allStocks.where((s) => codes.contains(s['code'])).toList();

      setState(() {
        _watchlistCodes = codes;
        _stocks = filtered;
      });
      _applyFilter();
    } catch (e) {
      print('Error in _loadAllData: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入資料失敗: $e')),
        );
      }
    }
  }

  // 篩選
  void _applyFilter() {
    List<Map<String, dynamic>> temp = _stocks;

    // freq
    if (_filterFreq != 'All') {
      temp = temp.where((s) => s['freq'] == _filterFreq).toList();
    }

    // signal
    if (_filterSignal == 'TD') {
      temp = temp.where((s) => s['signal'] == '闪电').toList();
    } else if (_filterSignal == 'TS') {
      temp = temp.where((s) => s['signal'] == '钻石').toList();
    }

    setState(() {
      _filteredStocks = temp;
    });
  }

  // 刪除(本地 stocks)
  Future<void> _removeStock(int localId) async {
    try {
      await dbHelper.deleteStock(localId);
      // 再次讀 watchlist & stocks => 只留 watchlist codes
      await _loadAllData();
    } catch (e) {
      print('Error removing stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗: $e')),
        );
      }
    }
  }

  // 按「更新全部」 => 後端 => getAll => 同步 => 只顯示 watchlist
  Future<void> _updateAllStocks() async {
    setState(() {
      _isUpdating = true;
      _updateProgress = 0;
      _totalStocks = _filteredStocks.length;
    });

    try {
      // A) 後端
      // await api.updateAllStocks(); // FinMind抓 & 後端DB更新
      // B) 拿最新
      final remoteList = await api.getAllStocks();
      // => [ {id, code, freq, signal, tdCount, ...}, ...]

      // C) 與本地 stocks => batchUpdate
      final localAll = await dbHelper.getStocks(); // 先拿所有 stocks
      final Map<String, int> codeFreqToLocalId = {};
      for (var loc in localAll) {
        final key = '${loc['code']}|${loc['freq']}';
        codeFreqToLocalId[key] = loc['id'];
      }

      final updates = <Map<String, dynamic>>[];
      for (var remote in remoteList) {
        final code = remote['code'];
        final freq = remote['freq'];
        final key = '$code|$freq';
        if (codeFreqToLocalId.containsKey(key)) {
          final localId = codeFreqToLocalId[key];
          updates.add({
            'id': localId,
            'signal': remote['signal'],
            'lastUpdate': remote['lastUpdate'] ?? DateTime.now().toString(),
            'tdCount': remote['tdCount'] ?? 0,
            'tsCount': remote['tsCount'] ?? 0,
          });
        }
      }

      if (updates.isNotEmpty) {
        await dbHelper.batchUpdateStocks(updates);
      }

      // D) 重新讀 watchlist + stocks
      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有股票已更新')),
        );
      }
    } catch (e) {
      print('Error updateAllStocks: $e');
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

  String _formatLastUpdate(String? lastUpdate) {
    if (lastUpdate == null) return '未更新';
    final dt = DateTime.parse(lastUpdate);
    return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
  }

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
              title: Text('Stocks (只顯示watchlist)'),
              actions: [
                IconButton(
                  icon: Icon(Icons.update),
                  onPressed: _isUpdating ? null : _updateAllStocks,
                ),
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
                DropdownButton<String>(
                  value: _filterSignal,
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('全部信號')),
                    DropdownMenuItem(value: 'TD', child: Text('TD')),
                    DropdownMenuItem(value: 'TS', child: Text('TS')),
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
                ? Center(child: Text('沒有在 watchlist 中的股票，或篩選無資料'))
                : ListView.builder(
                    itemCount: _filteredStocks.length,
                    itemBuilder: (ctx, i) {
                      final s = _filteredStocks[i];
                      return ListTile(
                        leading: _buildSignalIcon(s['signal']),
                        title: Text('${s['name']} (${s['freq']})'),
                        subtitle: Text(
                          '${s['code']} / '
                          'TD:${s['tdCount'] ?? 0}, TS:${s['tsCount'] ?? 0}\n'
                          '${_formatLastUpdate(s['lastUpdate'])}',
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete),
                          onPressed: () => _removeStock(s['id']),
                        ),
                        onTap: () {
                          // 若要看詳細
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockDetail(
                                stockCode: s['code'],
                                stockName: s['name'],
                                freq: s['freq'],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
        if (_isUpdating)
          ModalBarrier(dismissible: false, color: Colors.black45),
        if (_isUpdating)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
