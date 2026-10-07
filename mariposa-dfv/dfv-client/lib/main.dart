// lib/main.dart
import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'ui/screens/viewer_screen.dart';

void main() {
  runApp(const MariposaApp());
}

class MariposaApp extends StatelessWidget {
  const MariposaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mariposa DF Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConfigScreen(),
    );
  }
}

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _urlController = TextEditingController(text: 'http://10.1.1.1');
  final _portController = TextEditingController(text: '6191');
  final _tableController = TextEditingController(text: 'planet:taxi');

  void _connect() {
    if (_urlController.text.isEmpty || _tableController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rellena los campos, hermano!')),
      );
      return;
    }

    // Actualizamos el estado de la configuración global
    appConfigNotifier.value = AppConfig(
      baseUrl: _urlController.text.trim(),
      port: _portController.text.trim(),
      tableName: _tableController.text.trim(),
    );

    // Navegamos al Visor (Álbum de fotos / Swipe View)
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ViewerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.shield_moon_outlined, size: 64, color: Colors.blueAccent),
                    const SizedBox(height: 16),
                    const Text(
                      "Mariposa DF Viewer",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Hadoop/HBase Data Explorer",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Server URL / IP',
                        hintText: "Escribe 'mock' para probar sin servidor",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dns),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.router),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tableController,
                      decoration: const InputDecoration(
                        labelText: 'HBase Table Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.table_chart),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _connect,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Explorar Dataframe 🚀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
