import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';

import 'kalman_filter.dart';

class PDRMap extends StatelessWidget {
  final List<DataPoint>? dataPoints;

  late final double _minHeight;
  late final double _maxHeight;

  final _minHeightColor = const Color(0xff00ffff);
  final _maxHeightColor = const Color(0xffff0000);
  final _lowerPercentile = 0.1;
  final _upperPercentile = 0.9;

  PDRMap({super.key, this.dataPoints}) {
    if (dataPoints != null && dataPoints!.isNotEmpty) {
      var heights = dataPoints!.map((dataPoint) {
        return dataPoint.position[2];
      }).toList();
      heights.sort();
      final lowerPercentilePoint = (_lowerPercentile * heights.length)
          .toInt()
          .clamp(0, heights.length - 1);
      final upperPercentilePoint = (_upperPercentile * heights.length)
          .toInt()
          .clamp(0, heights.length - 1);
      _minHeight = heights[lowerPercentilePoint];
      _maxHeight = heights[upperPercentilePoint];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dataPoints == null || dataPoints!.isEmpty) {
      return Center(child: Text('No Data', style: TextStyle(fontSize: 20)));
    }
    return Column(
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: ScatterChart(
                ScatterChartData(
                  scatterSpots: toScatterSpots(dataPoints!),
                  scatterTouchData: ScatterTouchData(enabled: false),
                ),
              ),
            ),
          ),
        ),
        Text(
          'x: ${dataPoints!.last.position[0].toStringAsFixed(2)}m',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'y: ${dataPoints!.last.position[1].toStringAsFixed(2)}m',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'z: ${dataPoints!.last.position[2].toStringAsFixed(2)}m',
          style: TextStyle(
            color: spotColor(dataPoints!.last),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'min_z: ${_minHeight.toStringAsFixed(2)}m',
          style: TextStyle(
            color: _minHeightColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'max_z: ${_maxHeight.toStringAsFixed(2)}m',
          style: TextStyle(
            color: _maxHeightColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  List<ScatterSpot> toScatterSpots(List<DataPoint> dataPoints) {
    return dataPoints.map((dataPoint) {
      return ScatterSpot(
        dataPoint.position[0],
        dataPoint.position[1],
        dotPainter: FlDotCirclePainter(
          color: spotColor(dataPoint),
          radius: 3,
        ),
      );
    }).toList();
  }

  Color spotColor(DataPoint dataPoint) {
    return Color.lerp(
      _minHeightColor,
      _maxHeightColor,
      (dataPoint.position[2] - _minHeight) / (_maxHeight - _minHeight),
    )!;
  }
}

class PDRPlot extends StatelessWidget {
  final _velocityColor = const Color(0xffff0000);
  final _headingColor = const Color(0xff00ff00);

  final List<DataPoint>? dataPoints;

  const PDRPlot({super.key, this.dataPoints});

  @override
  Widget build(BuildContext context) {
    if (dataPoints == null || dataPoints!.isEmpty) {
      return Center(child: Text('No Data', style: TextStyle(fontSize: 20)));
    }
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: LineChart(
              LineChartData(
                lineBarsData: toLineBarsData(dataPoints!),
                lineTouchData: LineTouchData(enabled: false),
              ),
            ),
          ),
        ),
        Text(
          'velocity: ${dataPoints!.last.velocity.toStringAsFixed(2)}m/s',
          style: TextStyle(
            color: _velocityColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'heading: ${(dataPoints!.last.heading / pi * 180).toStringAsFixed(2)}°',
          style: TextStyle(
            color: _headingColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  List<LineChartBarData> toLineBarsData(List<DataPoint> dataPoints) {
    var lineBars = [
      LineChartBarData(
        spots: dataPoints.map((dataPoint) {
          return FlSpot(
            dataPoint.time.inMilliseconds / 1000,
            dataPoint.velocity,
          );
        }).toList(),
        dotData: const FlDotData(
          show: false,
        ),
        barWidth: 1,
        isCurved: false,
        color: _velocityColor,
      ),
      LineChartBarData(
        spots: dataPoints.map((dataPoint) {
          return FlSpot(
            dataPoint.time.inMilliseconds / 1000,
            dataPoint.heading,
          );
        }).toList(),
        dotData: const FlDotData(
          show: false,
        ),
        barWidth: 1,
        isCurved: false,
        color: _headingColor,
      ),
    ];
    return lineBars;
  }
}
