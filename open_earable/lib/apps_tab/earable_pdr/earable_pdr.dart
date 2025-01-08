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
  var _pdrRunning = false;

  KalmanFilter? _kalmanFilter;
  StreamSubscription? _earableIMUSubscription;
  StreamSubscription<BarometerEvent>? _phoneBarometerSubscription;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStateSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  static const int _pointsToRemember = 10000000000;
  List<DataPoint> _dataPoints = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    stopPdr();
  }

  void startPdr() {
    _dataPoints = [];

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
        _kalmanFilter!.correctEarableCompass(
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
      _kalmanFilter!.correctBarometer(event.pressure);
    });

    _checkLocationWhenInUsePermission().then((granted) {
      if (!granted) {
        print("TODO: this is bad");
      }
      print("lets go");

      // TODO: handle error
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading != null) {
          _kalmanFilter!.correctPhoneCompass(
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
        _kalmanFilter!.correctPedometer(
          Vector.fromList([event.steps], dtype: DType.float64),
        );
      })
        ..onError((e) {
          print(e);
        });

      // TODO: handle error
      _pedestrianStateSubscription =
          Pedometer.pedestrianStatusStream.listen((event) {
        _kalmanFilter!.setIsWalking(event.status == 'walking');
      })
            ..onError((e) {
              print(e);
            });
    });
  }

  void stopPdr() {
    if (_kalmanFilter != null) {
      _kalmanFilter!.cancel();
    }
    if (_earableIMUSubscription != null) {
      _earableIMUSubscription!.cancel();
    }
    if (_phoneBarometerSubscription != null) {
      _phoneBarometerSubscription!.cancel();
    }
    if (_stepCountSubscription != null) {
      _stepCountSubscription!.cancel();
    }
    if (_pedestrianStateSubscription != null) {
      _pedestrianStateSubscription!.cancel();
    }
    if (_compassSubscription != null) {
      _compassSubscription!.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: 0,
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PDR'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(
                icon: Icon(Icons.settings),
              ),
              Tab(
                icon: Icon(Icons.map),
              ),
              Tab(
                icon: Icon(Icons.line_axis),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Pedestrian Dead Reckoning',
                    style: TextStyle(fontSize: 20),
                  ),
                  IconButton(
                    splashRadius: 20,
                    icon: _pdrRunning
                        ? Icon(Icons.pause)
                        : Icon(Icons.play_arrow),
                    onPressed: () {
                      setState(() {
                        _pdrRunning = !_pdrRunning;
                        if (_pdrRunning) {
                          startPdr();
                        } else {
                          stopPdr();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: _dataPoints.isNotEmpty
                  ? ScatterChart(
                      ScatterChartData(
                        scatterSpots: toScatterSpots(_dataPoints),
                      ),
                    )
                  : Text('No Data', style: TextStyle(fontSize: 20)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: _dataPoints.isNotEmpty
                  ? LineChart(
                      LineChartData(
                        lineBarsData: toLineBarsData(_dataPoints),
                      ),
                    )
                  : Text('No Data', style: TextStyle(fontSize: 20)),
            ),
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
