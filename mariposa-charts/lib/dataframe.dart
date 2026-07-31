// 💡 Estructura fuertemente tipada para alimentar las BarSeries de Syncfusion
class CityDemographics {
  final String city;
  final double men;
  final double women;

  const CityDemographics({
    required this.city,
    required this.men,
    required this.women,
  });

  // 💡 Mapeo seguro del JSON dinámico de HBase [Seq[Map[String, String]]]
  factory CityDemographics.fromJson(Map<String, dynamic> json) {
    return CityDemographics(
      // HBase devuelve strings, por lo que usamos num.tryParse para evitar crashes
      city: json['key'] ?? 'UNKNOWN',
      men: double.tryParse(json['men'] ?? '0') ?? 0,
      women: double.tryParse(json['women'] ?? '0') ?? 0,
    );
  }
}
