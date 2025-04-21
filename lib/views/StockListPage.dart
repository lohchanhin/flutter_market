// lib/views/StockListPage.dart
// 2025‑04 最終整合版

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/DatabaseHelper.dart';
import '../services/api_service.dart';
import '../components/StockDetail.dart';

class StockListPage extends StatefulWidget {
  const StockListPage({super.key});
  @override
  State<StockListPage> createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
// ──────────────────── 服務 ────────────────────
  final dbHelper = DatabaseHelper.instance;
  final api = ApiService();

// ──────────────────── 篩選條件 ────────────────────
  String _filterFreq = 'All'; // All / Day / Week
  String _filterSignal = 'All'; // All / TD / TS
  bool _enablePAI = false; // 是否啟用 PAI 篩選
  String _filterPaiSignal = 'All'; // All / PAI_Buy / PAI_Sell
  int _maxDays = 14; // 最近 TD/TS 天數門檻
  bool _needRecentTDTS = true; // 啟用 PAI 時，是否還要最近 TD/TS

// ──────────────────── 狀態 ────────────────────
  List<Map<String, dynamic>> _filtered = [];
  bool _updating = false;
  int _progress = 0, _total = 0;
  DateTime? _selectedDate;

// ──────────────────── 初始化 ────────────────────
  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

// ═════ 本地資料載入 + 篩選 ═════
  Future<void> _loadLocalData() async {
    final watchCodes =
        (await dbHelper.getWatchlist()).map((e) => e['code']).toSet();

    var list = (await dbHelper.getStocks())
        .where((r) => watchCodes.contains(r['code']))
        .toList();

    if (_filterFreq != 'All')
      list = list.where((e) => e['freq'] == _filterFreq).toList();
    if (_filterSignal == 'TD')
      list = list.where((e) => e['signal'] == '闪电').toList();
    if (_filterSignal == 'TS')
      list = list.where((e) => e['signal'] == '钻石').toList();

    if (_enablePAI && _filterPaiSignal != 'All') {
      list = await _applyPaiFilter(list);
    }

    if (mounted) setState(() => _filtered = list);
  }

  /// PAI + (可選) 最近 TD/TS 過濾
  Future<List<Map<String, dynamic>>> _applyPaiFilter(
      List<Map<String, dynamic>> src) async {
    final out = <Map<String, dynamic>>[];
    for (final m in src) {
      if (m['paiSignal'] != _filterPaiSignal) continue;
      if (!_needRecentTDTS) {
        out.add(m);
        continue;
      }

      final latest = await dbHelper.getLatestTDTSDateByCode(m['code']);
      if (latest == null) continue;
      if (DateTime.now().difference(latest).inDays <= _maxDays) out.add(m);
    }
    return out;
  }

