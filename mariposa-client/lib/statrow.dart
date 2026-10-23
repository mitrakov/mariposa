class MariposaStatRow {
  final String key;
  final Map<String, double> metrics;

  MariposaStatRow(this.key, this.metrics);

  factory MariposaStatRow.fromTabular(List<String> columns, List<dynamic> rowValues) {
    String rowKey = "Unknown";
    Map<String, double> values = {};

    for (int i = 0; i < columns.length; i++) {
      if (i >= rowValues.length) break; // in case of columns count mismatch

      final columnName = columns[i];
      final rawValue = rowValues[i];

      if (columnName == 'id' || columnName == 'key') {
        rowKey = rawValue.toString();
      } else {
        values[columnName] = double.tryParse(rawValue.toString()) ?? 0.0;
      }
    }

    String displayKey = rowKey.length > 16 ? '${rowKey.substring(0, 13)}...' : rowKey;

    return MariposaStatRow(displayKey, values);
  }
}
