import 'package:flutter/material.dart';
import '../components/SearchBar.dart'; // 確保導入正確

class SearchPage extends StatelessWidget {
  SearchPage({Key? key}) : super(key: key);

  final TextEditingController _controller = TextEditingController();

  void _handleSearch(String query) {
    // 搜索邏輯實現
    // 這裡可以連接到你的模型或狀態管理來實際搜索股票
    print("Searching for: $query");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search Stocks'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SearchBar2(controller: _controller, onSearch: _handleSearch),
      ),
    );
  }
}
