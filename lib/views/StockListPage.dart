import 'package:flutter/material.dart';
import '../database/DatabaseHelper.dart'; // 确保导入正确

class StockListPage extends StatefulWidget {
  @override
  _StockListPageState createState() => _StockListPageState();
}

class _StockListPageState extends State<StockListPage> {
  List<Map<String, dynamic>> _stocks = [];

  @override
  void initState() {
    super.initState();
    _loadSavedStocks();
  }

  Future<void> _loadSavedStocks() async {
    final stocks = await DatabaseHelper.instance.getStocks();
    setState(() {
      _stocks = stocks;
    });
  }

  void _removeStock(int id) async {
    await DatabaseHelper.instance.deleteStock(id);
    _loadSavedStocks(); // 重新载入股票列表以更新UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Stocks'),
      ),
      body: ListView.builder(
        itemCount: _stocks.length,
        itemBuilder: (context, index) {
          final stock = _stocks[index];
          return ListTile(
            title: Text(stock['name']),
            subtitle: Text(stock['code']),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => _removeStock(stock['id']), // 添加移除按钮
            ),
          );
        },
      ),
    );
  }
}
