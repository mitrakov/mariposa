import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class MariposaScrollableChart extends StatelessWidget {
  const MariposaScrollableChart({Key? key}) : super(key: key);

  // 💡 JSON extendido con más ciudades para forzar el comportamiento de scroll
  final List<Map<String, dynamic>> demographicData = const [
    {"rowkey": "Moscow", "Men": 60.0, "Women": 40.0},
    {"rowkey": "St. Petersburg", "Men": 58.0, "Women": 42.0},
    {"rowkey": "V.Novgorod", "Men": 55.0, "Women": 45.0},
    {"rowkey": "Samara", "Men": 50.0, "Women": 50.0},
    {"rowkey": "Kazan", "Men": 52.0, "Women": 48.0},
    {"rowkey": "Novosibirsk", "Men": 54.0, "Women": 46.0},
    {"rowkey": "Yekaterinburg", "Men": 51.0, "Women": 49.0},
    {"rowkey": "Nizhny Novgorod", "Men": 53.0, "Women": 47.0},
    {"rowkey": "Chelyabinsk", "Men": 49.0, "Women": 51.0},
    {"rowkey": "Omsk", "Men": 48.0, "Women": 52.0},
    {"rowkey": "Rostov-on-Don", "Men": 56.0, "Women": 44.0},
    {"rowkey": "Ufa", "Men": 50.0, "Women": 50.0},
  ];

  @override
  Widget build(BuildContext context) {
    final List<_CityDemographics> chartData = demographicData.map((json) {
      return _CityDemographics(
        city: json["rowkey"] as String,
        men: (json["Men"] as num).toDouble(),
        women: (json["Women"] as num).toDouble(),
      );
    }).toList();

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
            // 💡 MAGIA DEL SCROLL: Define cuántas ciudades se ven en pantalla al mismo tiempo
            // Al poner 4, la app mostrará las primeras 4 ciudades de forma perfecta y cómoda,
            // y las otras 8 quedarán ocultas en el scroll. ¡Ideal para la pantalla de un celular!
            autoScrollingDelta: 8,
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

          series: <CartesianSeries<_CityDemographics, String>>[
            BarSeries<_CityDemographics, String>(
              name: 'Men (===)',
              dataSource: chartData,
              xValueMapper: (_CityDemographics data, _) => data.city,
              yValueMapper: (_CityDemographics data, _) => data.men,
              color: const Color(0xFF1E88E5),
              dataLabelSettings: const DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ),
            BarSeries<_CityDemographics, String>(
              name: 'Women (---)',
              dataSource: chartData,
              xValueMapper: (_CityDemographics data, _) => data.city,
              yValueMapper: (_CityDemographics data, _) => data.women,
              color: const Color(0xFFE91E63),
              dataLabelSettings: const DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _CityDemographics {
  final String city;
  final double men;
  final double women;
  _CityDemographics({required this.city, required this.men, required this.women});
}
