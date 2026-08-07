import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mariposa/dataframe.dart'; // Asegúrate de que aquí viva MariposaDataRow

class MariposaApiClient {
  final String baseUrl;

  MariposaApiClient({this.baseUrl = 'http://mitrakoff.ru:7012'});

  Future<List<String>> fetchHBaseTables() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/hbase/tables'));

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((table) => table.toString()).toList();
    } else throw Exception('Failed to load catalog from Pekko');
  }

  /// Recupera cualquier tabla de HBase y la convierte en una estructura de filas dinámica.
  Future<List<MariposaDataRow>> fetchDataMart(String namespace, String table) async {
    final response = await http.get(Uri.parse('$baseUrl/v1/hbase/$namespace/$table'));

    if (response.statusCode == 200) {
      return _parseDynamicJson(response.body);
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }

  Stream<String> runSparkJobStream(String sql, String targetTable) async* {
    final url = Uri.parse('$baseUrl/v1/spark');

    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({'sql': sql, 'hbaseTable': targetTable,});

    try {
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        yield* response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
      } else {
        yield '❌ Error del servidor: ${response.statusCode}';
      }
    } catch (e) {
      yield '=== [MARIPOSA-SPARK-STREAM-ERROR] ===: $e';
    }
  }

  /// Procesa el JSON dinámico sin nombres de columnas fijos
  List<MariposaDataRow> _parseDynamicJson(String jsonString) {
    final List<dynamic> decodedJson = jsonDecode(jsonString);

    // Convertimos cada objeto del JSON en un MariposaDataRow genérico
    return decodedJson
        .map((item) => MariposaDataRow.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
