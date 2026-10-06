// lib/ui/widgets/data_card.dart
import 'package:flutter/material.dart';

class DataCard extends StatelessWidget {
  final Map<String, dynamic> rowData;
  final int index;

  const DataCard({super.key, required this.rowData, required this.index});

  @override
  Widget build(BuildContext context) {
    // 💡 APUNTE 2: Filtramos el mapa para eliminar CUALQUIER entrada que sea null antes de renderizar
    final cleanData = Map<String, dynamic>.from(rowData)
      ..removeWhere((key, value) => value == null);

    return Card(
      elevation: 6,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header de la Tarjeta (Fijo arriba)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Registro #${index + 1}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const Icon(Icons.favorite, color: Colors.pink),
              ],
            ),
            const Divider(height: 32),

            // Cuerpo de la tarjeta con la lista limpia
            Expanded(
              child: ListView.separated(
                itemCount: cleanData.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.black12, height: 16),
                itemBuilder: (context, i) {
                  final entry = cleanData.entries.elementAt(i);

                  // 💡 APUNTE 1: Disposición en dos columnas usando Row + Expanded
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Columna Izquierda: Nombre del campo (Ancho fijo o proporcional)
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.key.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Columna Derecha: Valor del campo alineado a la derecha
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry.value.toString(),
                            textAlign: TextAlign.end, // Alineación limpia a la derecha
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
