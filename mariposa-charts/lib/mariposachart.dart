import 'package:flutter/material.dart';
import 'package:mariposa/dataframe.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class MariposaScrollableChart extends StatelessWidget {
  final List<CityDemographics> chartData;

  const MariposaScrollableChart(this.chartData);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mariposa Core - Analytics'),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SfCartesianChart(
          backgroundColor: const Color(0xFF121212),
          title: ChartTitle(
              text: 'Demographics by City (%)',
              textStyle: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)
          ),
          legend: Legend(
              isVisible: true,
              position: LegendPosition.top,
              textStyle: const TextStyle(color: Colors.white)
          ),
          tooltipBehavior: TooltipBehavior(enable: true),

          // 💡 CONTROL DE SCROLL NATIVO: Habilita el paneo (arrastrar con el dedo)
          zoomPanBehavior: ZoomPanBehavior(
            enablePanning: true, // Permite deslizar la gráfica con el dedo/mouse
            zoomMode: ZoomMode.y, // Restringe el scroll únicamente al eje de las ciudades
          ),

          // EJE X (Eje vertical de las categorías)
          primaryXAxis: CategoryAxis(
            isInversed: true,
            labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            majorGridLines: const MajorGridLines(width: 0),

            //initialVisibleMaximum: 5,
            initialVisibleMaximum: chartData.length > 5 ? 5 : (chartData.length - 1).toDouble(),
            // 💡 MAGIA DEL SCROLL: Define cuántas ciudades se ven en pantalla al mismo tiempo
            // Al poner 4, la app mostrará las primeras 4 ciudades de forma perfecta y cómoda,
            // y las otras 8 quedarán ocultas en el scroll. ¡Ideal para la pantalla de un celular!
            //autoScrollingDelta: 8,
            autoScrollingMode: AutoScrollingMode.start,
          ),

          // EJE Y (Eje horizontal de los porcentajes)
          primaryYAxis: NumericAxis(
            minimum: 0,
            maximum: 100,
            interval: 20,
            labelFormat: '{value}%',
            labelStyle: const TextStyle(color: Colors.white54),
            majorGridLines: MajorGridLines(color: Colors.white.withOpacity(0.05)),
          ),

          series: <CartesianSeries<CityDemographics, String>>[
            BarSeries<CityDemographics, String>(
              name: 'Men',
              dataSource: chartData,
              xValueMapper: (CityDemographics data, _) => data.city,
              yValueMapper: (CityDemographics data, _) => data.men,
              color: const Color(0xFF1E88E5),
              dataLabelSettings: const DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ),
            BarSeries<CityDemographics, String>(
              name: 'Women',
              dataSource: chartData,
              xValueMapper: (CityDemographics data, _) => data.city,
              yValueMapper: (CityDemographics data, _) => data.women,
              color: const Color(0xFFE91E63),
              dataLabelSettings: const DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        ),
      ),
    );
  }
}
