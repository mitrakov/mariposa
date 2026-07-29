class ChartData {
  final String rowKey;
  final double men;
  final double women;

  ChartData({required this.rowKey, required this.men, required this.women});

  factory ChartData.fromJson(Map<String, dynamic> json) {
    return ChartData(
      rowKey: json['rowKey'],
      men: (json['men'] as num).toDouble(),
      women: (json['women'] as num).toDouble(),
    );
  }
}
