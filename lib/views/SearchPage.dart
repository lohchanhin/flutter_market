// views/SearchPage.dart
// 2025‑04 版：批量添加效能優化 + 進度視覺化 + ConflictAlgorithm / 型別修正

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm; // ★ NEW

import '../database/DatabaseHelper.dart';
import '../components/SearchBar.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final db = DatabaseHelper.instance;

  // assets/stocks_data.json → [{代號, 名稱}, ...]
  late List<Map<String, dynamic>> _stocks;
  List<Map<String, dynamic>> _view = [];

  Set<String> _added = {};
  Set<String> _multiPick = {};
  String _filter = 'All';

  bool _busy = false;
  double? _pct = 0; // null = indeterminate

  // ───────────────────────── init
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadStockJson();
    await _refreshWatchlist();
  }

  Future<void> _loadStockJson() async {
    final txt = await rootBundle.loadString('assets/stocks_data.json');
    _stocks = (json.decode(txt) as List).cast<Map<String, dynamic>>();
    _applyFilterAndSearch();
  }

  Future<void> _refreshWatchlist() async {
    final rows = await db.getWatchlist();
    _added = rows.map((e) => e['code'] as String).toSet();
    _applyFilterAndSearch(_controller.text);
  }

  // ───────────────────────── 搜尋 + 篩選
  void _applyFilterAndSearch([String q = '']) {
    var show = _stocks;

    if (q.isNotEmpty) {
      final lq = q.toLowerCase();
      show = show
          .where((s) =>
              (s['名稱'] as String).toLowerCase().contains(lq) ||
              (s['代號'] as String).toLowerCase().contains(lq))
          .toList();
    }

    switch (_filter) {
      case 'Added':
        show = show.where((s) => _added.contains(s['代號'])).toList();
        break;
      case 'NotAdded':
        show = show.where((s) => !_added.contains(s['代號'])).toList();
        break;
    }

    setState(() => _view = show);
  }

  // ───────────────────────── 單支添加
  Future<void> _addSingle(String code, String name) async {
    if (_added.contains(code)) return;
    setState(() => _busy = true);
    try {
      await _insertWatchAndStocks({code: name});
      await _refreshWatchlist();
      _toast('已添加 $code');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── 一鍵添加
  Future<void> _addAllVisible() async {
    final Map<String, String> toAdd = {
      for (var s in _view)
        if (!_added.contains(s['代號']))
          s['代號'] as String: (s['名稱'] as String? ?? '') // ★ FIX
    };
    if (toAdd.isEmpty) {
      _toast('沒有可添加的股票');
      return;
    }

    setState(() {
      _busy = true;
      _pct = 0;
    });

    try {
      await _insertWatchAndStocks(toAdd, progress: (d, t) {
        setState(() => _pct = d / t);
      });
      await _refreshWatchlist();
      _toast('成功添加 ${toAdd.length} 檔 (Day/Week)');
    } catch (e) {
      _toast('添加失敗: $e');
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _pct = 0;
        });
    }
  }

  // ───────────────────────── 批量 DB 插入
  Future<void> _insertWatchAndStocks(
    Map<String, String> map, {
    void Function(int done, int total)? progress,
  }) async {
    final total = map.length;
    int done = 0;

    final database = await db.database;
    await database.transaction((txn) async {
      for (final e in map.entries) {
        await txn.insert('watchlist', {'code': e.key, 'name': e.value},
            conflictAlgorithm: ConflictAlgorithm.ignore);

        for (final f in ['Day', 'Week']) {
          await txn.insert(
            'stocks',
            {
              'code': e.key,
              'name': e.value,
              'freq': f,
              'signal': null,
              'tdCount': 0,
              'tsCount': 0,
              'lastUpdate': null,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        done++;
        progress?.call(done, total);
      }
    });
  }

  // ───────────────────────── Toast
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ───────────────────────── UI
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('股票搜尋 (Watchlist)'),
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: '一鍵添加可見股票',
                onPressed: _addAllVisible,
              ),
              PopupMenuButton<String>(
                tooltip: '顯示篩選',
                onSelected: (v) {
                  setState(() => _filter = v);
                  _applyFilterAndSearch(_controller.text);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'All', child: Text('顯示全部')),
                  PopupMenuItem(value: 'Added', child: Text('已添加')),
                  PopupMenuItem(value: 'NotAdded', child: Text('未添加')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                      child: Text(_filter == 'All'
                          ? '全部'
                          : _filter == 'Added'
                              ? '已添加'
                              : '未添加')),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SearchBar2(
                  controller: _controller,
                  onSearch: (q) => _applyFilterAndSearch(q),
                ),
              ),
              Expanded(
                child: _view.isEmpty
                    ? const Center(child: Text('沒有結果'))
                    : ListView.builder(
                        itemCount: _view.length,
                        itemBuilder: (_, i) {
                          final s = _view[i];
                          final code = s['代號'];
                          final name = s['名稱'] ?? '';
                          final added = _added.contains(code);
                          final selected = _multiPick.contains(code);

                          return ListTile(
                            title: Text(name),
                            subtitle: Text(code),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    added ? Icons.check : Icons.add,
                                    color: added ? Colors.green : null,
                                  ),
                                  onPressed: added
                                      ? null
                                      : () => _addSingle(code, name),
                                ),
                                IconButton(
                                  icon: Icon(selected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank),
                                  onPressed: () => setState(() {
                                    selected
                                        ? _multiPick.remove(code)
                                        : _multiPick.add(code);
                                  }),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: _multiPick.isNotEmpty
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.done),
                  label: Text('添加 ${_multiPick.length}'),
                  onPressed: () async {
                    final m = {
                      for (var c in _multiPick)
                        c: (_stocks.firstWhere((s) => s['代號'] == c)['名稱']
                            as String) // ★ FIX
                    };
                    _multiPick.clear();
                    await _insertWatchAndStocks(m);
                    await _refreshWatchlist();
                    _toast('已添加 ${m.length} 檔');
                  },
                )
              : null,
        ),

        // 遮罩 + 進度
        if (_busy) ...[
          const ModalBarrier(color: Colors.black54, dismissible: false),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(value: _pct),
                const SizedBox(height: 12),
                Text(
                  _pct == null
                      ? '處理中...'
                      : '處理中 ${((_pct! * 100).toStringAsFixed(0))}%',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
