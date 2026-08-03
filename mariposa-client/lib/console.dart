import 'package:flutter/material.dart';
import 'package:mariposa/api.dart';

class SqlConsolePage extends StatefulWidget {
  const SqlConsolePage({super.key});

  @override
  State<SqlConsolePage> createState() => _SqlConsolePageState();
}

class _SqlConsolePageState extends State<SqlConsolePage> {
  final TextEditingController _sqlController   = TextEditingController(text: "SELECT...;",);
  final TextEditingController _tableController = TextEditingController(text: "default:table");

  // 💡 El buffer donde acumularemos los logs de Spark
  String _logBuffer = "";
  bool _isExecuting = false;
  final ScrollController _scrollController = ScrollController();
  final MariposaApiClient _apiClient = MariposaApiClient();

  // 🚀 Función para disparar el streaming
  void _executeSparkJob() {
    setState(() {
      _logBuffer = "🚀 Iniciando Spark Job en el cluster Mariposa...\n";
      _isExecuting = true;
    });

    // 💡 Conectamos con el Dart Stream de nuestra API
    _apiClient.runSparkJobStream(
      _sqlController.text.trim(),
      _tableController.text.trim(),
    ).listen(
          (line) {
            if (!mounted) return;
        setState(() {
          _logBuffer += "$line\n";
        });
            // 💡 Auto-scroll inteligente: solo baja si hay contenido nuevo
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
      },
      onDone: () {
        if (mounted) setState(() => _isExecuting = false);
      },
      onError: (err) => setState(() {
        _logBuffer += "❌ ERROR: $err\n";
        _isExecuting = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚡ Mariposa Spark Console')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            //  Entrada de Tabla Destino
            TextField(
              controller: _tableController,
              decoration: const InputDecoration(labelText: 'HBase Target Table'),
            ),
            const SizedBox(height: 10),
            //  Editor de SQL
            TextField(
              controller: _sqlController,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Hive SQL Query'),
            ),
            const SizedBox(height: 10),
            //  Botón de ejecución
            ElevatedButton.icon(
              onPressed: _isExecuting ? null : _executeSparkJob,
              icon: const Icon(Icons.play_arrow),
              label: const Text('RUN SPARK JOB'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            //  LA CONSOLA: Donde los Streams cobran vida
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _logBuffer,
                    style: const TextStyle(
                      color: Colors.greenAccent, // Estilo "Matrix" / Terminal
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
