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
  String? _selectedTable;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final MariposaApiClient _apiClient = MariposaApiClient();
  bool _isLoading = false;

  late Future<List<String>> _tablesFuture;

  @override
  void initState() {
    super.initState() ;
    _tablesFuture = _apiClient.fetchHBaseTables();
  }

  void _fetchAndShowChart() async {
    if (!_formKey.currentState!.validate() || _selectedTable == null) return;

    setState(() => _isLoading = true);

    try {
      final parts = _selectedTable!.trim().split(":");
      final data = await _apiClient.fetchDataMart(parts.length == 2 ? parts.first : "default", parts.last);

      setState(() => _isLoading = false);

      if (data.isEmpty) {
        _showSnackBar('Tabla vacía en HBase');
        return;
      }

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
            MaterialPageRoute(builder: (context) => SqlConsolePage(_selectedTable)),
          );
        },
        label: const Text('SPARK CONSOLE'),
        icon: const Icon(Icons.bolt),
        backgroundColor: const Color(0xFF1E88E5),
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

                // 💡 INTEGRACIÓN MAESTRA: FutureBuilder para pintar el catálogo dinámico de HBase
                FutureBuilder<List<String>>(
                  future: _tablesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Mientras Pekko responde, mostramos un dropdown simulado con un spinner discreto
                      return TextFormField(
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Cargando catálogo de HBase...',
                          prefixIcon: SizedBox(
                            width: 20, height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      );
                    } else if (snapshot.hasError) {
                      // Si falla Kerberos o la red, mostramos la alerta visual en el mismo campo
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Error al cargar tablas',
                          prefixIcon: Icon(Icons.error_outline, color: Colors.redAccent),
                        ),
                        items: const [],
                        onChanged: null, // Deshabilitado
                        validator: (_) => 'Verifica la conexión del servidor Pekko',
                      );
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'No se encontraron tablas',
                          prefixIcon: Icon(Icons.warning_amber_outlined, color: Colors.orangeAccent),
                        ),
                        items: const [],
                        onChanged: null,
                      );
                    }

                    // ESTRATEGIA: Si ya hay datos, autoseleccionamos la primera tabla del clúster si el estado está limpio
                    final tables = snapshot.data!;
                    if (_selectedTable == null && tables.isNotEmpty) {
                      _selectedTable = tables.first;
                    }

                    return DropdownButtonFormField<String>(
                      initialValue: _selectedTable,
                      decoration: const InputDecoration(
                        labelText: 'Select HBase Table',
                        prefixIcon: Icon(Icons.table_chart_outlined, color: Colors.white54),
                      ),
                      dropdownColor: const Color(0xFF1F1F1F), // Fondo oscuro para el menú desplegable
                      items: tables.map((String table) {
                        return DropdownMenuItem<String>(
                          value: table,
                          child: Text(table, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: _isLoading ? null : (newValue) {
                        setState(() => _selectedTable = newValue);
                      },
                      validator: (value) => value == null ? 'La tabla es obligatoria' : null,
                    );
                  },
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
        backgroundColor: const Color(0xFFE91E63),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
