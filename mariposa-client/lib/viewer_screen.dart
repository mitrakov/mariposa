import 'package:flutter/material.dart';
import 'package:mariposa/datacard.dart';
import 'package:mariposa/dataframe.dart';
import 'package:mariposa/api.dart';

class ViewerScreen extends StatefulWidget {
  final DataFrameResponse df;
  final String tableName; // Necesitamos el nombre de la tabla para pedir más datos

  const ViewerScreen(this.df, {required this.tableName});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final List<Map<String, dynamic>> _allRows = [];
  final MariposaApiClient _apiClient = MariposaApiClient();
  String? _nextRowKey;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // Procesamos el mazo inicial que llegó por parámetro desde la pantalla anterior
    _processNewDataBlock(widget.df);
  }

  void _processNewDataBlock(DataFrameResponse response) {
    _nextRowKey = response.nextRowKey;

    // 1. Extraemos las filas del bloque actual
    final List<Map<String, dynamic>> newRows = [];
    for (int i = 0; i < response.rows.length; i++) {
      newRows.add(response.getRowAsMap(i));
    }

    // 2. LA MAGIA: Barajamos localmente las cartas del bloque nuevo antes de concatenarlas
    newRows.shuffle();

    setState(() {
      _allRows.addAll(newRows);
      _isLoading = false;
    });
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || _nextRowKey == null) return;
    setState(() => _isLoading = true);

    try {
      // Pedimos el siguiente mazo usando la función modificada con persistencia interna
      DataFrameResponse response = await _apiClient.fetchDataframe(widget.tableName);
      _processNewDataBlock(response);
    } catch (e) {
      print("ERROR: $e");
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Scaffold(body: Center(child: Text("Error connecting to HBase.")));
    }
    if (_allRows.isEmpty && _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("🦋 Mariposa Dataframe")),
      body: PageView.builder(
        itemCount: _allRows.length + (_nextRowKey != null ? 1 : 0),
        onPageChanged: (index) {
          // Si el usuario se acerca al final del lote actual, disparamos la precarga en segundo plano
          if (index >= _allRows.length - 2 && _nextRowKey != null) {
            _loadMoreData();
          }
        },
        itemBuilder: (context, index) {
          if (index >= _allRows.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return DataCard(rowData: _allRows[index], index: index);
        },
      ),
    );
  }
}
