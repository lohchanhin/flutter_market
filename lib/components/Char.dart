import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../components/StockDetail.dart';

class KLineChart extends StatefulWidget {
  final List<StockData> stockData;
  final Function(List<StockData>) onSignalData;

  const KLineChart(
      {Key? key, required this.stockData, required this.onSignalData})
      : super(key: key);

  @override
  _KLineChartState createState() => _KLineChartState();
}

class _KLineChartState extends State<KLineChart> {
  final TransformationController _transformationController =
      TransformationController();
  List<int> tdCounts = [];
  List<int> tsCounts = [];
  List<StockData> signalDays = [];

  @override
  void initState() {
    super.initState();
    tdCounts = _calculateTDCounts(widget.stockData);
    tsCounts = _calculateTSCounts(widget.stockData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSignalData(
          signalDays); // Call the callback to pass signal data back
      _scrollToEnd(); // Scrolls to the end after the frame is built
    });
  }

  void _scrollToEnd() {
    double width =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);
    _transformationController.value = Matrix4.identity()
      ..translate(-width + MediaQuery.of(context).size.width);
  }

  @override
  Widget build(BuildContext context) {
    double chartWidth =
        MediaQuery.of(context).size.width * (widget.stockData.length / 10);
    double minY = widget.stockData.map((e) => e.low).reduce(min) * 0.9;
    double maxY = widget.stockData.map((e) => e.high).reduce(max) * 1.1;

    return Container(
      height: 400,
      padding: EdgeInsets.all(20),
      child: InteractiveViewer(
        transformationController: _transformationController,
        constrained: false,
        scaleEnabled: true,
        panEnabled: true,
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
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: true)),
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              gridData: FlGridData(show: true),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipRoundedRadius: 8,
                  tooltipPadding: EdgeInsets.all(8),
                  tooltipMargin: 5,
                  tooltipBorder: BorderSide(color: Colors.grey),
                  getTooltipItem: _getTooltipItem,
                ),
              ),
            ),
            swapAnimationDuration: const Duration(milliseconds: 650),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    return widget.stockData
        .asMap()
        .map((index, data) {
          double open = data.open;
          double close = data.close;
          bool isBull = open < close;
          int tdCount = tdCounts[index];
          int tsCount = tsCounts[index];

          if (tdCount == 9 || tsCount == 9) {
            data.isBullishSignal = tdCount == 9;
            data.isBearishSignal = tsCount == 9;
            signalDays.add(data); // Collecting days with signals
          }

          return MapEntry(
            index,
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  fromY: open,
                  toY: close,
                  color: isBull ? Colors.green : Colors.red,
                  width: 10,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    fromY: open,
                    toY: close,
                    color: Colors.grey[300]!,
                  ),
                ),
              ],
              showingTooltipIndicators: [0],
            ),
          );
        })
        .values
        .toList();
  }

  BarTooltipItem _getTooltipItem(BarChartGroupData group, int groupIndex,
      BarChartRodData rod, int rodIndex) {
    final int tdCount = tdCounts[group.x.toInt()];
    final int tsCount = tsCounts[group.x.toInt()];
    if (tdCount == 9) {
      return BarTooltipItem('⚡ $tdCount', TextStyle(color: Colors.green));
    } else if (tsCount == 9) {
      return BarTooltipItem('💎 $tsCount', TextStyle(color: Colors.red));
    } else {
      return BarTooltipItem("${tdCount > 0 ? tdCount : tsCount}",
          TextStyle(color: tdCount > 0 ? Colors.red : Colors.green));
    }
  }

  List<int> _calculateTDCounts(List<StockData> data) {
    List<int> tdCounts = List.filled(data.length, 0);
    for (int i = 4; i < data.length; i++) {
      if (data[i].close > data[i - 4].close) {
        tdCounts[i] = (tdCounts[i - 1] < 9) ? tdCounts[i - 1] + 1 : 1;
      } else {
        tdCounts[i] = 0;
      }
    }
    return tdCounts;
  }

  List<int> _calculateTSCounts(List<StockData> data) {
    List<int> tsCounts = List.filled(data.length, 0);
    for (int i = 4; i < data.length; i++) {
      if (data[i].close < data[i - 4].close) {
        tsCounts[i] = (tsCounts[i - 1] < 9) ? tsCounts[i - 1] + 1 : 1;
      } else {
        tsCounts[i] = 0;
      }
    }
    return tsCounts;
  }
}
