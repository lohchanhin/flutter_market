class StockData {
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double adjClose;
  final int volume;
  final bool? isBullishSignal;

  StockData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.adjClose,
    required this.volume,
    this.isBullishSignal,
  });

  StockData copyWith({
    String? date,
    double? open,
    double? high,
    double? low,
    double? close,
    double? adjClose,
    int? volume,
    bool? isBullishSignal,
  }) {
    return StockData(
      date: date ?? this.date,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      adjClose: adjClose ?? this.adjClose,
      volume: volume ?? this.volume,
      isBullishSignal: isBullishSignal ?? this.isBullishSignal,
    );
  }
}
