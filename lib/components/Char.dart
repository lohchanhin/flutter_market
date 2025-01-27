import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/stock_data.dart';

////////////////////////////////////////////////////////
// 2) KLineChart 小部件
////////////////////////////////////////////////////////
class KLineChart extends StatefulWidget {
  /// 由外部傳入的一組 K 線資料
  final List<StockData> stockData;

  /// 計算到「TD=9或TS=9」的日期，可藉由 onSignalData 傳出去
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

    // 準備 TD/TS counts 的陣列
    final length = widget.stockData.length;
    tdCounts = List.filled(length, 0);
    tsCounts = List.filled(length, 0);

    // 計算 TD/TS
    _calculateTDTSCounts(widget.stockData, tdCounts, tsCounts);

    // 收集「TD=9 / TS=9」的日子，傳給外部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSignalData(signalDays);
      _scrollToEnd();
    });
  }

  // 滾到右邊，顯示最新K
  void _scrollToEnd() {
    double chartWidth =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);
    _transformationController.value = Matrix4.identity()
      ..translate(-chartWidth + MediaQuery.of(context).size.width);
  }

  @override
  Widget build(BuildContext context) {
    // 計算圖表寬度
    double chartWidth =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);

    // 給 K 線一點上下 padding
    double minY = widget.stockData.map((e) => e.low).reduce(min) * 0.95;
    double maxY = widget.stockData.map((e) => e.high).reduce(max) * 1.05;

    return Container(
      height: 400,
      // 頂部空間 40，讓圖在視覺上更居中
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
              // 座標軸標籤
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 5, // 每5根顯示一次日期
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= widget.stockData.length) {
                        return const SizedBox.shrink();
                      }
                      // e.g. '2023-05-10' => '05-10'
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

  /// 建立蠟燭線: rod1=影線, rod2=主體
  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < widget.stockData.length; i++) {
      final data = widget.stockData[i];

      final open = data.open;
      final close = data.close;
      final high = data.high;
      final low = data.low;

      final tdVal = tdCounts[i];
      final tsVal = tsCounts[i];

      // 若TD=9/TS=9 => 收集, 可能外部要用
      if (tdVal == 9 || tsVal == 9) {
        data.isBullishSignal = (tdVal == 9);
        data.isBearishSignal = (tsVal == 9);
        signalDays.add(data);
      }

      // 判斷漲跌 => 決定K棒顏色
      final isBull = (close >= open);
      final candleColor = isBull ? Colors.green : Colors.red;

      // // rod1: 影線 (low->high)
      // final shadowRod = BarChartRodData(
      //   fromY: low,
      //   toY: high,
      //   width: 2,
      //   color: candleColor,
      // );

      // rod2: 主體 (open->close)
      final bodyRod = BarChartRodData(
        fromY: open,
        toY: close,
        width: 8,
        color: candleColor,
      );

      final group = BarChartGroupData(
        x: i,
        barRods: [bodyRod],
        showingTooltipIndicators: [0, 1],
      );
      groups.add(group);
    }
    return groups;
  }

  /// Tooltip 僅顯示 "閃電⚡" (TD=9) / "鑽石💎" (TS=9)
  BarTooltipItem _getTooltipItem(
    BarChartGroupData group,
    int groupIndex,
    BarChartRodData rod,
    int rodIndex,
  ) {
    final idx = group.x.toInt();
    final tdVal = tdCounts[idx];
    final tsVal = tsCounts[idx];

    String text = '';
    Color textColor = Colors.white;

    if (tdVal > 0) {
      // TD 狀況 => 紅色
      textColor = Colors.red;
      if (tdVal == 9) {
        text = '⚡'; // 閃電
      } else {
        text = '$tdVal'; // 顯示數字
      }
    } else if (tsVal > 0) {
      // TS 狀況 => 綠色
      textColor = Colors.green;
      if (tsVal == 9) {
        text = '💎'; // 鑽石
      } else {
        text = '$tsVal'; // 顯示數字
      }
    } else {
      // tdVal=0 && tsVal=0 => 不顯示
      text = '';
    }

    return BarTooltipItem(
      text,
      TextStyle(color: textColor, fontSize: 16),
    );
  }

  /// 計算 TD/TS
  void _calculateTDTSCounts(
      List<StockData> data, List<int> tdCounts, List<int> tsCounts) {
    for (int i = 4; i < data.length; i++) {
      // TD (連續漲)
      if (data[i].close > data[i - 4].close) {
        if (tsCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          tdCounts[i] = 1;
        } else {
          tdCounts[i] = (tdCounts[i - 1] >= 9) ? 1 : tdCounts[i - 1] + 1;
        }
        tsCounts[i] = 0;
      } else {
        // TS (連續跌)
        if (tdCounts[i - 1] > 0 ||
            (tdCounts[i - 1] == 0 && tsCounts[i - 1] == 0)) {
          tsCounts[i] = 1;
        } else {
          tsCounts[i] = (tsCounts[i - 1] >= 9) ? 1 : tsCounts[i - 1] + 1;
        }
        tdCounts[i] = 0;
      }
    }
  }
}
