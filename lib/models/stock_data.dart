// models/stock_data.dart
class StockData {
  final String date;
  final double open, high, low, close, adjClose;
  final int volume;

  int? tdCount;
  bool? isBullishSignal;
  bool? isBearishSignal;

  StockData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.adjClose,
    required this.volume,
    this.tdCount,
    this.isBullishSignal,
    this.isBearishSignal,
  });
}
