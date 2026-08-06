import 'package:flutter/material.dart';
import 'package:mariposa/api.dart';
import 'package:mariposa/console.dart';
import 'package:mariposa/mariposachart.dart';

void main() {
  runApp(const MariposaApp());
}

class MariposaApp extends StatelessWidget {
  const MariposaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mariposa Ecosistema',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1F1F1F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
      ),
      home: const ConnectionInputPage(),
    );
  }
}

class ConnectionInputPage extends StatefulWidget {
  const ConnectionInputPage({Key? key}) : super(key: key);

  @override
  State<ConnectionInputPage> createState() => _ConnectionInputPageState();
}

class _ConnectionInputPageState extends State<ConnectionInputPage> {
  final TextEditingController _tableController = TextEditingController(text: 'default:table');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final MariposaApiClient _apiClient = MariposaApiClient();
  bool _isLoading = false;

  // En _fetchAndShowChart, simplifica la lógica:
  void _fetchAndShowChart() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Bajamos los datos genéricos (Gen-3)
      final parts = _tableController.text.trim().split(":");   // std format is "namespace:table"
      final data = await _apiClient.fetchDataMart(parts.length == 2 ? parts.first : "default", parts.last);

      setState(() => _isLoading = false);

      if (data.isEmpty) {
        _showSnackBar('Tabla vacía en HBase');
        return;
      }

      // 💡 Navegamos directamente. El ordenamiento ocurrirá dentro de la gráfica.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => MariposaUniversalChart(data)),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Fallo de conexión: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦋 Mariposa Cluster Gateway'),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SqlConsolePage()),
          );
        },
        label: const Text('SPARK CONSOLE'),
        icon: const Icon(Icons.bolt),
        backgroundColor: const Color(0xFF1E88E5), // Tu azul corporativo
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.hub_outlined, size: 80, color: Color(0xFF1E88E5)),
                const SizedBox(height: 16),
                const Text(
                  'Query HBase via Pekko',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 32),

                TextFormField(
                  controller: _tableController,
                  decoration: const InputDecoration(
                    labelText: 'HBase Table Name',
                    prefixIcon: Icon(Icons.table_chart_outlined, color: Colors.white54),
                  ),
                  validator: (value) => value!.isEmpty ? 'La tabla es obligatoria' : null,
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchAndShowChart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('GENERATE CHART 🚀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE91E63), // Color Fucsia de alerta
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  

  @override
  void dispose() {
    _tableController.dispose();
    super.dispose();
  }
}
