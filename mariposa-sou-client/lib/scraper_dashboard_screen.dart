import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scraper_models.dart';
import 'scraper_http_service.dart';

class ScraperDashboardScreen extends StatefulWidget {
  const ScraperDashboardScreen({super.key});

  @override
  State<ScraperDashboardScreen> createState() => _ScraperDashboardScreenState();
}

class _ScraperDashboardScreenState extends State<ScraperDashboardScreen> {
  final ScraperHttpService _httpService = ScraperHttpService();
  final TextEditingController _nodeController = TextEditingController(text: 'localhost');
  final TextEditingController _newScraperController = TextEditingController();

  List<String> _scrapers = [];
  Map<String, ScraperStatus> _statuses = {};
  Timer? _pollingTimer;
  String _consoleLogs = 'Selecciona un scraper para ver sus logs...';
  String? _selectedScraperForLogs;

  @override
  void initState() {
    super.initState();
    _loadScrapersList();
    // Iniciar hilos de consulta automatica cada 4 segundos para actualizar estatus
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _updateAllStatuses());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _nodeController.dispose();
    _newScraperController.dispose();
    super.dispose();
  }

  // --- PERSISTENCIA CON SHARED PREFERENCES ---
  Future<void> _loadScrapersList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedList = prefs.getStringList('mariposa_scrapers');
    if (savedList != null) {
      setState(() {
        _scrapers = savedList;
      });
    }
    _updateAllStatuses();
  }

  Future<void> _saveScrapersList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('mariposa_scrapers', _scrapers);
  }

  // --- CONTROL LOGICO DE ACCIONES ---
  Future<void> _updateAllStatuses() async {
    final host = _nodeController.text.trim();
    if (host.isEmpty) return;

    for (var id in _scrapers) {
      try {
        final status = await _httpService.checkStatus(host, id);
        setState(() {
          _statuses[id] = status;
        });
        // Si el scraper seleccionado esta corriendo, refrescar logs en vivo
        if (id == _selectedScraperForLogs && status.isRunning) {
          _fetchLogs(id);
        }
      } catch (_) {
        // Si falla por desconexion, asumimos STOPPED por seguridad
      }
    }
  }

  Future<void> _fetchLogs(String id) async {
    try {
      final logs = await _httpService.getLogs(_nodeController.text.trim(), id);
      setState(() {
        _consoleLogs = logs;
      });
    } catch (e) {
      setState(() {
        _consoleLogs = 'Error al recuperar logs: $e';
      });
    }
  }

  Future<void> _toggleScraper(String id, bool isRunning) async {
    final host = _nodeController.text.trim();
    try {
      if (isRunning) {
        await _httpService.stopScraper(host, id);
        _showSnackBar('Se envió señal de parada a $id', Colors.orange);
      } else {
        await _httpService.startScraper(host, id);
        _showSnackBar('Scraper $id iniciado con éxito', Colors.green);
      }
      _updateAllStatuses();
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
    }
  }

  void _addScraper() {
    final name = _newScraperController.text.trim();
    if (name.isNotEmpty && !_scrapers.contains(name)) {
      setState(() {
        _scrapers.add(name);
        _newScraperController.clear();
      });
      _saveScrapersList();
      _updateAllStatuses();
    }
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  // --- DISEÑO DE LA INTERFAZ DE USUARIO ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦋 Mariposa Scraper Controller'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Sección de configuración de IP del Nodo
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nodeController,
                    decoration: const InputDecoration(
                      labelText: 'IP or Host',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _updateAllStatuses,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Cluster'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                )
              ],
            ),
          ),
          // Sección para agregar nuevos scrapers a la lista externa
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newScraperController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del script',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _addScraper,
                  icon: const Icon(Icons.add),
                )
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Lista de Azulejos (Tiles) de control
          Expanded(
            child: ListView.builder(
              itemCount: _scrapers.length,
              itemBuilder: (context, index) {
                final id = _scrapers[index];
                final status = _statuses[id];
                final isRunning = status?.isRunning ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: isRunning ? Colors.green[50] : Colors.grey[100],
                  child: ListTile(
                    leading: Icon(
                      isRunning ? Icons.play_circle_fill : Icons.stop_circle,
                      color: isRunning ? Colors.green : Colors.grey,
                      size: 36,
                    ),
                    title: Text('$id', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(isRunning ? 'PID: ${status?.pid} • Uptime: ${status?.uptimeSeconds}s' : 'Estado: DETENIDO'),
                    onLongPress: () => _deleteScraper(id),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.terminal, color: Colors.blueGrey),
                          onPressed: () {
                            setState(() {
                              _selectedScraperForLogs = id;
                            });
                            _fetchLogs(id);
                          },
                        ),
                        IconButton(
                          icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, color: isRunning ? Colors.orange : Colors.green),
                          onPressed: () => _toggleScraper(id, isRunning),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Consola Oscura Integrada de Logs
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _selectedScraperForLogs == null
                      ? _consoleLogs
                      : '📝 [LOGS $_selectedScraperForLogs]\n\n$_consoleLogs',
                  style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Courier', fontSize: 11),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  /// Elimina un scraper de la lista, limpia su estatus y actualiza SharedPreferences.
  Future<void> _deleteScraper(String id) async {
    // 1. Validar si el scraper está corriendo antes de borrarlo
    final isRunning = _statuses[id]?.isRunning ?? false;
    if (isRunning) {
      _showSnackBar('No puedes eliminar "$id" mientras esté ejecutándose. Deténlo primero.', Colors.red);
      return;
    }

    // 2. Mostrar diálogo nativo de confirmación
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('⚠️ ¿Eliminar Scraper?'),
          content: Text('¿Estás seguro de que deseas eliminar "$id" de tu panel de control Mariposa?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // Cancelar
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // Confirmar
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    // 3. Si el usuario confirmó, procedemos al borrado atómico
    if (confirm == true) {
      setState(() {
        _scrapers.remove(id);   // Remover de la lista principal de la UI
        _statuses.remove(id);   // Limpiar su caché de estatus en memoria
        // Si teníamos seleccionados sus logs, limpiamos la consola oscura
        if (_selectedScraperForLogs == id) {
          _selectedScraperForLogs = null;
          _consoleLogs = 'Selecciona un scraper para ver sus logs...';
        }
      });

      // 4. Persistir la lista limpia en el almacenamiento externo
      await _saveScrapersList();
      _showSnackBar('Scraper "$id" eliminado de la lista.', Colors.blueGrey);
    }
  }

}
