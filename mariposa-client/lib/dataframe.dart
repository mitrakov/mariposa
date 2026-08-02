class MariposaDataRow {
  final String key; // La etiqueta (ej: Ciudad, Nodo, Categoría)
  final Map<String, double> metrics; // Todas las demás columnas numéricas

  MariposaDataRow({required this.key, required this.metrics});

  factory MariposaDataRow.fromJson(Map<String, dynamic> json) {
    // 1. Extraemos la llave (asumimos que Pekko la manda como 'key' o usamos la primera)
    String rowKey = json['key'] ?? json.values.first.toString();

    // 2. Filtramos el resto de los campos para convertirlos en métricas
    Map<String, double> values = {};
    json.forEach((k, v) {
      if (k != 'key') {
        // Intentamos parsear todo lo que no sea la llave como un número
        values[k] = double.tryParse(v.toString()) ?? 0.0;
      }
    });

    // 3. Aplicamos tu recorte de 16 caracteres para la UI
    String displayKey = rowKey.length > 16
        ? '${rowKey.substring(0, 13)}...'
        : rowKey;

    return MariposaDataRow(key: displayKey, metrics: values);
  }
}
