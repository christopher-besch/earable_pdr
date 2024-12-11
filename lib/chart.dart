import 'package:flutter/material.dart';
import 'package:material_charts/material_charts.dart';

import 'kalman_filter.dart';

List<ChartSeries> toChartSeries(List<DataPoint> dataPoints) {
  return [
    ChartSeries(
      name: 'Accelleration x',
      dataPoints: dataPoints.map((dataPoint) {
        print('a');
        print(dataPoint.acceleration);
        return ChartDataPoint(value: dataPoint.acceleration[0]);
      }).toList(),
      color: Color.fromRGBO(116, 46, 149, 1),
    ),
    ChartSeries(
      name: 'Accelleration y',
      dataPoints: dataPoints.map((dataPoint) {
        print('b');
        print(dataPoint.acceleration);
        return ChartDataPoint(value: dataPoint.acceleration[1]);
      }).toList(),
      color: Color.fromRGBO(49, 46, 149, 1),
    ),
    ChartSeries(
      name: 'Accelleration z',
      dataPoints: dataPoints.map((dataPoint) {
        print('c');
        print(dataPoint.acceleration);
        return ChartDataPoint(value: dataPoint.acceleration[2]);
      }).toList(),
      color: Color.fromRGBO(116, 46, 49, 1),
    ),
  ];
}
