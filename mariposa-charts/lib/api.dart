import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mariposa/dataframe.dart';

class MariposaApiClient {
  final String baseUrl;

  MariposaApiClient({this.baseUrl = 'http://192.168.1.49:7012'});

  /// Recupera los datos de HBase. Si falla, intenta cargar la última copia guardada.
  Future<List<CityDemographics>> fetchDemographics(String namespace, String table) async {
    final url = Uri.parse('$baseUrl/v1/hbase/$namespace/$table');
    final String cacheKey = 'CACHE_${namespace}_$table'; // Llave única por tabla

    try {
      // 1. Intentar la petición HTTP al servidor Pekko
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // 💡 ÉXITO: Guardamos una copia en el almacenamiento local antes de retornar
        _saveToCache(cacheKey, response.body);

        return _parseJson(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('=== [MARIPOSA-NETWORK-ERROR] ===: $e');
      print('--- Attempting to load from local fallback... ---');

      // 2. FALLO DE CONEXIÓN: Intentamos recuperar los datos del caché
      final String? cachedData = await _loadFromCache(cacheKey);

      if (cachedData != null) {
        print('✅ Fallback successful: Using last known data for $table');
        return _parseJson(cachedData);
      } else throw Exception('No connection to Mariposa Cluster and no offline data found.');
    }
  }

  // 💡 Función auxiliar para parsear el JSON
  List<CityDemographics> _parseJson(String jsonString) {
    final List<dynamic> decodedJson = jsonDecode(jsonString);
    return decodedJson
        .map((item) => CityDemographics.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // 💡 Guardar JSON en el disco del iPhone/Android
  Future<void> _saveToCache(String key, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json);
  }

  // 💡 Recuperar JSON del disco
  Future<String?> _loadFromCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}
