import 'dart:math';
import 'package:flutter/material.dart';
import 'package:open_earable/apps_tab/earable_pdr/chart.dart';
import 'package:ml_linalg/linalg.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:open_earable/ble/ble_controller.dart';
import 'package:open_earable/shared/earable_not_connected_warning.dart';
import 'dart:async';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:pedometer/pedometer.dart';

import 'kalman_filter.dart';

class EarablePDR extends StatefulWidget {
  final OpenEarable openEarable;

  const EarablePDR(this.openEarable, {super.key});

  @override
  State<EarablePDR> createState() => _EarablePDRState();
}

class _EarablePDRState extends State<EarablePDR> {
  late KalmanFilter _kalmanFilter;
  late StreamSubscription _earableIMUSubscription;
  late StreamSubscription<AccelerometerEvent> _phoneAccelerometerSubscription;
  late StreamSubscription<StepCount> _stepCountSubscription;
  late StreamSubscription<PedestrianStatus> _pedestrianStateSubscription;

  static const int _pointsToRemember = 100;
  List<DataPoint> _dataPoints = [];

  @override
  void initState() {
    super.initState();
    _checkActivityRecognitionPermission().then((granted) {
      if (!granted) {
        print("TODO: this is bad");
      }
      print("lets go");

      _kalmanFilter = KalmanFilter()
        ..stream.listen((dataPoint) {
          setState(() {
            _dataPoints.add(dataPoint);
            _dataPoints = _dataPoints
                .sublist(max(0, _dataPoints.length - _pointsToRemember));
          });
        });

      // TODO: use
      // OpenEarableSensorConfig config =
      //     OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
      // widget.openEarable.sensorManager.writeSensorConfig(config);
      // _earableIMUSubscription = widget.openEarable.sensorManager
      //     .subscribeToSensorData(0)
      //     .listen((data) {
      //   double mx = data["MAG"]["X"] as double;
      //   double my = data["MAG"]["Y"] as double;
      //   double mz = data["MAG"]["Z"] as double;

      //   _kalmanFilter.correctMagnetometer(
      //     Vector.fromList([mx, my, mz], dtype: DType.float64),
      //   );
      // });

      // TODO: handle error
      _phoneAccelerometerSubscription =
          accelerometerEventStream().listen((event) {
        _kalmanFilter.correctAcceleration(
          Vector.fromList([event.x, event.y, event.z], dtype: DType.float64),
        );
      });

      // TODO: handle error
      _stepCountSubscription = Pedometer.stepCountStream.listen((event) {
        _kalmanFilter.correctPedometer(
          Vector.fromList([event.steps], dtype: DType.float64),
        );
      })
        ..onError((e) {
          print(e);
        });

      // TODO: handle error
      _pedestrianStateSubscription =
          Pedometer.pedestrianStatusStream.listen((event) {
        if (event.status == 'stopped') {
          _kalmanFilter.correctWalkingStopped();
        }
      })
            ..onError((e) {
              print(e);
            });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _earableIMUSubscription.cancel();
    _phoneAccelerometerSubscription.cancel();
    _stepCountSubscription.cancel();
    _pedestrianStateSubscription.cancel();
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
              AspectRatio(
                aspectRatio: 1.5,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: LineChart(
                    LineChartData(
                      // minX: 0,
                      // maxX: 100,
                      // minY: -1,
                      // maxY: 1,
                      // lineTouchData: const LineTouchData(enabled: false),
                      // clipData: const FlClipData.all(),
                      // gridData: const FlGridData(
                      //   show: true,
                      //   drawVerticalLine: false,
                      // ),
                      // borderData: FlBorderData(show: false),
                      lineBarsData: toLineBarsData(_dataPoints),
                      // titlesData: const FlTitlesData(
                      //   show: false,
                      // ),
                    ),
                  ),
                ),
              )
            else
              Text('No Data', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
    );
  }

  Future<bool> _checkActivityRecognitionPermission() async {
    bool granted = await Permission.activityRecognition.isGranted;

    if (!granted) {
      granted = await Permission.activityRecognition.request() ==
          PermissionStatus.granted;
    }

    return granted;
  }
}
