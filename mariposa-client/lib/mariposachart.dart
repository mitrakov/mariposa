import 'package:flutter/material.dart';
import 'package:mariposa/dataframe.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class MariposaUniversalChart extends StatefulWidget {
  final List<MariposaDataRow> initialData;
  const MariposaUniversalChart(this.initialData, {super.key});

  @override
  State<MariposaUniversalChart> createState() => _MariposaUniversalChartState();
}

class _MariposaUniversalChartState extends State<MariposaUniversalChart> {
  late List<MariposaDataRow> _currentData;
  String _activeSort = 'key'; // Orden por defecto

  @override
  void initState() {
    super.initState();
    _currentData = List.from(widget.initialData);
    _sortData('key'); // Orden inicial alfabético
  }

  void _sortData(String column) {
    setState(() {
      _activeSort = column; // 💡 Ahora sí le damos uso para rastrear el estado
      if (column == 'key') {
        _currentData.sort((a, b) => a.key.compareTo(b.key));
      } else {
        _currentData.sort((a, b) {
          final valA = a.metrics[column] ?? 0.0;
          final valB = b.metrics[column] ?? 0.0;
          return valB.compareTo(valA); // Descendente
        });
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('🦋 Mariposa DataMart'),
        backgroundColor: const Color(0xFF1F1F1F),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort rankings',
            onSelected: _sortData, // Tu función de ordenamiento dinámica
            itemBuilder: _buildSortMenuItems,
          )
        ],
      ),
      body: _currentData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _buildChartBody(), // Extraer también el body ayuda a la legibilidad
    );
  }


  List<PopupMenuEntry<String>> _buildSortMenuItems(BuildContext context) {
    // Color para la opción activa vs inactiva
    Color activeColor = const Color(0xFF1E88E5); // Azul Mariposa
    Color inactiveColor = Colors.white54;

    final List<PopupMenuEntry<String>> items = [
      PopupMenuItem<String>(
        value: 'key',
        child: ListTile(
          leading: Icon(
              Icons.label_outline,
              color: _activeSort == 'key' ? activeColor : inactiveColor // 💡 Uso de la variable
          ),
          title: Text(
            'Order by Label (A-Z)',
            style: TextStyle(color: _activeSort == 'key' ? Colors.white : Colors.white),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuDivider(),
    ];

    if (_currentData.isNotEmpty) {
      final metricsKeys = _currentData.first.metrics.keys.toList();
      items.addAll(metricsKeys.map((String metric) {
        bool isSelected = _activeSort == metric; // 💡 Uso de la variable
        return PopupMenuItem<String>(
          value: metric,
          child: ListTile(
            leading: Icon(
                Icons.bar_chart,
                color: isSelected ? activeColor : inactiveColor
            ),
            title: Text(
              'Order by $metric (DESC)',
              style: TextStyle(color: isSelected ? Colors.white : Colors.white70),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        );
      }).toList());
    }

    return items;
  }


  Widget _buildChartBody() {
    // 1. Si no hay datos, mostramos un estado vacío elegante
    if (_currentData.isEmpty) {
      return const Center(
        child: Text('No data found in HBase', style: TextStyle(color: Colors.white54)),
      );
    }

    // 2. Extraer los nombres de las métricas (ej: ["total", "men", "women"])
    final List<String> metricNames = _currentData.first.metrics.keys.toList();

    // 3. Paleta de colores Mariposa (puedes ampliarla si tus tablas tienen muchas columnas)
    final List<Color> palette = [
      const Color(0xFF1E88E5), // Azul
      const Color(0xFFE91E63), // Fucsia
      const Color(0xFF4CAF50), // Verde
      const Color(0xFFFF9800), // Naranja
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // Altura dinámica: 70px por ciudad + espacio para la leyenda
            height: _currentData.length * 70.0 + 120,
            child: SfCartesianChart(
              backgroundColor: Colors.transparent,
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.top,
                textStyle: TextStyle(color: Colors.white, fontSize: 12),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),

              // Eje X: Las etiquetas (Ciudades, Nodos, etc.)
              primaryXAxis: const CategoryAxis(
                isInversed: true,
                labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                majorGridLines: MajorGridLines(width: 0),
              ),

              // Eje Y: Valores numéricos
              primaryYAxis: NumericAxis(
                labelStyle: const TextStyle(color: Colors.white54),
                majorGridLines: MajorGridLines(color: Colors.white.withOpacity(0.05)),
              ),

              // 💡 GENERACIÓN DINÁMICA DE SERIES
              // Mapeamos cada nombre de métrica a una BarSeries de Syncfusion
              series: metricNames.asMap().entries.map((entry) {
                int idx = entry.key;
                String metric = entry.value;

                return BarSeries<MariposaDataRow, String>(
                  name: metric,
                  dataSource: _currentData,
                  xValueMapper: (MariposaDataRow row, _) => row.key,
                  yValueMapper: (MariposaDataRow row, _) => row.metrics[metric],
                  color: palette[idx % palette.length],
                  animationDuration: 1000, // 1 segundo de animación al ordenar
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    textStyle: TextStyle(color: Colors.white, fontSize: 9),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
