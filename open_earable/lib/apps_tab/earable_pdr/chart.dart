import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';

import 'kalman_filter.dart';

List<LineChartBarData> toLineBarsData(List<DataPoint> dataPoints) {
  var lineBars = [
    LineChartBarData(
      spots: dataPoints.map((dataPoint) {
        return FlSpot(dataPoint.time.inMilliseconds / 1000, dataPoint.velocity);
      }).toList(),
      dotData: const FlDotData(
        show: false,
      ),
      barWidth: 1,
      isCurved: false,
      color: Color(0xffff0000),
    ),
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
      barWidth: 1,
      isCurved: false,
      color: Color(0xff00ff00),
    ),
  ];
  return lineBars;
}

List<ScatterSpot> toScatterSpots(List<DataPoint> dataPoints) {
  var heights = dataPoints.map((dataPoint) {
    return dataPoint.position[2];
  }).toList();
  heights.sort();
  final lowerPercentilePoint =
      (0.1 * heights.length).toInt().clamp(0, heights.length - 1);
  final upperPercentilePoint =
      (0.9 * heights.length).toInt().clamp(0, heights.length - 1);
  final minHeight = heights[lowerPercentilePoint];
  final maxHeight = heights[upperPercentilePoint];

  final minHeightColor = Color(0xff0000ff);
  final maxHeightColor = Color(0xffff0000);

  return dataPoints.map((dataPoint) {
    return ScatterSpot(
      dataPoint.position[0],
      dataPoint.position[1],
      dotPainter: FlDotCirclePainter(
        color: Color.lerp(
          minHeightColor,
          maxHeightColor,
          (dataPoint.position[2] - minHeight) / (maxHeight - minHeight),
        )!,
        radius: 3,
      ),
    );
  }).toList();
}
