import 'package:flutter/material.dart';
import 'package:mariposa/statrow.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class MariposaUniversalChart extends StatefulWidget {
  final List<MariposaStatRow> initialData;
  const MariposaUniversalChart(this.initialData, {super.key});

  @override
  State<MariposaUniversalChart> createState() => _MariposaUniversalChartState();
}

class _MariposaUniversalChartState extends State<MariposaUniversalChart> {
  late List<MariposaStatRow> _currentData;
  String _activeSort = 'key';

  @override
  void initState() {
    super.initState();
    _currentData = List.from(widget.initialData);
    _sortData('key');
  }

  void _sortData(String column) {
    setState(() {
      _activeSort = column;
      if (column == 'key') {
        _currentData.sort((a, b) => a.key.compareTo(b.key));
      } else {
        _currentData.sort((a, b) {
          final valA = a.metrics[column] ?? 0.0;
          final valB = b.metrics[column] ?? 0.0;
          return valB.compareTo(valA);
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
            onSelected: _sortData,
            itemBuilder: _buildSortMenuItems,
          )
        ],
      ),
      body: _currentData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _buildChartBody(),
    );
  }


  List<PopupMenuEntry<String>> _buildSortMenuItems(BuildContext context) {
    Color activeColor = const Color(0xFF1E88E5);
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
        bool isSelected = _activeSort == metric;
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
    if (_currentData.isEmpty) {
      return const Center(
        child: Text('No data found in HBase', style: TextStyle(color: Colors.white54)),
      );
    }

    final List<String> metricNames = _currentData.first.metrics.keys.toList();

    final List<Color> palette = [
      const Color(0xFF1E88E5),
      const Color(0xFFE91E63),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _currentData.length * 70.0 + 120,
            child: SfCartesianChart(
              backgroundColor: Colors.transparent,
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.top,
                textStyle: TextStyle(color: Colors.white, fontSize: 12),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),

              primaryXAxis: const CategoryAxis(
                isInversed: true,
                labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                majorGridLines: MajorGridLines(width: 0),
              ),

              primaryYAxis: NumericAxis(
                labelStyle: const TextStyle(color: Colors.white54),
                majorGridLines: MajorGridLines(color: Colors.white.withOpacity(0.05)),
              ),

              series: metricNames.asMap().entries.map((entry) {
                int idx = entry.key;
                String metric = entry.value;

                return BarSeries<MariposaStatRow, String>(
                  name: metric,
                  dataSource: _currentData,
                  xValueMapper: (MariposaStatRow row, _) => row.key,
                  yValueMapper: (MariposaStatRow row, _) => row.metrics[metric],
                  color: palette[idx % palette.length],
                  animationDuration: 1000, // 1 sec
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