  Future<void> _refreshAfterFilter() async {
    // 確保 setState 之外非同步執行
    await Future.microtask(() {});
    _selectedDate == null ? _loadLocalData() : _fetchServerByDate();
  }

// ═════ 伺服器（指定日）查詢 ═════
  Future<void> _fetchServerByDate() async {
    if (_selectedDate == null) return;
    setState(() => _updating = true);
    try {
      final ds = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final freq = _filterFreq != 'All' ? _filterFreq : null;
      String? sig;
      if (_filterSignal == 'TD') sig = 'TD';
      if (_filterSignal == 'TS') sig = 'TS';

      final raw =
          await api.getStocksByDate(date: ds, freq: freq, signalType: sig);

      // 合併重複 id
      final Map<int, Map<String, dynamic>> merged = {};
      for (final r in raw) {
        final id = r['id'];
        merged[id] ??= {...r, 'signalSet': <String>{}};
        if (r['signal'] != null)
          (merged[id]!['signalSet'] as Set).add(r['signal']);
      }

      final list = <Map<String, dynamic>>[];
      merged.forEach((_, m) {
        final ss = m['signalSet'] as Set;
        m['signal'] = ss.containsAll({'闪电', '钻石'})
            ? 'both'
            : ss.contains('闪电')
                ? '闪电'
                : ss.contains('钻石')
                    ? '钻石'
                    : '';
        m.remove('signalSet');
        list.add(m);
      });

      if (_enablePAI && _filterPaiSignal != 'All') {
        await Future.wait(list.map((e) async {
          if (e['paiSignal'] != _filterPaiSignal) return;
          if (!_needRecentTDTS) return;
          final latest = await dbHelper.getLatestTDTSDateByCode(e['code']);
          e['within'] = latest != null &&
              DateTime.now().difference(latest).inDays <= _maxDays;
        }));
      }

      var res = list;
      if (_enablePAI && _filterPaiSignal != 'All') {
        res = res
            .where((e) =>
                e['paiSignal'] == _filterPaiSignal &&
                (_needRecentTDTS ? e['within'] == true : true))
            .toList();
      }
      setState(() => _filtered = res);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

// ═════ 同步全部股票 ═════
  Future<void> _syncAll() async {
    setState(() {
      _updating = true;
      _progress = 0;
      _total = 0;
    });

    try {
      final remote = await api.getAllStocks();
      final local = await dbHelper.getStocks();
      final map = {for (var l in local) '${l['code']}|${l['freq']}': l};

      _total = remote.length;

      for (final r in remote) {
        final serverId = r['id'] as int;
        final code = r['code'];
        final freq = (r['freq'] ?? 'Day').toString();
        final key = '$code|$freq';

        if (map.containsKey(key)) {
          final id = map[key]!['id'] as int;
          await dbHelper.updateStockServerId(id, serverId);
          await dbHelper.updateStockSignal(
            id,
            r['signal'],
            r['lastUpdate'] ?? DateTime.now().toIso8601String(),
            r['tdCount'] ?? 0,
            r['tsCount'] ?? 0,
            r['pai'],
            r['paiSignal'],
          );
        }

        await dbHelper.deleteSignalsByStockId(serverId);
        final sigs = r['signals'] as List? ?? [];
        if (sigs.isNotEmpty) {
          await dbHelper.batchInsertSignals(
            sigs.map((s) => Map<String, dynamic>.from(s)).toList(),
          );
        }

        setState(() => _progress++);
      }

      await _loadLocalData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所有股票已同步完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

// ═════ Bottom‑Sheet 濾鏡 ═════
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        // 暫存 UI 狀態
        String freq = _filterFreq;
        String sig = _filterSignal;
        String pai = _filterPaiSignal;
        int days = _maxDays;
        bool need = _needRecentTDTS;
        bool enablePai = _enablePAI;

        return StatefulBuilder(builder: (ctx, setSt) {
          Widget group(String title, List<String> items, String sel,
              Map<String, String> label, void Function(String) onTap) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 8,
                  children: items
                      .map((v) => ChoiceChip(
                            label: Text(label[v] ?? v),
                            selected: sel == v,
                            onSelected: (_) {
                              setSt(() => onTap(v)); // 立即反白
                              _refreshAfterFilter(); // 重跑篩選
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
            );
          }

          return DraggableScrollableSheet(
            expand: false,
            builder: (_, scroll) => Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scroll,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  group('週期', ['All', 'Day', 'Week'], freq,
                      {'All': '全部', 'Day': '日', 'Week': '週'}, (v) {
                    freq = v;
                    setState(() => _filterFreq = v);
                  }),
                  group('信號', ['All', 'TD', 'TS'], sig,
                      {'All': '全部', 'TD': '閃電', 'TS': '鑽石'}, (v) {
                    sig = v;
                    setState(() => _filterSignal = v);
                  }),
                  SwitchListTile(
                    title: const Text('啟用 PAI 篩選'),
                    value: enablePai,
                    onChanged: (b) {
                      setSt(() => enablePai = b);
                      setState(() => _enablePAI = enablePai);
                      _refreshAfterFilter();
                    },
                  ),
                  if (enablePai) ...[
                    group('PAI 類型', ['All', 'PAI_Buy', 'PAI_Sell'], pai,
                        {'All': '全部', 'PAI_Buy': '買入', 'PAI_Sell': '賣出'}, (v) {
                      pai = v;
                      setState(() => _filterPaiSignal = v);
                    }),
                    Row(children: [
                      const Expanded(child: Text('最近 TD/TS 天數上限')),
                      Text('≤ $days'),
                    ]),
                    Slider(
                      value: days.toDouble(),
                      min: 3,
                      max: 30,
                      divisions: 9,
                      label: '$days',
                      onChanged: (v) {
                        setSt(() => days = v.round());
                        setState(() => _maxDays = days);
                        _refreshAfterFilter();
                      },
                    ),
                    SwitchListTile(
                      title: const Text('PAI 需同時最近 TD/TS'),
                      subtitle: const Text('關閉＝只檢查 PAI，不檢查 TD/TS 時間'),
                      value: need,
                      onChanged: (b) {
                        setSt(() => need = b);
                        setState(() => _needRecentTDTS = need);
                        _refreshAfterFilter();
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        });
      },
    );
  }

// ═════ 輔助 ═════
  String _fmtUpdate(Object? s, String freq) {
    if (s == null) return '歷史資料';
    try {
      final dt = DateTime.parse(s.toString());
      if (freq == 'Week') {
        final mon = dt.subtract(Duration(days: dt.weekday - 1));
        return '最後更新：${DateFormat('yyyy-MM-dd').format(mon)}';
      }
      return '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
    } catch (_) {
      return '格式錯誤';
    }
  }

  Icon _icon(String? sig, String? pai) {
    switch (sig) {
      case '闪电':
        return const Icon(Icons.flash_on, color: Colors.green);
      case '钻石':
        return const Icon(Icons.diamond, color: Colors.red);
      case 'both':
        return const Icon(Icons.stars, color: Colors.purple);
    }
    switch (pai) {
      case 'PAI_Buy':
        return const Icon(Icons.trending_up, color: Colors.lightGreen);
      case 'PAI_Sell':
        return const Icon(Icons.trending_down, color: Colors.orange);
      default:
        return const Icon(Icons.do_not_disturb, color: Colors.grey);
    }
  }

// ═════ UI 主體 ═════
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      IgnorePointer(
        ignoring: _updating,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Stocks (Watchlist)'),
            actions: [
              IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: '同步更新',
                  onPressed: _updating ? null : _syncAll),
              IconButton(
                  icon: const Icon(Icons.filter_alt),
                  tooltip: '篩選',
                  onPressed: _openFilterSheet),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_selectedDate == null
                        ? '選擇日期'
                        : DateFormat('yyyy-MM-dd').format(_selectedDate!)),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: _selectedDate ?? DateTime.now());
                      if (d != null) {
                        setState(() => _selectedDate = d);
                        _fetchServerByDate();
                      }
                    }),
                if (_selectedDate != null)
                  IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _selectedDate = null);
                        _loadLocalData();
                      }),
                const Spacer(),
                Text('符合: ${_filtered.length}'),
              ]),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('沒有符合條件的股票'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final s = _filtered[i];
                        return ListTile(
                          leading: _icon(s['signal'], s['paiSignal']),
                          title: Text('${s['name']} (${s['freq']})'),
                          subtitle: Text(
                              '${s['code']} • TD:${s['tdCount']} TS:${s['tsCount']}'
                              '${s['daysSinceSignal'] != null ? ' • 最近:${s['daysSinceSignal']}天' : ''}\n'
                              '${_fmtUpdate(s['lastUpdate'], s['freq'] ?? 'Day')}'),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => StockDetail(
                                      stockCode: s['code'],
                                      stockName: s['name'],
                                      freq: s['freq'] ?? 'Day'))),
                        );
                      }),
            ),
          ]),
        ),
      ),
      if (_updating) ...[
        const ModalBarrier(color: Colors.black45, dismissible: false),
        Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(
              value: _total > 0 ? _progress / _total : null),
          const SizedBox(height: 16),
          Text('同步中 $_progress/$_total',
              style: const TextStyle(color: Colors.white)),
        ])),
      ],
    ]);
  }
}
