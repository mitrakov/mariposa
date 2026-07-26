import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mariposa/chartdata.dart';

class BeautifulPieChart extends StatelessWidget {
  final List<ChartData> dataList;

  const BeautifulPieChart({super.key, required this.dataList});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: PieChart(
        PieChartData(
          sectionsSpace: 4, // Modern spacing between slices
          centerSpaceRadius: 50, // Turns it into a sleek donut chart
          sections: dataList.map((data) {
            return PieChartSectionData(
              color: Color(data.colorHex),
              value: data.value,
              title: '${data.value}%',
              radius: 60, // Width of the ring
              titleStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
