import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DataCard extends StatelessWidget {
  final Map<String, dynamic> rowData;
  final int index;

  const DataCard({super.key, required this.rowData, required this.index});

  bool _isUrl(String s) => s.trim().toLowerCase().startsWith('http://') || s.trim().toLowerCase().startsWith('https://');

  Future<void> _handleLaunchUrl(String urlString, BuildContext context) async {
    try {
      final Uri url = Uri.parse(urlString.trim());
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) { debugPrint("Cannot open URL: $e"); }
  }

  bool _isImageUrl(String value) {
    final s = value.toLowerCase();
    return s.endsWith('.jpg') || s.contains('.jpg?') ||
        s.endsWith('.jpeg') || s.contains('.jpeg?') ||
        s.endsWith('.png') || s.contains('.png?') ||
        s.endsWith('.webp') || s.endsWith('.webp?') ||
        s.endsWith('.gif') || s.contains('.gif?');
  }

  @override
  Widget build(BuildContext context) {
    final cleanData = Map<String, dynamic>.from(rowData)
      ..removeWhere((key, value) => value == null);

    String? mainPhotoUrl;
    final photoKey = cleanData.keys.firstWhere(
          (k) => k.toLowerCase() == 'photo_url' || k.toLowerCase() == 'photo',
      orElse: () => '',
    );

    if (photoKey.isNotEmpty && _isImageUrl(cleanData[photoKey].toString())) {
      mainPhotoUrl = cleanData[photoKey].toString();
      cleanData.remove(photoKey);
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: Colors.white70,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Row #${index + 1}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.favorite, color: Colors.grey),
                      ],
                    ),
                    const Divider(height: 8),

                    Expanded(
                      child: ListView.separated(
                        itemCount: cleanData.length + 1,      // +1 because first item is photo box
                        separatorBuilder: (context, index) => const Divider(color: Colors.black12, height: 16),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            if (mainPhotoUrl == null) return const SizedBox.shrink();
                            return Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                initiallyExpanded: false,
                                title: const Text(
                                  "Ver foto adjunta",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey),
                                ),
                                leading: const Icon(Icons.image, size: 20, color: Colors.blueGrey),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(bottom: 12.0),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 300, // photo height
                                    color: Colors.grey[200],
                                    child: Image.network(
                                      mainPhotoUrl,
                                      fit: BoxFit.fitWidth,
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
                                              Text("Image not available", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final entry = cleanData.entries.elementAt(i - 1);
                          var valueStr = entry.value.toString().trim();
                          if (valueStr.startsWith('ArraySeq(') && valueStr.endsWith(')'))
                            valueStr = valueStr.substring(9, valueStr.length - 1);

                          final isInlineImage = _isImageUrl(valueStr);
                          final isClickableUrl = _isUrl(valueStr);

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 2.0),
                                  child: Text(entry.key, overflow: TextOverflow.ellipsis, maxLines: 2,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 6,
                                child: isInlineImage
                                    ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    valueStr,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, e, s) => Text(
                                      valueStr,
                                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                                    ),
                                  ),
                                ) : isClickableUrl ? GestureDetector(
                                  onTap: () => _handleLaunchUrl(valueStr, context),
                                  child: Text(
                                    valueStr,
                                    textAlign: TextAlign.start,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                                    : Text(
                                  valueStr,
                                  textAlign: TextAlign.start,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
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
