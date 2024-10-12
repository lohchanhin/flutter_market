import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../components/StockDetail.dart';

class KLineChart extends StatelessWidget {
  final List<StockData> stockData;

  const KLineChart({Key? key, required this.stockData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: EdgeInsets.all(20),
      child: BarChart(
        BarChartData(
          barGroups: stockData.map((data) {
            double open = data.open;
            double close = data.close;
            bool isBull = open < close;
            return BarChartGroupData(
              x: stockData.indexOf(data),
              barRods: [
                BarChartRodData(
                    fromY: open,
                    toY: close,
                    color: isBull ? Colors.green : Colors.red,
                    width: 2, // 设置柱子的宽度
                    borderRadius:
                        BorderRadius.all(Radius.circular(2)), // 设置柱子的圆角
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      fromY: open,
                      toY: close,
                      color: Colors.grey[300]!, // 使用较浅的颜色显示背景
                    ))
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            show: true,
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: true),
          gridData: FlGridData(show: true),
        ),
      ),
    );
  }
}
