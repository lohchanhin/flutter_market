import 'package:flutter/material.dart';

class StockDetail extends StatelessWidget {
  final String stockCode;
  final String stockName;

  const StockDetail(
      {Key? key, required this.stockCode, required this.stockName})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(stockName),
        subtitle: Text('Code: $stockCode'),
      ),
    );
  }
}
