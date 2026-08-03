import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mariposa/dataframe.dart'; // Asegúrate de que aquí viva MariposaDataRow

class MariposaApiClient {
  final String baseUrl;

  MariposaApiClient({this.baseUrl = 'http://192.168.1.49:7012'});

  /// Recupera cualquier tabla de HBase y la convierte en una estructura de filas dinámica.
  Future<List<MariposaDataRow>> fetchDataMart(String namespace, String table) async {
    final url = Uri.parse('$baseUrl/v1/hbase/$namespace/$table');
    final String cacheKey = 'CACHE_${namespace}_$table';

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Guardamos el JSON crudo (Arreglo de Mapas)
        _saveToCache(cacheKey, response.body);
        return _parseDynamicJson(response.body);
      } else {
        throw Exception('Mariposa Server Error: ${response.statusCode}');
      }
    } catch (e) {
      print('=== [MARIPOSA-NETWORK-ERROR] ===: $e');

      final String? cachedData = await _loadFromCache(cacheKey);
      if (cachedData != null) {
        print('✅ Fallback: Cargando datos históricos de $table');
        return _parseDynamicJson(cachedData);
      } else {
        throw Exception('Sin conexión al clúster y sin datos locales para $table.');
      }
    }
  }

  Stream<String> runSparkJobStream(String sql, String targetTable) async* {
    final url = Uri.parse('$baseUrl/v1/spark');

    // 💡 Preparamos la petición manual para manejar el Stream
    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'sql': sql,
      'hbaseTable': targetTable,
    });

    try {
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        // 💡 Transformamos los bytes entrantes (UTF-8) en líneas de texto
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

  // --- Persistencia Local (SharedPrefs) ---
  Future<void> _saveToCache(String key, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json);
  }

  Future<String?> _loadFromCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}
