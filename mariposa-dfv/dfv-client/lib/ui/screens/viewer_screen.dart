// lib/ui/screens/viewer_screen.dart
import 'package:flutter/material.dart';
import '../../models/dataframe_response.dart';
import '../../services/api_service.dart';
import '../widgets/data_card.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final List<Map<String, dynamic>> _allRows = [];
  String? _nextRowKey;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMoreData(); // Carga el primer bloque al iniciar
  }

  Future<void> _loadMoreData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      DataFrameResponse response = await ApiService.fetchPage(startRow: _nextRowKey);
      setState(() {
        _nextRowKey = response.nextRowKey;
        // Mapeamos dinámicamente cada fila recibida y la añadimos a la lista
        for (int i = 0; i < response.rows.length; i++) {
          _allRows.add(response.getRowAsMap(i));
        }
        _isLoading = false;
      });
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
      return const Scaffold(body: Center(child: Text("Error al cargar datos de HBase, bro. Check server.")));
    }

    if (_allRows.isEmpty && _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Mariposa DF Album")),
      body: PageView.builder(
        itemCount: _allRows.length + (_nextRowKey != null ? 1 : 0),
        onPageChanged: (index) {
          // Si el usuario llega al final del bloque actual, pedimos el siguiente lote a Pekko
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
