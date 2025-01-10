import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'chart.dart';
import 'kalman_filter.dart';

// an app to plot your walked path without GPS
class EarablePDR extends StatefulWidget {
  final OpenEarable openEarable;

  const EarablePDR(this.openEarable, {super.key});

  @override
  State<EarablePDR> createState() => _EarablePDRState();
}

class _EarablePDRState extends State<EarablePDR> {
  // is the Kalman Filter updating the state right now
  var _pdrRunning = false;

  KalmanFilter? _kalmanFilter;

  // the subscriptions of the sensors
  // they are considered online once they have sent at least one point of data
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

  // How many Kalman Filter DataPoints should be displayed?
  static const int _pointsToRemember = 10000000000;
  // the past DataPoints
  // This is stored here and not in the Kalman Filter as the Kalman Filter doesn't need them.
  List<DataPoint> _dataPoints = [];

  @override
  void initState() {
    super.initState();

    // sensible default values
    _predictionRateController.text = 0.05.toString();
    _kalmanDataRateController.text = 0.1.toString();
    _stepLengthController.text = 0.82.toString();
  }

  @override
  void dispose() {
    super.dispose();
    stopPdr();
  }

  // start the Kalman Filter
  void startPdr() {
    _dataPoints = [];

    // create the Kalman Filter
    _kalmanFilter = KalmanFilter(
      double.tryParse(_predictionRateController.text)!,
      double.tryParse(_kalmanDataRateController.text)!,
      double.tryParse(_stepLengthController.text)!,
    )..stream.listen((dataPoint) {
        setState(() {
          // add a new point of data when it arrives
          _dataPoints.add(dataPoint);
          _dataPoints = _dataPoints
              .sublist(max(0, _dataPoints.length - _pointsToRemember));
        });
      });

    // connect to the earable IMU //
    if (widget.openEarable.bleManager.connected) {
      print("connected to earable");

      OpenEarableSensorConfig config =
          OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
      widget.openEarable.sensorManager.writeSensorConfig(config);
      _earableIMUSubscription = widget.openEarable.sensorManager
          .subscribeToSensorData(0)
          .listen((data) {
        // consider the sensor online now
        if (!_earableOnline) {
          print("earable online");
          setState(() {
            _earableOnline = true;
          });
        }

        // Use the sensor reading to update the system state.
        _kalmanFilter!.correctWithEarableCompass(
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

    // connect to the phone barometer //
    _phoneBarometerSubscription = barometerEventStream().listen((event) {
      // consider the sensor online now
      if (!_phoneBarometerOnline) {
        print("phone barometer online");
        setState(() {
          _phoneBarometerOnline = true;
        });
      }
      _kalmanFilter!.correctWithBarometer(event.pressure);
    })
      ..onError((e) {
        print('failed to subscribe to phone barometer');
        print(e);
      });

    // connect to the phone compass //
    _checkLocationWhenInUsePermission().then((granted) {
      if (!granted) {
        print("permission to use phone compass not granted");
        return;
      }

      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading != null) {
          // consider the sensor online now
          if (!_phoneCompassOnline) {
            print("phone compass online");
            setState(() {
              _phoneCompassOnline = true;
            });
          }

          // convert degrees to radians
          _kalmanFilter!.correctWithPhoneCompass(
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

    // connect to the phone pedometer //
    _checkActivityRecognitionPermission().then((granted) {
      if (!granted) {
        print("permission to use phone pedometer not granted");
        return;
      }

      // step counter //
      _stepCountSubscription = Pedometer.stepCountStream.listen((event) {
        // consider the sensor online now
        if (!_phoneStepCounterOnline) {
          print("phone step counter online");
          setState(() {
            _phoneStepCounterOnline = true;
          });
        }

        _kalmanFilter!.correctWithPedometer(event.steps);
      })
        ..onError((e) {
          print('failed to subscribe to phone step counter');
          print(e);
        });

      // pedestrian status //
      _pedestrianStateSubscription =
          Pedometer.pedestrianStatusStream.listen((event) {
        // consider the sensor online now
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

  // disable the Kalman Filter without deleting the data points
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
            // the settings
            Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'Pedestrian Dead Reckoning',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Hold your phone infront of you in your hand and keep your head upright as you walk. This provides the most accurate positioning.\nAlso, enable the permissions: Location, Nearby devices and Physical activity',
                      style: TextStyle(fontSize: 18),
                    ),
                    // start/stop button
                    IconButton(
                      splashRadius: 40,
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
                    // input fields
                    Column(
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
                    const SizedBox(height: 24),
                    // online/offline status for each sensor
                    Column(
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
                  ],
                ),
              ),
            ),
            // the map
            PDRMap(dataPoints: _dataPoints),
            // the plot
            PDRPlot(dataPoints: _dataPoints),
          ],
        ),
      ),
    );
  }

  // ask of the ActivityRecognitionPermission if required
  // return true iff granted
  Future<bool> _checkActivityRecognitionPermission() async {
    bool granted = await Permission.activityRecognition.isGranted;

    if (!granted) {
      granted = await Permission.activityRecognition.request() ==
          PermissionStatus.granted;
    }

    return granted;
  }

  // ask of the LocationWhenInUsePermission if required
  // return true iff granted
  Future<bool> _checkLocationWhenInUsePermission() async {
    bool granted = await Permission.locationWhenInUse.isGranted;

    if (!granted) {
      granted = await Permission.locationWhenInUse.request() ==
          PermissionStatus.granted;
    }

    return granted;
  }
}

// displays whether a sensor is online or offline
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
        // expand so that the online/offline labels are vertically aligned
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
