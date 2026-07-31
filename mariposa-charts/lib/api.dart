import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mariposa/dataframe.dart';

class MariposaApiClient {
  // 💡 Configura aquí la IP fija de tu Mini-PC maestra ($MASTER_HOST)
  final String baseUrl;

  MariposaApiClient({this.baseUrl = 'http://192.168.1.49:7012'});

  /// Recupera los datos demográficos de HBase de forma asíncrona
  Future<List<CityDemographics>> fetchDemographics(String namespace, String table) async {
    // Construye la URL dinámica usando el formato de tu ruta en Pekko
    final url = Uri.parse('$baseUrl/v1/hbase/$namespace/$table');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print(response.body);
        // 💡 parsear el arreglo puro JSON [{}, {}, {}]
        final List<dynamic> decodedJson = jsonDecode(response.body);

        // Mapear la colección dinámica hacia nuestra lista de objetos inmutables
        return decodedJson
            .map((item) => CityDemographics.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Server error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('=== [MARIPOSA-CLIENT-ERROR] ===: $e');
      rethrow;
    }
  }
}
