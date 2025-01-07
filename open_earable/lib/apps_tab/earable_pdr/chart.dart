import 'package:fl_chart/fl_chart.dart';

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
      // gradient: LinearGradient(
      //   colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
      //   stops: const [0.1, 1.0],
      // ),
      barWidth: 4,
      isCurved: false,
    ),
    // ChartSeries(
    //   name: 'Velocity',
    //   dataPoints: dataPoints.map((dataPoint) {
    //     return ChartDataPoint(value: dataPoint.velocity);
    //   }).toList(),
    //   color: Color.fromRGBO(116, 46, 49, 1),
    // ),
    // ChartSeries(
    //   name: 'Total Steps',
    //   dataPoints: dataPoints.map((dataPoint) {
    //     return ChartDataPoint(value: dataPoint.total_steps);
    //   }).toList(),
    //   color: Color.fromRGBO(116, 46, 149, 1),
    // ),
  ];
  return lineBars;
}
