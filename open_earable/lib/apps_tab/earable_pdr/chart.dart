import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';

import 'kalman_filter.dart';

List<LineChartBarData> toLineBarsData(List<DataPoint> dataPoints) {
  var lineBars = [
    // LineChartBarData(
    //   spots: dataPoints.map((dataPoint) {
    //     return FlSpot(dataPoint.time.inMilliseconds / 1000, dataPoint.velocity);
    //   }).toList(),
    //   dotData: const FlDotData(
    //     show: false,
    //   ),
    //   // gradient: LinearGradient(
    //   //   colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
    //   //   stops: const [0.1, 1.0],
    //   // ),
    //   barWidth: 4,
    //   isCurved: false,
    // ),
    // LineChartBarData(
    //   spots: dataPoints.map((dataPoint) {
    //     return FlSpot(
    //       dataPoint.time.inMilliseconds / 1000,
    //       dataPoint.position[2],
    //     );
    //   }).toList(),
    //   dotData: const FlDotData(
    //     show: false,
    //   ),
    //   // gradient: LinearGradient(
    //   //   colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
    //   //   stops: const [0.1, 1.0],
    //   // ),
    //   barWidth: 4,
    //   isCurved: false,
    // ),
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
      // gradient: LinearGradient(
      //   colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
      //   stops: const [0.1, 1.0],
      // ),
      barWidth: 4,
      isCurved: false,
    ),
  ];
  return lineBars;
}

List<ScatterSpot> toScatterSpots(List<DataPoint> dataPoints) {
  return dataPoints.map((dataPoint) {
    return ScatterSpot(
      dataPoint.position[0],
      dataPoint.position[1],
      dotPainter: FlDotCirclePainter(
        color: Color(0xffffffff),
        radius: 1,
      ),
    );
  }).toList();
}
