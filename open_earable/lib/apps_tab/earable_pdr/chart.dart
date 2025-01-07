import 'package:flutter/material.dart';
import 'package:material_charts/material_charts.dart';

import 'kalman_filter.dart';

List<ChartSeries> toChartSeries(List<DataPoint> dataPoints) {
  var chartSeries = [
    // ChartSeries(
    //   name: 'Position x',
    //   dataPoints: dataPoints.map((dataPoint) {
    //     return ChartDataPoint(value: dataPoint.position[0]);
    //   }).toList(),
    //   color: Color.fromRGBO(116, 46, 149, 1),
    // ),
    // ChartSeries(
    //   name: 'Position y',
    //   dataPoints: dataPoints.map((dataPoint) {
    //     return ChartDataPoint(value: dataPoint.position[1]);
    //   }).toList(),
    //   color: Color.fromRGBO(49, 46, 149, 1),
    // ),
    // ChartSeries(
    //   name: 'Position z',
    //   dataPoints: dataPoints.map((dataPoint) {
    //     return ChartDataPoint(value: dataPoint.position[2]);
    //   }).toList(),
    //   color: Color.fromRGBO(116, 46, 49, 1),
    // ),
    ChartSeries(
      name: 'Velocity',
      dataPoints: dataPoints.map((dataPoint) {
        return ChartDataPoint(value: dataPoint.velocity);
      }).toList(),
      color: Color.fromRGBO(116, 46, 49, 1),
    ),
    ChartSeries(
      name: 'Total Steps',
      dataPoints: dataPoints.map((dataPoint) {
        return ChartDataPoint(value: dataPoint.total_steps);
      }).toList(),
      color: Color.fromRGBO(116, 46, 149, 1),
    ),
  ];
  return chartSeries;
}
