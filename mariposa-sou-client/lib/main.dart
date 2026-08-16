import 'package:flutter/material.dart';
import 'scraper_dashboard_screen.dart';

void main() {
  runApp(const MariposaApp());
}

class MariposaApp extends StatelessWidget {
  const MariposaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mariposa SOU Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const ScraperDashboardScreen(),
    );
  }
}
