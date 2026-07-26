import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mariposa/barchart.dart';
import 'package:mariposa/chartdata.dart';
import 'package:mariposa/piechart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ChartScreen(),
    );
  }
}

class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key});

  // Simulated Apache Pekko JSON fetch
  Future<List<ChartData>> fetchPekkoData() async {
    await Future.delayed(const Duration(seconds: 1)); // Mock network lag

    const jsonString = '''
    [
      {"label": "Apples", "value": 45, "color": "0xFF4CAF50"},
      {"label": "Bananas", "value": 30, "color": "0xFFFFEB3B"},
      {"label": "Oranges", "value": 25, "color": "0xFFFF9800"}
    ]
    ''';

    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((item) => ChartData.fromJson(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pekko Charts')),
      body: FutureBuilder<List<ChartData>>(
        future: fetchPekkoData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('Error loading data'));
          }

          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                const Text('Pie Chart representation:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                BeautifulPieChart(dataList: data),
                const SizedBox(height: 40),
                const Text('Bar Chart representation:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                BeautifulBarChart(dataList: data),
              ],
            ),
          );
        },
      ),
    );
  }
}
