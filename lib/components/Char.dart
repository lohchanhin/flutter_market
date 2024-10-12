import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../components/StockDetail.dart';

class KLineChart extends StatelessWidget {
  final List<StockData> stockData;

  const KLineChart({Key? key, required this.stockData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<int> tdCounts = _calculateTDCounts(stockData);
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
                        showingTooltipIndicators: [
                          0
                        ], // Add index here to show tooltip
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
                    final int count = tdCounts[group.x.toInt()];
                    if (count == 9) {
                      return BarTooltipItem(
                        "${rod.toY > rod.fromY ? '⚡' : '💎'} $count",
                        TextStyle(
                            color: rod.toY > rod.fromY
                                ? Colors.green
                                : Colors.red),
                      );
                    } else {
                      return BarTooltipItem(
                        "$count",
                        TextStyle(color: Colors.blue),
                      );
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
      } else if (data[i].close < data[i - 4].close) {
        count = count < 9 ? count + 1 : 1;
      } else {
        count = 0; // Reset on no trend continuation
      }
      tdCounts[i] = count;
    }
    return tdCounts;
  }
}
