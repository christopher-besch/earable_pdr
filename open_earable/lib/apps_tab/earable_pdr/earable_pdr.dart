import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  var _earableOnline = false;
  StreamSubscription<BarometerEvent>? _phoneBarometerSubscription;
  var _phoneBarometerOnline = false;
  StreamSubscription<StepCount>? _stepCountSubscription;
  var _phoneStepCounterOnline = false;
  StreamSubscription<PedestrianStatus>? _pedestrianStateSubscription;
  var _phonePedestrianStateOnline = false;
  StreamSubscription<CompassEvent>? _compassSubscription;
  var _phoneCompassOnline = false;

  final TextEditingController _stepLengthController = TextEditingController();
  final TextEditingController _predictionRateController =
      TextEditingController();
  final TextEditingController _kalmanDataRateController =
      TextEditingController();

  static const int _pointsToRemember = 10000000000;
  List<DataPoint> _dataPoints = [];

  @override
  void initState() {
    super.initState();

    _predictionRateController.text = 0.05.toString();
    _kalmanDataRateController.text = 0.1.toString();
    _stepLengthController.text = 0.82.toString();
  }

  @override
  void dispose() {
    super.dispose();
    stopPdr();
  }

  void startPdr() {
    _dataPoints = [];

    _kalmanFilter = KalmanFilter(
      double.tryParse(_predictionRateController.text)!,
      double.tryParse(_kalmanDataRateController.text)!,
      double.tryParse(_stepLengthController.text)!,
    )..stream.listen((dataPoint) {
        setState(() {
          _dataPoints.add(dataPoint);
          _dataPoints = _dataPoints
              .sublist(max(0, _dataPoints.length - _pointsToRemember));
        });
      });

    // earable //
    if (widget.openEarable.bleManager.connected) {
      print("connected to earable");

      OpenEarableSensorConfig config =
          OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
      widget.openEarable.sensorManager.writeSensorConfig(config);
      _earableIMUSubscription = widget.openEarable.sensorManager
          .subscribeToSensorData(0)
          .listen((data) {
        if (!_earableOnline) {
          print("earable online");
          setState(() {
            _earableOnline = true;
          });
        }

        _kalmanFilter!.correctEarableCompass(
          // data["EULER"]["YAW"],
          data["EULER"]["ROLL"],
          data["EULER"]["PITCH"],
          data["MAG"]["X"],
          data["MAG"]["Y"],
          data["MAG"]["Z"],
        );
      })
        ..onError((e) {
          print("failed to subscribe to earable IMU");
        });
    } else {
      print("earable not connected");
    }

    // phone barometer //
    _phoneBarometerSubscription = barometerEventStream().listen((event) {
      if (!_phoneBarometerOnline) {
        print("phone barometer online");
        setState(() {
          _phoneBarometerOnline = true;
        });
      }
      _kalmanFilter!.correctBarometer(event.pressure);
    })
      ..onError((e) {
        print('failed to subscribe to phone barometer');
        print(e);
      });

    // phone compass //
    _checkLocationWhenInUsePermission().then((granted) {
      if (!granted) {
        print("permission to use phone compass not granted");
        return;
      }

      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading != null) {
          if (!_phoneCompassOnline) {
            print("phone compass online");
            setState(() {
              _phoneCompassOnline = true;
            });
          }

          _kalmanFilter!.correctPhoneCompass(
            event.heading! * pi / 180,
            event.accuracy! * pi / 180,
          );
        }
      })
        ..onError((e) {
          print('failed to subscribe to phone compass');
          print(e);
        });
    });

    // phone pedometer //
    _checkActivityRecognitionPermission().then((granted) {
      if (!granted) {
        print("permission to use phone pedometer not granted");
        return;
      }

      _stepCountSubscription = Pedometer.stepCountStream.listen((event) {
        if (!_phoneStepCounterOnline) {
          print("phone step counter online");
          setState(() {
            _phoneStepCounterOnline = true;
          });
        }

        _kalmanFilter!.correctPedometer(
          Vector.fromList([event.steps], dtype: DType.float64),
        );
      })
        ..onError((e) {
          print('failed to subscribe to phone step counter');
          print(e);
        });

      _pedestrianStateSubscription =
          Pedometer.pedestrianStatusStream.listen((event) {
        if (!_phonePedestrianStateOnline) {
          print("phone pedestrian status online");
          setState(() {
            _phonePedestrianStateOnline = true;
          });
        }

        _kalmanFilter!.setIsWalking(event.status == 'walking');
      })
            ..onError((e) {
              print('failed to subscribe to phone pedestrian status');
              print(e);
            });
    });
  }

  void stopPdr() {
    print('stopping pdr');

    _earableOnline = false;
    _phoneBarometerOnline = false;
    _phoneStepCounterOnline = false;
    _phonePedestrianStateOnline = false;
    _phoneCompassOnline = false;

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
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _predictionRateController,
                          decoration: InputDecoration(
                            labelText: 'Prediction Rate',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[.,0-9]'),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _kalmanDataRateController,
                          decoration: InputDecoration(
                            labelText: 'Data Rate',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[.,0-9]'),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _stepLengthController,
                          decoration: InputDecoration(
                            labelText: 'Step Length',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[.,0-9]'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        OnlineStatusText(
                          isOnline: _earableOnline,
                          subSystemName: 'Earable IMU',
                        ),
                        OnlineStatusText(
                          isOnline: _phoneBarometerOnline,
                          subSystemName: 'Phone Barometer',
                        ),
                        OnlineStatusText(
                          isOnline: _phoneStepCounterOnline,
                          subSystemName: 'Phone Step Counter',
                        ),
                        OnlineStatusText(
                          isOnline: _phonePedestrianStateOnline,
                          subSystemName: 'Phone Pedestrian Status',
                        ),
                        OnlineStatusText(
                          isOnline: _phoneCompassOnline,
                          subSystemName: 'Phone Compass',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PDRMap(dataPoints: _dataPoints),
            PDRPlot(dataPoints: _dataPoints),
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

class OnlineStatusText extends StatelessWidget {
  final _onlineColor = const Color(0xff00ff00);
  final _offlineColor = const Color(0xffff0000);

  final String? subSystemName;
  final bool? isOnline;

  const OnlineStatusText({super.key, this.subSystemName, this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$subSystemName: ',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 20,
          ),
        ),
        Expanded(
          child: Text(
            isOnline! ? 'ONLINE' : 'OFFLINE',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 20,
              color: isOnline! ? _onlineColor : _offlineColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
