import 'package:flutter/material.dart';

class StockList extends StatelessWidget {
  final List<Map<String, String>> stocks;
  final Function(Map<String, String>) onSelect;

  const StockList({Key? key, required this.stocks, required this.onSelect})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: stocks.length,
      itemBuilder: (context, index) {
        final stock = stocks[index];
        return ListTile(
          title: Text(stock['name']!),
          subtitle: Text(stock['code']!),
          onTap: () => onSelect(stock),
        );
      },
    );
  }
}
