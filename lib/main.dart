import 'dart:math';
import 'package:flutter/material.dart';
import 'package:inertial_pde/chart.dart';
import 'package:material_charts/material_charts.dart';

import 'kalman_filter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      debugShowCheckedModeBanner: false,
      home: PDRHomepage(),
    );
  }
}

class PDRHomepage extends StatefulWidget {
  const PDRHomepage({super.key});

  @override
  State<PDRHomepage> createState() => _PDRHomepageState();
}

class _PDRHomepageState extends State<PDRHomepage> {
  late KalmanFilter _kalmanFilter;
  static const int _pointsToRemember = 100;
  List<DataPoint> _dataPoints = [];

  final _chartStyle = MultiLineChartStyle(
    backgroundColor: Colors.white,
    colors: [Colors.blue, Colors.green, Colors.red],
    smoothLines: false,
    showPoints: false,
    // tooltipStyle: const MultiLineTooltipStyle(
    //   threshold: 20,
    // ),
    forceYAxisFromZero: false,
    // crosshair: CrosshairConfig(
    //   enabled: true,
    //   lineColor: Colors.grey.withOpacity(0.5),
    // ),
  );

  @override
  void initState() {
    super.initState();
    _kalmanFilter = KalmanFilter()
      ..stream.listen((dataPoint) {
        setState(() {
          _dataPoints.add(dataPoint);
          _dataPoints = _dataPoints
              .sublist(max(0, _dataPoints.length - _pointsToRemember));
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PDR'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'PDR',
              style: TextStyle(fontSize: 20),
            ),
            if (_dataPoints.isNotEmpty)
              MultiLineChart(
                series: toChartSeries(_dataPoints),
                style: _chartStyle,
                height: 500,
                width: 300,
                enableZoom: false,
                enablePan: false,
              )
            else
              Text('No Data', style: TextStyle(fontSize: 20))
          ],
        ),
      ),
    );
  }
}
