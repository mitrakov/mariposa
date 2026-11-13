class DataFrameResponse {
  final List<Map<String, dynamic>> rows;
  final String? nextId;

  DataFrameResponse(this.rows, this.nextId);

  factory DataFrameResponse.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List<dynamic>? ?? [];
    return DataFrameResponse(rawRows.map((row) => Map<String, dynamic>.from(row as Map)).toList(), json['nextId'] as String?);
  }

  Map<String, dynamic> getRowAsMap(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= rows.length) return {};
    return rows[rowIndex];
  }
}
