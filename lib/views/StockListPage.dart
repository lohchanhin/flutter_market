import 'package:flutter/material.dart';
import '../components/StockList.dart'; // 確保導入正確

class StockListPage extends StatelessWidget {
  StockListPage({Key? key}) : super(key: key);

  final List<Map<String, String>> stocks = [
    {"code": "0001", "name": "Example Corp"},
    {"code": "0002", "name": "Another Inc"},
    // 添加更多股票數據
  ];

  void _selectStock(Map<String, String> stock) {
    // 處理股票選擇，如導航到詳細頁面
    print("Selected stock: ${stock['name']}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stock List'),
      ),
      body: StockList(stocks: stocks, onSelect: _selectStock),
    );
  }
}
