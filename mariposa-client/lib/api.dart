import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mariposa/dataframe.dart';

class MariposaApiClient {
  final String baseUrl;
  static const String _cursorKeyPrefix = "DF_CURSOR_";

  MariposaApiClient({this.baseUrl = 'http://myfeo.fun:7012/v1/hbase'});

  // Métodо auxiliar centralizado para manejar los cursores guardados en el iPhone
  Future<String> _buildUrlWithPersistence(String table) async {
    final prefs = await SharedPreferences.getInstance();
    // Creamos una clave única por tabla para que los cursores no se pisen entre sí
    final String storageKey = "$_cursorKeyPrefix$table";

    String? savedRowKey = prefs.getString(storageKey);
    String url = '$baseUrl/table/$table?limit=10';

    if (savedRowKey != null && savedRowKey.isNotEmpty) {
      url += '&startRow=$savedRowKey';
      print("Found savedRowKey: $savedRowKey");
    } else {
      print("No savedRowKey found...");
    }
    return url;
  }

  Future<void> _saveNextCursor(String table, String? nextRowKey) async {
    final prefs = await SharedPreferences.getInstance();
    final String storageKey = "$_cursorKeyPrefix$table";

    if (nextRowKey != null && nextRowKey.isNotEmpty) {
      await prefs.setString(storageKey, nextRowKey);
      print("Saved RowKey: $nextRowKey");
    } else {
      // Si llegamos al fin real de los datos en HBase, limpiamos la memoria para reiniciar el mazo
      await prefs.remove(storageKey);
      print("RowKey removed");
    }
  }

  // Mantenemos tus otros métodos por compatibilidad hacia atrás del API Client
  Future<List<String>> fetchHBaseTables() async {
    print('$baseUrl/tables');
    final response = await http.get(Uri.parse('$baseUrl/tables'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((table) => table.toString()).toList();
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }

  Future<DataFrameResponse> fetchDataframe(String table) async {
    final String url = await _buildUrlWithPersistence(table);
    print(url);
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final dfResponse = DataFrameResponse.fromJson(data);

      await _saveNextCursor(table, dfResponse.nextRowKey);
      return dfResponse;
    } else throw Exception('Mariposa Server Error: ${response.statusCode}; ${response.body}');
  }
}
