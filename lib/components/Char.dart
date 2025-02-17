import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/stock_data.dart';

////////////////////////////////////////////////////////
// KLineChart 小部件（升級版）
////////////////////////////////////////////////////////
class KLineChart extends StatefulWidget {
  /// 外部傳入的一組 K 線資料
  final List<StockData> stockData;

  /// 計算到「TD=9 或 TS=9」的訊號日，回傳給外部
  final Function(List<StockData>) onSignalData;

  const KLineChart({
    Key? key,
    required this.stockData,
    required this.onSignalData,
  }) : super(key: key);

  @override
  _KLineChartState createState() => _KLineChartState();
}

class _KLineChartState extends State<KLineChart> {
  final TransformationController _transformationController =
      TransformationController();

  late List<int> tdCounts;
  late List<int> tsCounts;
  List<StockData> signalDays = [];

  @override
  void initState() {
    super.initState();
    final length = widget.stockData.length;
    tdCounts = List.filled(length, 0);
    tsCounts = List.filled(length, 0);

    // 計算 TD/TS 次數（從第 4 筆開始）
    _calculateTDTSCounts(widget.stockData, tdCounts, tsCounts);

    // 根據 TD/TS 次數計算訊號，從第 4 筆開始
    for (int i = 4; i < widget.stockData.length; i++) {
      if (tdCounts[i] == 9) {
        // TD==9 代表賣訊號，設定 isBullishSignal 為 false
        signalDays.add(widget.stockData[i].copyWith(isBullishSignal: false));
      } else if (tsCounts[i] == 9) {
        // TS==9 代表買訊號，設定 isBullishSignal 為 true
        signalDays.add(widget.stockData[i].copyWith(isBullishSignal: true));
      }
    }

    // 畫面繪製後回傳訊號資料並滾動到最新K棒
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSignalData(signalDays);
      _scrollToEnd();
    });
  }

  // 滾動到圖表右邊，顯示最新 K 棒
  void _scrollToEnd() {
    double chartWidth =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);
    _transformationController.value = Matrix4.identity()
      ..translate(-chartWidth + MediaQuery.of(context).size.width);
  }

  @override
  Widget build(BuildContext context) {
    double chartWidth =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);
    double minY = widget.stockData.map((e) => e.low).reduce(min) * 0.95;
    double maxY = widget.stockData.map((e) => e.high).reduce(max) * 1.05;

    return Container(
      height: 400,
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InteractiveViewer(
        constrained: false,
        scaleEnabled: true,
        panEnabled: true,
        transformationController: _transformationController,
        child: SizedBox(
          width: chartWidth,
          height: 400,
          child: BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              barGroups: _buildBarGroups(),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 5, // 每 5 根顯示一次日期
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= widget.stockData.length) {
                        return const SizedBox.shrink();
                      }
                      // 格式化日期：例如 '2023-05-10' 只顯示 '05-10'
                      final rawDate = widget.stockData[idx].date;
                      final label = (rawDate.length >= 10)
                          ? rawDate.substring(5, 10)
                          : rawDate;
                      return Text(label, style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.all(8),
                  tooltipMargin: 5,
                  tooltipBorder: const BorderSide(color: Colors.grey),
                  getTooltipItem: _getTooltipItem,
                ),
              ),
            ),
            swapAnimationDuration: const Duration(milliseconds: 400),
          ),
        ),
      ),
    );
  }

  /// 建立每根 K 線的 BarChartGroupData（僅用於繪製圖表）
  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < widget.stockData.length; i++) {
      final data = widget.stockData[i];
      final open = data.open;
      final close = data.close;
      final high = data.high;
      final low = data.low;

      // 判斷漲跌 => 決定 K 棒顏色
      final isBull = (close >= open);
      final candleColor = isBull ? Colors.green : Colors.red;

      final bodyRod = BarChartRodData(
        fromY: open,
        toY: close,
        width: 8,
        color: candleColor,
      );

      final group = BarChartGroupData(
        x: i,
        barRods: [bodyRod],
        showingTooltipIndicators: [0],
      );
      groups.add(group);
    }
    return groups;
  }

  /// Tooltip 僅顯示 "⚡" (TD==9) 或 "💎" (TS==9)，若尚未達 9 則顯示累計數字
  BarTooltipItem _getTooltipItem(BarChartGroupData group, int groupIndex,
      BarChartRodData rod, int rodIndex) {
    final idx = group.x.toInt();
    final tdVal = tdCounts[idx];
    final tsVal = tsCounts[idx];

    String text = '';
    Color textColor = Colors.white;

    if (tdVal > 0) {
      textColor = Colors.red;
      if (tdVal == 9) {
        text = '⚡'; // 賣訊號標記
      } else {
        text = '$tdVal';
      }
    } else if (tsVal > 0) {
      textColor = Colors.green;
      if (tsVal == 9) {
        text = '💎'; // 買訊號標記
      } else {
        text = '$tsVal';
      }
    }
    return BarTooltipItem(
      text,
      TextStyle(color: textColor, fontSize: 16),
    );
  }

  /// 計算 TD/TS 次數
  /// 從第 4 筆資料開始，若當前收盤大於第 i-4 筆則累加 TD（否則歸 0），反之則累加 TS
  void _calculateTDTSCounts(
      List<StockData> data, List<int> tdCounts, List<int> tsCounts) {
    for (int i = 4; i < data.length; i++) {
      double currentClose = data[i].close;
      double previousClose = data[i - 4].close;
      if (currentClose > previousClose) {
        tdCounts[i] = (tdCounts[i - 1] < 9) ? tdCounts[i - 1] + 1 : 1;
        tsCounts[i] = 0;
      } else if (currentClose < previousClose) {
        tsCounts[i] = (tsCounts[i - 1] < 9) ? tsCounts[i - 1] + 1 : 1;
        tdCounts[i] = 0;
      } else {
        tdCounts[i] = 0;
        tsCounts[i] = 0;
      }
    }
  }
}
