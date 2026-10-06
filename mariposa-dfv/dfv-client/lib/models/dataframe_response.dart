// lib/models/dataframe_response.dart
class DataFrameResponse {
  final String tableName;
  final List<String> columns;
  final List<List<dynamic>> rows;
  final String? nextRowKey;

  DataFrameResponse({
    required this.tableName,
    required this.columns,
    required this.rows,
    this.nextRowKey,
  });

  factory DataFrameResponse.fromJson(Map<String, dynamic> json) {
    return DataFrameResponse(
      tableName: json['tableName'] as String,
      columns: List<String>.from(json['columns']),
      rows: (json['rows'] as List).map((row) => List<dynamic>.from(row)).toList(),
      nextRowKey: json['pagination']?['next_row_key'] as String?,
    );
  }

  // Convierte una fila específica (por índice) en un mapa amigable Key-Value
  Map<String, dynamic> getRowAsMap(int rowIndex) {
    if (rowIndex >= rows.length) return {};
    final rowData = rows[rowIndex];
    final Map<String, dynamic> rowMap = {};

    for (int i = 0; i < columns.length; i++) {
      if (i < rowData.length) {
        rowMap[columns[i]] = rowData[i];
      }
    }
    return rowMap;
  }
}
