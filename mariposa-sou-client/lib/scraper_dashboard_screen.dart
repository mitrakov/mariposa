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
  final TextEditingController _newHostController = TextEditingController(text: '192.168.1.49');
  final TextEditingController _newScraperController = TextEditingController();

  // 🔥 El cambio clave: Ahora es una lista de objetos distribuidos complejos
  List<DistributedScript> _scrapers = [];

  // Mapeamos los estados usando la clave única combinada '$host/$id'
  Map<String, ScraperStatus> _statuses = {};
  Timer? _pollingTimer;
  String _consoleLogs = 'Selecciona un scraper para ver sus logs...';
  DistributedScript? _selectedScriptForLogs;

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
    _newHostController.dispose();
    _newScraperController.dispose();
    super.dispose();
  }

  // --- PERSISTENCIA CON SHARED PREFERENCES ---
  Future<void> _loadScrapersList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedJsonList = prefs.getStringList(
      'mariposa_distributed_scrapers',
    );

    if (savedJsonList != null) {
      setState(() {
        _scrapers = savedJsonList
            .map((item) => DistributedScript.fromJson(item))
            .toList();
      });
    } else {
      // Valores por defecto iniciales para pruebas en tu cluster casero
      setState(() {
        _scrapers = [];
      });
    }
    _updateAllStatuses();
  }

  Future<void> _saveScrapersList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList = _scrapers
        .map((item) => item.toJson())
        .toList();
    await prefs.setStringList('mariposa_distributed_scrapers', jsonList);
  }

  // --- CONTROL LÓGICO DE ACCIONES DISTRIBUIDAS ---
  Future<void> _updateAllStatuses() async {
    for (var script in _scrapers) {
      try {
        // Cada iteración consulta de forma independiente al host configurado en su modelo
        final status = await _httpService.checkStatus(script.host, script.id);
        setState(() {
          _statuses[script.uniqueKey] = status;
        });

        // Si este script en específico está seleccionado, refresca sus logs desde su propio servidor
        if (_selectedScriptForLogs?.uniqueKey == script.uniqueKey) {
          _fetchLogs(script);
        }
      } catch (_) {
        // En caso de caída del servidor Pekko de ese nodo, no detenemos el bucle del resto del clúster
      }
    }
  }

  Future<void> _fetchLogs(DistributedScript script) async {
    try {
      final logs = await _httpService.getLogs(script.host, script.id);
      setState(() {
        _consoleLogs = logs;
      });
    } catch (e) {
      setState(() {
        _consoleLogs = 'Error al recuperar logs de ${script.host}: $e';
      });
    }
  }

  Future<void> _toggleScraper(DistributedScript script, bool isRunning) async {
    try {
      if (isRunning) {
        await _httpService.stopScraper(script.host, script.id);
        _showSnackBar(
          'Se envió SIGTERM a ${script.id} en el nodo ${script.host}',
          Colors.orange,
        );
      } else {
        await _httpService.startScraper(script.host, script.id);
        _showSnackBar(
          'Scraper ${script.id} iniciado en ${script.host}',
          Colors.green,
        );
      }
      _updateAllStatuses();
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
    }
  }

  void _addScraper() {
    final name = _newScraperController.text.trim();
    final host = _newHostController.text.trim();

    if (name.isNotEmpty && host.isNotEmpty) {
      final newScript = DistributedScript(id: name, host: host);

      // Validar duplicados exactos en el mismo nodo
      final exists = _scrapers.any((s) => s.uniqueKey == newScript.uniqueKey);
      if (!exists) {
        setState(() {
          _scrapers.add(newScript);
          _newScraperController.clear();
        });
        _saveScrapersList();
        _updateAllStatuses();
      } else {
        _showSnackBar(
          'Este script ya esta registrado en el nodo $host',
          Colors.red,
        );
      }
    }
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦋 Mariposa Cluster Distributed Controller'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Panel de Inserción: Script + Host Destino
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _newScraperController,
                    decoration: const InputDecoration(
                      labelText: 'Script name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _newHostController,
                    decoration: const InputDecoration(
                      labelText: 'IP o Host',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addScraper,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // Lista de Azulejos (Tiles) de control
          Expanded(
            child: ListView.builder(
              itemCount: _scrapers.length,
              itemBuilder: (context, index) {
                final script = _scrapers[index];
                final status = _statuses[script.uniqueKey];
                final isRunning = status?.isRunning ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: isRunning ? Colors.green[50] : Colors.grey[100],
                  child: ListTile(
                    dense: true,  
                    contentPadding: EdgeInsets.zero,  
                    minVerticalPadding: 0,  
                    minTileHeight: 0,
                    onLongPress: () => _deleteScraper(script),
                    leading: Icon(
                      isRunning ? Icons.play_circle_fill : Icons.stop_circle,
                      color: isRunning ? Colors.green : Colors.grey,
                      size: 36,
                    ),
                    title: Text(
                      '${script.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // 🔥 UI Mejorada: Muestra claramente a qué IP/Nodo pertenece este proceso
                    subtitle: Text(
                      isRunning
                          ? 'Nodo: ${script.host}\nPID: ${status?.pid} • Uptime: ${status?.uptimeSeconds}s'
                          : 'Nodo: ${script.host} • Estado: DETENIDO',
                    ),
                    isThreeLine: isRunning,
                    trailing: SizedBox(
                      width: isRunning ? 140 : 96,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.terminal,
                              color: Colors.blueGrey,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedScriptForLogs = script;
                              });
                              _fetchLogs(script);
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              isRunning ? Icons.stop : Icons.play_arrow,
                              color: isRunning ? Colors.orange : Colors.green,
                            ),
                            onPressed: () => _toggleScraper(script, isRunning),
                          ),
                        ],
                      ),
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
                  _selectedScriptForLogs == null
                      ? _consoleLogs
                      : '📝 [LOGS ${_selectedScriptForLogs!.id} en ${_selectedScriptForLogs!.host}]\n\n$_consoleLogs',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'Courier',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future _deleteScraper(DistributedScript script) async {
    final isRunning = _statuses[script.uniqueKey]?.isRunning ?? false;
    if (isRunning) {
      _showSnackBar(
        'No puedes eliminar este script mientras se ejecute en ${script.host}.',
        Colors.red,
      );
      return;
    }
    final bool? confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('⚠️ ¿Eliminar Scraper?'),
          content: Text('¿Estás seguro de que deseas eliminar "${script.id}" de tu panel de control Mariposa?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      setState(() {
        _scrapers.removeWhere((s) => s.uniqueKey == script.uniqueKey);
        _statuses.remove(script.uniqueKey);
        if (_selectedScriptForLogs?.uniqueKey == script.uniqueKey) {
          _selectedScriptForLogs = null;
          _consoleLogs = 'Selecciona un scraper para ver sus logs...';
        }
      });
      await _saveScrapersList();
      _showSnackBar('Script removido de la lista.', Colors.blueGrey);
    }
  }
}
