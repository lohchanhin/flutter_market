import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
// 导入相似度计算库
import '../components/SearchBar.dart';
import '../database/DatabaseHelper.dart';
// Ensure this import is correct

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _stocks = [];
  List<dynamic> _filteredStocks = [];

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  Future<void> _loadStockData() async {
    final String response =
        await rootBundle.loadString('assets/stocks_data.json');
    final data = await json.decode(response);
    setState(() {
      _stocks = data;
      _filteredStocks = _stocks;
    });
  }

  void _handleSearch(String query) {
    List<dynamic> results = [];
    if (query.isEmpty) {
      results = [];
    } else {
      results = _stocks.where((stock) {
        final String name = stock['名稱'].toLowerCase();
        final String code = stock['代號'].toLowerCase();
        return name.contains(query.toLowerCase()) ||
            code.contains(query.toLowerCase());
      }).toList();
    }
    setState(() {
      _filteredStocks = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('股票搜尋'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SearchBar2(controller: _controller, onSearch: _handleSearch),
          ),
          Expanded(
            child: _filteredStocks.isEmpty
                ? Center(child: Text('請輸入搜尋詞以查找股票'))
                : ListView.builder(
                    itemCount: _filteredStocks.length,
                    itemBuilder: (context, index) {
                      final stock = _filteredStocks[index];
                      return ListTile(
                        title: Text(stock['名稱']),
                        subtitle: Text(stock['代號']),
                        trailing: IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () {
                            // Add stock to the database
                            DatabaseHelper.instance.addStock(
                                {'code': stock['代號'], 'name': stock['名稱']});
                          },
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}
