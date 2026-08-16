import 'package:dio/dio.dart';
import 'scraper_models.dart'; // 👈 Importamos tus nuevos modelos

class ScraperHttpService {
  final Dio _dio;

  ScraperHttpService()
      : _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String _buildUrl(String nodeHost, String endpoint) {
    final cleanHost = nodeHost.trim().replaceAll('http://', '').replaceAll('/', '');
    return 'http://$cleanHost:7013/v1/scraper/$endpoint';
  }

  /// 1) RUN PROCESS -> Ahora devuelve un objeto ScraperStartResponse tipado
  Future<ScraperStartResponse> startScraper(String nodeHost, String scraperId) async {
    try {
      final url = _buildUrl(nodeHost, 'start/$scraperId');
      print(url);
      final response = await _dio.post(url);

      if (response.statusCode == 202 || response.statusCode == 200) {
        return ScraperStartResponse.fromJson(response.data); // 👈 Parsing seguro
      }
      throw Exception('Código inesperado: ${response.statusCode}');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 2) CHECK STATUS -> Ahora devuelve un objeto ScraperStatus tipado
  Future<ScraperStatus> checkStatus(String nodeHost, String scraperId) async {
    try {
      final url = _buildUrl(nodeHost, 'status/$scraperId');
      final response = await _dio.get(url);
      return ScraperStatus.fromJson(response.data); // 👈 Parsing seguro
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 3) RETURN LOGS -> Se mantiene igual (devuelve String crudo)
  Future<String> getLogs(String nodeHost, String scraperId) async {
    try {
      final url = _buildUrl(nodeHost, 'logs/$scraperId');
      final response = await _dio.get<String>(url);
      return response.data ?? 'No hay logs disponibles.';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 4) KILL GRACEFUL (SIGTERM)
  Future<Map<String, dynamic>> stopScraper(String nodeHost, String scraperId) async {
    try {
      final url = _buildUrl(nodeHost, 'stop/$scraperId');
      print(url);
      final response = await _dio.post(url);
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  String _handleDioError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) {
      return 'Error de conexión: El nodo del clúster tardó demasiado en responder.';
    } else if (error.type == DioExceptionType.badResponse) {
      final data = error.response?.data;
      if (data is Map && data.containsKey('error')) {
        return data['error'].toString();
      }
      return 'Error del servidor Pekko: ${error.response?.statusCode}';
    }
    return 'Error de red inesperado: ${error.message}';
  }
}
