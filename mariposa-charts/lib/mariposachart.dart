import 'package:flutter/material.dart';
import 'package:mariposa/dataframe.dart'; // Tu modelo CityDemographics
import 'package:syncfusion_flutter_charts/charts.dart';

class MariposaScrollableChart extends StatelessWidget {
  final List<CityDemographics> chartData;

  const MariposaScrollableChart(this.chartData);

  @override
  Widget build(BuildContext context) {
    // 💡 PASO 1: Calcular una altura fija y cómoda por cada ciudad (ej: 70 pixeles)
    // Esto asegura que la gráfica crezca de forma proporcional y las barras nunca se aplasten
    final double itemHeight = 70.0;
    final double chartHeight = chartData.length * itemHeight + 100.0; // +100 para headers/leyenda

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Mariposa Core - Analytics'),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
      ),
      // 💡 PASO 2: Envolver todo en un scroll nativo que captura el trackpad de macOS a la perfección
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(), // Efecto elástico hermoso de Apple iOS/macOS
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 💡 Contenedor con altura dinámica calculada en memoria
            SizedBox(
              height: chartHeight,
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

                // 💡 REMOVIDO: Ya no necesitamos zoomPanBehavior de Syncfusion,
                // porque el scroll completo lo maneja el SingleChildScrollView de Flutter.

                // EJE X (Eje vertical de las categorías)
                primaryXAxis: CategoryAxis(
                  isInversed: true,
                  labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  majorGridLines: const MajorGridLines(width: 0),
                  // 💡 REMOVIDO: visibleMaximum ya no es necesario porque la gráfica
                  // se dibuja completa en su contenedor y el scroll corta la pantalla.
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
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
