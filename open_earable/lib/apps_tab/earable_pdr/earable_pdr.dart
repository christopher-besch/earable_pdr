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
import 'package:flutter_compass/flutter_compass.dart';

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
  late StreamSubscription<BarometerEvent> _phoneBarometerSubscription;
  late StreamSubscription<StepCount> _stepCountSubscription;
  late StreamSubscription<PedestrianStatus> _pedestrianStateSubscription;
  late StreamSubscription<CompassEvent> _compassSubscription;

  static const int _pointsToRemember = 10000000000;
  List<DataPoint> _dataPoints = [];

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

    if (widget.openEarable.bleManager.connected) {
      print("connected to earable");
      OpenEarableSensorConfig config =
          OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
      widget.openEarable.sensorManager.writeSensorConfig(config);
      _earableIMUSubscription = widget.openEarable.sensorManager
          .subscribeToSensorData(0)
          .listen((data) {
        _kalmanFilter.correctEarableCompass(
          // data["EULER"]["YAW"],
          data["EULER"]["ROLL"],
          data["EULER"]["PITCH"],
          data["MAG"]["X"],
          data["MAG"]["Y"],
          data["MAG"]["Z"],
        );
      });
    } else {
      print("failed to connect to earable");
    }

    // TODO: handle error
    _phoneBarometerSubscription = barometerEventStream().listen((event) {
      _kalmanFilter.correctBarometer(event.pressure);
    });

    _checkLocationWhenInUsePermission().then((granted) {
      if (!granted) {
        print("TODO: this is bad");
      }
      print("lets go");

      // TODO: handle error
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading != null) {
          _kalmanFilter.correctPhoneCompass(
            event.heading! * pi / 180,
            event.accuracy! * pi / 180,
          );
        }
      });
    });

    _checkActivityRecognitionPermission().then((granted) {
      if (!granted) {
        print("TODO: this is bad");
      }
      print("lets go");

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
        _kalmanFilter.setIsWalking(event.status == 'walking');
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
    _phoneBarometerSubscription.cancel();
    _stepCountSubscription.cancel();
    _pedestrianStateSubscription.cancel();
    _compassSubscription.cancel();
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
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: ScatterChart(
                    ScatterChartData(
                      scatterSpots: toScatterSpots(_dataPoints),
                    ),
                    // duration: Duration(milliseconds: 150), // Optional
                    // curve: Curves.linear, // Optional
                  ),
                  // child: LineChart(
                  //   LineChartData(
                  //     // minX: 0,
                  //     // maxX: 100,
                  //     // minY: -1,
                  //     // maxY: 1,
                  //     // lineTouchData: const LineTouchData(enabled: false),
                  //     // clipData: const FlClipData.all(),
                  //     // gridData: const FlGridData(
                  //     //   show: true,
                  //     //   drawVerticalLine: false,
                  //     // ),
                  //     // borderData: FlBorderData(show: false),
                  //     lineBarsData: toLineBarsData(_dataPoints),
                  //     // titlesData: const FlTitlesData(
                  //     //   show: false,
                  //     // ),
                  //   ),
                  // ),
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

  Future<bool> _checkLocationWhenInUsePermission() async {
    bool granted = await Permission.locationWhenInUse.isGranted;

    if (!granted) {
      granted = await Permission.locationWhenInUse.request() ==
          PermissionStatus.granted;
    }

    return granted;
  }
}
