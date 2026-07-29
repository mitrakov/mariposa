import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mariposa/barchart.dart';
import 'package:mariposa/chartdata.dart';
import 'package:mariposa/mariposapage2.dart';
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
      home: const MariposaScrollableChart(),
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
      {"rowkey":"Moscow",         "Men": 60, "Women": 40},
      {"rowkey":"St. Petersburg", "Men": 58, "Women": 42},
      {"rowkey":"Novgorod",       "Men": 55, "Women": 45},
      {"rowkey":"Samara",         "Men": 50, "Women": 50}
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
                //BarChart(dataList: data),   // from fl_chart.dart
              ],
            ),
          );
        },
      ),
    );
  }
}
