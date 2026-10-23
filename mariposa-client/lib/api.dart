import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mariposa/dataframe.dart';
import 'package:mariposa/statrow.dart';

class MariposaApiClient {
  final String baseUrl;
  MariposaApiClient({this.baseUrl = 'http://myfeo.fun:7012/v1/hbase'});

  Future<List<String>> fetchHBaseTables() async {
    final response = await http.get(Uri.parse('$baseUrl/tables'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((table) => table.toString()).toList();
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }

  Future<List<MariposaStatRow>> fetchTable(String table) async {
    final response = await http.get(Uri.parse('$baseUrl/table/$table'));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> rawColumns = data['columns'] ?? [];
      final List<dynamic> rawRows = data['rows'] ?? [];
      final List<String> columns = rawColumns.map((c) => c.toString()).toList();

      return rawRows.map((dynamic rowItem) {
        final List<dynamic> rowValues = rowItem as List<dynamic>;
        return MariposaStatRow.fromTabular(columns, rowValues);
      }).toList();
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }
  
  Future<DataFrameResponse> fetchDataframe(String table) async {
    final response = await http.get(Uri.parse('$baseUrl/table/$table'));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return DataFrameResponse.fromJson(data);
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }
}
