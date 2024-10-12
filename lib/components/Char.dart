import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../components/StockDetail.dart';

class KLineChart extends StatelessWidget {
  final List<StockData> stockData;

  const KLineChart({Key? key, required this.stockData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<int> tdCounts = _calculateTDCounts(stockData);
    List<int> tsCounts = _calculateTSCounts(stockData);
    double chartWidth =
        MediaQuery.of(context).size.width * (stockData.length / 10);

    return Container(
      height: 400,
      padding: EdgeInsets.all(20),
      child: InteractiveViewer(
        constrained: false,
        scaleEnabled: true,
        panEnabled: true,
        child: SizedBox(
          width: chartWidth,
          height: 400,
          child: BarChart(
            BarChartData(
              barGroups: stockData
                  .asMap()
                  .map((index, data) {
                    double open = data.open;
                    double close = data.close;
                    bool isBull = open < close;
                    int tdCount = tdCounts[index];
                    int tsCount = tsCounts[index];
                    return MapEntry(
                      index,
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                              fromY: open,
                              toY: close,
                              color: isBull ? Colors.green : Colors.red,
                              width: 2,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(2)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                fromY: open,
                                toY: close,
                                color: Colors.grey[300]!,
                              )),
                        ],
                        showingTooltipIndicators: [0],
                      ),
                    );
                  })
                  .values
                  .toList(),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: true)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
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
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final int tdCount = tdCounts[group.x.toInt()];
                    final int tsCount = tsCounts[group.x.toInt()];
                    if (tdCount == 9) {
                      return BarTooltipItem(
                        '⚡ $tdCount', // 鑽石符號代表多頭信號
                        TextStyle(color: Colors.green),
                      );
                    } else if (tsCount == 9) {
                      return BarTooltipItem(
                        '💎 $tsCount', // 閃電符號代表空頭信號
                        TextStyle(color: Colors.red),
                      );
                    } else {
                      TextStyle style = TextStyle(
                          color: tdCount > 0 ? Colors.red : Colors.green);
                      return BarTooltipItem(
                          "${tdCount > 0 ? tdCount : tsCount}", style);
                    }
                  },
                ),
              ),
            ),
            swapAnimationDuration: const Duration(milliseconds: 650),
          ),
        ),
      ),
    );
  }

  List<int> _calculateTDCounts(List<StockData> data) {
    List<int> tdCounts = List.filled(data.length, 0);
    int count = 0;
    for (int i = 4; i < data.length; i++) {
      if (data[i].close > data[i - 4].close) {
        count = count < 9 ? count + 1 : 1;
      } else {
        count = 0;
      }
      tdCounts[i] = count;
    }
    return tdCounts;
  }

  List<int> _calculateTSCounts(List<StockData> data) {
    List<int> tsCounts = List.filled(data.length, 0);
    int count = 0;
    for (int i = 4; i < data.length; i++) {
      if (data[i].close < data[i - 4].close) {
        count = count < 9 ? count + 1 : 1;
      } else {
        count = 0;
      }
      tsCounts[i] = count;
    }
    return tsCounts;
  }
}
