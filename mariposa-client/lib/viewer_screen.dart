import 'package:flutter/material.dart';
import 'package:mariposa/datacard.dart';
import 'package:mariposa/dataframe.dart';

class ViewerScreen extends StatefulWidget {
  final DataFrameResponse df;
  const ViewerScreen(this.df);
  
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final List<Map<String, dynamic>> _allRows = [];
  String? _nextRowKey;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMoreData();
  }

  Future<void> _loadMoreData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      DataFrameResponse response = widget.df;
      setState(() {
        _nextRowKey = response.nextRowKey;
        for (int i = 0; i < response.rows.length; i++) {
          _allRows.add(response.getRowAsMap(i));
        }
        _isLoading = false;
      });
    } catch (e) {
      print("ERROR: $e");
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Scaffold(body: Center(child: Text("Error connecting to HBase.")));
    }

    if (_allRows.isEmpty && _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("🦋 Mariposa Dataframe")),
      body: PageView.builder(
        itemCount: _allRows.length + (_nextRowKey != null ? 1 : 0),
        onPageChanged: (index) {
          if (index >= _allRows.length - 2 && _nextRowKey != null) {
            _loadMoreData();
          }
        },
        itemBuilder: (context, index) {
          if (index >= _allRows.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return DataCard(rowData: _allRows[index], index: index);
        },
      ),
    );
  }
}
