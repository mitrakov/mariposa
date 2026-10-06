// lib/config/app_config.dart
import 'package:flutter/material.dart';

class AppConfig {
  String baseUrl;
  String port;
  String tableName;

  AppConfig({this.baseUrl = '', this.port = '', this.tableName = ''});

  String get fullUrl => "$baseUrl:$port/api/table/$tableName";
}

// Notificador global para que la UI reaccione cuando el usuario guarde la config
final ValueNotifier<AppConfig> appConfigNotifier = ValueNotifier(AppConfig());
