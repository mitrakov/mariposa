class ChartData {
  final String label;
  final double value;
  final int colorHex;

  ChartData({required this.label, required this.value, required this.colorHex});

  factory ChartData.fromJson(Map<String, dynamic> json) {
    return ChartData(
      label: json['label'],
      value: (json['value'] as num).toDouble(),
      colorHex: int.parse(json['color']),
    );
  }
}
