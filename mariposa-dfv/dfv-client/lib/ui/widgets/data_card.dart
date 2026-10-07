import 'package:flutter/material.dart';

class DataCard extends StatelessWidget {
  final Map<String, dynamic> rowData;
  final int index;

  const DataCard({super.key, required this.rowData, required this.index});

  // 💡 FUNCIÓN AUXILIAR: Detecta si un String es un enlace a una imagen web popular
  bool _isImageUrl(String value) {
    final lowerValue = value.toLowerCase();

    // Verifica extensiones clásicas o patrones comunes de URLs de imágenes optimizadas
    return lowerValue.endsWith('.jpg') ||
        lowerValue.endsWith('.jpeg') ||
        lowerValue.endsWith('.png') ||
        lowerValue.endsWith('.webp') ||
        lowerValue.endsWith('.gif') ||
        lowerValue.contains('.jpg?') ||
        lowerValue.contains('.jpeg?') ||
        lowerValue.contains('.png?');
  }

  @override
  Widget build(BuildContext context) {
    // Limpiamos los campos NULL tal como lo acordamos
    final cleanData = Map<String, dynamic>.from(rowData)
      ..removeWhere((key, value) => value == null);

    // 🕵️‍♂️ EXTRAEMOS LA FOTO PRINCIPAL: Buscamos si existe la columna de foto para la portada
    String? mainPhotoUrl;
    final photoKey = cleanData.keys.firstWhere(
          (k) => k.toLowerCase() == 'photo_url' || k.toLowerCase() == 'photo',
      orElse: () => '',
    );

    if (photoKey.isNotEmpty && _isImageUrl(cleanData[photoKey].toString())) {
      mainPhotoUrl = cleanData[photoKey].toString();
      // Opcional: la quitamos de la lista inferior para no duplicar espacio visual
      cleanData.remove(photoKey);
    }

    return Card(
      elevation: 6,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24), // Evita que la foto se salga de las esquinas
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📸 RENDER DE PORTADA: Si detectamos una foto principal, la plantamos arriba con un buen ratio
            if (mainPhotoUrl != null)
              Container(
                width: double.infinity,
                height: 300, // Altura balanceada para pantallas de iPhone
                color: Colors.grey[200],
                child: Image.network(
                  mainPhotoUrl,
                  fit: BoxFit.cover, // Llena el contenedor manteniendo las proporciones
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.amber[50],
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, color: Colors.amber, size: 40),
                          SizedBox(height: 4),
                          Text("Imagen no disponible", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Contenido textual y resto de metadatos
            Expanded(
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
                    const Divider(height: 24),

                    // Cuerpo de la tarjeta con la lista limpia
                    Expanded(
                      child: ListView.separated(
                        itemCount: cleanData.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.black12, height: 16),
                        itemBuilder: (context, i) {
                          final entry = cleanData.entries.elementAt(i);
                          final valueStr = entry.value.toString();
                          final isInlineImage = _isImageUrl(valueStr);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Columna Izquierda: Nombre del campo
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.key.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Columna Derecha: Valor o Imagen embebida
                                Expanded(
                                  flex: 5,
                                  child: isInlineImage
                                      ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      valueStr,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, e, s) => Text(
                                        valueStr,
                                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                                      ),
                                    ),
                                  )
                                      : Text(
                                    valueStr,
                                    textAlign: TextAlign.start,
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
            ),
          ],
        ),
      ),
    );
  }
}
