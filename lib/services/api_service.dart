import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://market-search-server.onrender.com/api';

  /// 1) 取得所有儲存的股票 (清單)
  /// 後端回傳格式:
  /// [
  ///   {
  ///     "id": 1,
  ///     "code": "1101",
  ///     "name": "台泥",
  ///     "freq": "Day",
  ///     "signal": null,
  ///     "lastUpdate": "2025-01-26T17:18:14.467Z",
  ///     "tdCount": 5,
  ///     "tsCount": 0
  ///   },
  ///   ...
  /// ]
  Future<List<dynamic>> getAllStocks() async {
    final response = await http.get(Uri.parse('$baseUrl/stocks'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List;
    } else {
      throw Exception(
          'Failed to fetch stocks. StatusCode = ${response.statusCode}');
    }
  }

  /// 2) 新增股票 (code, name, freq)
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

  /// 3) 刪除股票 (by ID)
  Future<void> deleteStock(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to delete stock. StatusCode = ${response.statusCode}');
    }
  }

  /// 4) 更新「全部」股票 (後端做抓取 + TD/TS 計算)
  /// 用後端最新結果 => getAllStocks() => 同步本地
  Future<void> updateAllStocks() async {
    final response = await http.post(Uri.parse('$baseUrl/stocks/updateAll'));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to update all stocks. StatusCode = ${response.statusCode}');
    }
  }

  /// 5) 更新「單一」股票 (by ID)
  Future<void> updateSingleStock(int id) async {
    final url = '$baseUrl/stocks/$id/update';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to update single stock. StatusCode = ${response.statusCode}');
    }
  }

  /// 6) 取得「單一」股票詳細 (by ID)
  Future<Map<String, dynamic>> getStockDetail(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/$id'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to fetch stock detail. StatusCode = ${response.statusCode}');
    }
  }

  /// (可選) 如果後端支援「依股票代碼」查詢
  Future<Map<String, dynamic>> getStockDetailByCode(String code) async {
    final response = await http.get(Uri.parse('$baseUrl/stocks/code/$code'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to fetch stock detail by code. StatusCode = ${response.statusCode}');
    }
  }

  // ------------------------------------------------------------------------
  // ★★★ 新增 - 依日期、週期、訊號類型 查詢「該日有訊號的股票」 ★★★
  // GET /stocks/signalsByDate?date=YYYY-MM-DD&freq=Day/Week&signalType=TD/TS
  // - date (必填) => ex: '2025-03-18'
  // - freq (選填) => 'Day' or 'Week'; 若未指定或 'All' 則不傳
  // - signalType (選填) => 'TD' or 'TS'; 若未指定或 'All' 則不傳
  // 後端預期回傳:
  // {
  //   "count": 3,
  //   "data": [
  //     {
  //       "stockId": 7,
  //       "code": "1101",
  //       "name": "台泥",
  //       "freq": "Day",
  //       "date": "2025-03-18",
  //       "signal": "闪电",
  //       "tdCount": 9,
  //       "tsCount": 0
  //     },
  //     ...
  //   ]
  // }
  // ------------------------------------------------------------------------
  Future<List<dynamic>> getStocksByDate({
    required String date,
    String? freq,
    String? signalType,
  }) async {
    // 準備 query
    final queryParams = <String, String>{'date': date};

    // freq != null & != 'All' 才加到 query
    if (freq != null && freq != 'All') {
      queryParams['freq'] = freq;
    }

    // signalType = 'TD' 或 'TS' 才加
    if (signalType == 'TD') {
      queryParams['signalType'] = 'TD';
    } else if (signalType == 'TS') {
      queryParams['signalType'] = 'TS';
    }

    final uri = Uri.parse('$baseUrl/stocks/signalsByDate')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final jsonMap = json.decode(response.body) as Map<String, dynamic>;
      if (jsonMap.containsKey('data')) {
        // 取得實際的股票清單
        return jsonMap['data'] as List<dynamic>;
      } else {
        throw Exception('Invalid response format: no "data" field found.');
      }
    } else {
      throw Exception(
          'Failed to fetch stocks by date. StatusCode = ${response.statusCode}');
    }
  }
}
