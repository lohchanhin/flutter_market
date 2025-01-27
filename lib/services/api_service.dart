import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  static const String baseUrl = 'https://market-search-server.onrender.com/api';

  // 1) 取得所有儲存的股票 (清單)
  // 後端回傳格式:
  // [
  //   {
  //     "id": 1,
  //     "code": "1101",
  //     "name": "台泥",
  //     "freq": "Day",
  //     "signal": null,
  //     "lastUpdate": "2025-01-26T17:18:14.467Z",
  //     "tdCount": 5,
  //     "tsCount": 0
  //   },
  //   ...
  // ]
  Future<List<dynamic>> getAllStocks() async {
    final response = await http.get(Uri.parse('$baseUrl/stocks'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List;
    } else {
      throw Exception(
          'Failed to fetch stocks. StatusCode = ${response.statusCode}');
    }
  }

  // 2) 新增股票 (code, name, freq)
  Future<void> addStock(String code, String name, String freq) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stocks'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'code': code,
        'name': name,
        'freq': freq,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to add stock. StatusCode = ${response.statusCode}');
    }
  }

  // 3) 刪除股票 (by ID)
  Future<void> deleteStock(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to delete stock. StatusCode = ${response.statusCode}');
    }
  }

  // 4) 更新「全部」股票 (後端做抓取 + TD/TS 計算)
  // 用後端最新結果 => getAllStocks() => 同步本地
  Future<void> updateAllStocks() async {
    final response = await http.post(Uri.parse('$baseUrl/stocks/updateAll'));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to update all stocks. StatusCode = ${response.statusCode}');
    }
  }

  // 5) 更新「單一」股票 (by ID)
  Future<void> updateSingleStock(int id) async {
    final url = '$baseUrl/stocks/$id/update';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to update single stock. StatusCode = ${response.statusCode}');
    }
  }

  // 6) 取得「單一」股票詳細 (by ID)
  Future<Map<String, dynamic>> getStockDetail(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to fetch stock detail. StatusCode = ${response.statusCode}');
    }
  }

  // (可選) 如果後端支援「依股票代碼」查詢
  Future<Map<String, dynamic>> getStockDetailByCode(String code) async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/code/$code'));
    print('$baseUrl/stocks/code/$code');
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to fetch stock detail by code. StatusCode = ${response.statusCode}');
    }
  }
}
