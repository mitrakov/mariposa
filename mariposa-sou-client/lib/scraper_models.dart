import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class ScraperStatus {
  final int pid;
  final String status; // "RUNNING" o "STOPPED"
  final String script;
  final String logFile;
  final int uptimeSeconds;

  // Constructor constante para máxima optimización de memoria (Inmutable)
  const ScraperStatus({
    required this.pid,
    required this.status,
    required this.script,
    required this.logFile,
    required this.uptimeSeconds,
  });

  // Constructor de fábrica: El equivalente al método apply() del companion object en Scala
  factory ScraperStatus.fromJson(Map<String, dynamic> json) {
    return ScraperStatus(
      pid: (json['pid'] as num?)?.toInt() ?? -1,
      status: (json['status'] as String?)?.toUpperCase() ?? 'STOPPED',
      script: json['script'] as String? ?? 'Desconocido',
      logFile: json['logFile'] as String? ?? 'Sin archivo de log',
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  // Helper útil para saber de un vistazo si el proceso está activo en la UI
  bool get isRunning => status == 'RUNNING';

  // El método copyWith: El equivalente exacto al método .copy() de las case classes de Scala
  ScraperStatus copyWith({
    int? pid,
    String? status,
    String? script,
    String? logFile,
    int? uptimeSeconds,
  }) {
    return ScraperStatus(
      pid: pid ?? this.pid,
      status: status ?? this.status,
      script: script ?? this.script,
      logFile: logFile ?? this.logFile,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
    );
  }

  @override
  String toString() {
    return 'ScraperStatus(pid: $pid, status: $status, uptime: ${uptimeSeconds}s)';
  }
}

@immutable
class ScraperStartResponse {
  final String message;
  final String logFile;

  const ScraperStartResponse({
    required this.message,
    required this.logFile,
  });

  factory ScraperStartResponse.fromJson(Map<String, dynamic> json) {
    return ScraperStartResponse(
      message: json['message'] as String? ?? 'Proceso iniciado.',
      logFile: json['logFile'] as String? ?? '',
    );
  }

  @override
  String toString() => 'ScraperStartResponse(message: $message)';
}

class DistributedScript {
  final String id;
  final String host;

  const DistributedScript({
    required this.id,
    required this.host,
  });

  // Clave única combinada para mapear los estados de forma aislada en la pantalla
  String get uniqueKey => '$host/$id';

  // Conversión a Mapa para SharedPreferences
  Map<String, dynamic> toMap() => {
    'id': id,
    'host': host,
  };

  factory DistributedScript.fromMap(Map<String, dynamic> map) {
    return DistributedScript(
      id: map['id'] as String? ?? '',
      host: map['host'] as String? ?? 'localhost',
    );
  }

  // Métodos estándar para serialización limpia
  String toJson() => json.encode(toMap());
  factory DistributedScript.fromJson(String source) => DistributedScript.fromMap(json.decode(source) as Map<String, dynamic>);
}
