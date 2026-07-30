import 'package:flutter/material.dart';
import 'package:mariposa/api.dart';
import 'package:mariposa/dataframe.dart';
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
      // 💡 Aplicar Modo Oscuro global de nivel corporativo
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
  // Controladores de texto para capturar los parámetros de HBase
  final TextEditingController _schemaController = TextEditingController(text: 'default');
  final TextEditingController _tableController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Instancia de tu cliente de red apuntando a tus Mini-PCs reales
  final MariposaApiClient _apiClient = MariposaApiClient();

  bool _isLoading = false;

  /// Lanza la petición HTTP asíncrona hacia el backend de Pekko
  void _fetchAndShowChart() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final schema = _schemaController.text.trim();
    final table = _tableController.text.trim();

    try {
      // Interrogar a HBase de forma dinámica
      List<CityDemographics> data = await _apiClient.fetchDemographics(schema, table);

      setState(() => _isLoading = false);

      if (data.isEmpty) {
        _showSnackBar('La tabla especificada está vacía en HBase.');
        return;
      }

      // 💡 Transición limpia hacia el componente visual de Syncfusion pasando los datos reales
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MariposaScrollableChart(data),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Fallo de conexión contra el cluster: ${e.toString()}');
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦋 Mariposa Cluster Gateway'),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        centerTitle: true,
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

                // 1. Campo para el Schema (Namespace)
                TextFormField(
                  controller: _schemaController,
                  decoration: const InputDecoration(
                    labelText: 'HBase Schema / Namespace',
                    prefixIcon: Icon(Icons.folder_open, color: Colors.white54),
                  ),
                  validator: (value) => value!.isEmpty ? 'El schema es obligatorio' : null,
                ),
                const SizedBox(height: 16),

                // 2. Campo para la Tabla
                TextFormField(
                  controller: _tableController,
                  decoration: const InputDecoration(
                    labelText: 'HBase Table Name',
                    prefixIcon: Icon(Icons.table_chart_outlined, color: Colors.white54),
                    hintText: 'ej: users o sensor_data',
                  ),
                  validator: (value) => value!.isEmpty ? 'El nombre de la tabla es obligatorio' : null,
                ),
                const SizedBox(height: 32),

                // 3. Botón de Acción con indicador de carga integrado
                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchAndShowChart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5), // Azul institucional
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : const Text(
                    'GENERATE CHART 🚀',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _schemaController.dispose();
    _tableController.dispose();
    super.dispose();
  }
}
