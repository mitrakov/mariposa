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
    // 1. Obtener el nombre original
    String city = json['key'] ?? 'UNKNOWN';

    return CityDemographics(
      city: city.length > 16 ? '${city.substring(0, 15)}...' : city,
      men: double.tryParse(json['men'] ?? '0') ?? 0,
      women: double.tryParse(json['women'] ?? '0') ?? 0,
    );
  }
}
