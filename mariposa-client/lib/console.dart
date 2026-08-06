import 'package:flutter/material.dart';
import 'package:mariposa/api.dart';

class SqlConsolePage extends StatefulWidget {
  final String? initialTable;
  SqlConsolePage(this.initialTable);

  @override
  State<SqlConsolePage> createState() => _SqlConsolePageState();
}

class _SqlConsolePageState extends State<SqlConsolePage> {
  static final TextEditingController _sqlController = TextEditingController(text: "SELECT...;");
  static final TextEditingController _tableController = TextEditingController(text: "");

  String _logBuffer = "";
  bool _isExecuting = false;
  final ScrollController _scrollController = ScrollController();
  final MariposaApiClient _apiClient = MariposaApiClient();

  void _executeSparkJob() {
    setState(() {
      _logBuffer = "🚀 Iniciando Spark Job en el cluster Mariposa...\n";
      _isExecuting = true;
    });

    _apiClient.runSparkJobStream(
      _sqlController.text.trim(),
      _tableController.text.trim(),
    ).listen((line) {
        if (!mounted) return;
        setState(() {
          _logBuffer += "$line\n";
        });

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
  void initState() {
    super.initState();
    _tableController.text = widget.initialTable ?? "default:table";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mariposa Spark Console')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _sqlController,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Hive SQL Query'),
            ),
            const SizedBox(height: 10),
            Row(spacing: 10,
              children: [
                Expanded(child: TextField(
                  controller: _tableController,
                  decoration: const InputDecoration(labelText: 'HBase Target Table'),
                )),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _isExecuting ? null : _executeSparkJob,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('RUN SPARK JOB'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 10),
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
                      color: Colors.greenAccent,
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
