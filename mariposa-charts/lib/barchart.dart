import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mariposa/chartdata.dart';

class BeautifulBarChart extends StatelessWidget {
  final List<ChartData> dataList;

  const BeautifulBarChart({super.key, required this.dataList});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false), // Hide ugly borders
          gridData: const FlGridData(show: false), // Clean look
          barGroups: dataList.asMap().entries.map((entry) {
            int index = entry.key;
            ChartData data = entry.value;

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data.value,
                  color: Color(data.colorHex),
                  width: 22,
                  borderRadius: BorderRadius.circular(6), // Rounded tops
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 100, // Background track effect
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
