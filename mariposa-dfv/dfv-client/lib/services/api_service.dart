// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/dataframe_response.dart';

class ApiService {
  static Future<DataFrameResponse> fetchPage({String? startRow}) async {
    final config = appConfigNotifier.value;

    if (config.baseUrl.isEmpty || config.tableName.isEmpty) {
      throw Exception("Configuración incompleta, bro.");
    }

    // ⚡ MOCK DATA SYSTEM: Si escribes "mock" en la IP, usamos estos datos locales de prueba
    if (config.baseUrl.toLowerCase() == 'mock') {
      await Future.delayed(const Duration(milliseconds: 600)); // Simula latencia de red

      // Cambiamos los datos según el startRow (paginación falsa)
      if (startRow == null) {
        return DataFrameResponse.fromJson({
          "tableName": config.tableName,
          "columns": ["id", "timestamp", "user_id", "status", "payload_size", "location"],
          "rows": [
            ["row_001", 1791244800, "usr_99", "CLEAN", 2048, "San Francisco"],
            ["row_002", 1791244860, "usr_102", "ACTIVE", 512, null], // Probando un NULL
            ["row_003", 1791244920, "usr_55", "PROCESSED", 1024, "New York"]
          ],
          "pagination": {"next_row_key": "row_004"}
        });
      } else {
        // Segunda página del stream
        return DataFrameResponse.fromJson({
          "tableName": config.tableName,
          "columns": ["id", "timestamp", "user_id", "status", "payload_size", "location"],
          "rows": [
            ["row_004", 1791245000, "usr_12", "CLEAN", null, "London"], // Otro NULL
            ["row_005", 1791245120, "usr_88", "TERMINATED", 4096, "Tokyo"]
          ],
          "pagination": null // Fin de los datos simulados
        });
      }
    }

    // 🌐 CONEXIÓN REAL: Servidor Scala Pekko HTTP
    String urlString = config.fullUrl;
    if (startRow != null) {
      urlString += "?startRow=$startRow";
    }

    final response = await http.get(Uri.parse(urlString));

    if (response.statusCode == 200) {
      final Map<String, dynamic> decodedJson = jsonDecode(response.body);
      return DataFrameResponse.fromJson(decodedJson);
    } else {
      throw Exception("Error al conectar con Pekko: ${response}");
    }
  }
}
