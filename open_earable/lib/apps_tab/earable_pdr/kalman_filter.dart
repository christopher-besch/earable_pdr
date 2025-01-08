import 'dart:async';
import 'dart:math';

import 'package:ml_linalg/linalg.dart';

class DataPoint {
  Duration time;
  Vector position;
  double velocity;
  double heading;
  double totalSteps;
  DataPoint(
    this.time,
    this.position,
    this.velocity,
    this.heading,
    this.totalSteps,
  );
}

// Time is given in seconds, length in meters, speed in meters per second, pressure in hectopascal and angles in radians.
class KalmanFilter {
  // time interval between update steps in seconds
  // while the sensor input is asynchronous and thus polled at different time intervals the update step is performed synchronously
  // This isn't a Duration to make calculating with it easier.
  late double _dt;
  late double _dataRate;

  final _earableAccuracy = 1000000.0;

  bool _walking = true;

  late Timer _predictTimer;
  late Timer _reportTimer;

  // current state:
  // position_x
  // position_y
  // position_z (height)
  // velocity
  // heading
  // steps taken
  // step size
  late Vector _x;
  // estimate covariance
  late Matrix _P;
  // process noise covariance
  late Matrix _Q;

  late Stopwatch _time;

  // This stream outputs the current state of the kalman filter.
  final StreamController<DataPoint> _controller = StreamController<DataPoint>();
  Stream<DataPoint> get stream => _controller.stream;

  KalmanFilter(double predictionRate, double dataRate, double stepLength) {
    _time = Stopwatch()..start();

    _dt = predictionRate;
    _dataRate = dataRate;
    _x = Vector.fromList(
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, stepLength],
      dtype: DType.float64,
    );
    // assume the starting position and velocity is correct -> high confidence
    // the height and step count is likely completely wrong -> low confidence
    // the step size is assumed completely constant
    _P = Matrix.fromList(
      [
        [0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 1000, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 10, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 100000.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    _Q = Matrix.fromList(
      [
        [0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.01, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );

    _predictTimer =
        Timer.periodic(Duration(microseconds: (_dt * 1000000).round()), (_) {
      predict();
      // see the comment in setIsWalking
      if (!_walking) {
        correctWalkingStopped();
      }
    });

    _reportTimer = Timer.periodic(
        Duration(microseconds: (_dataRate * 1000000).round()), (_) {
      print(
        '${_x[0].toStringAsFixed(1)}\t${_x[1].toStringAsFixed(1)}\t${_x[2].toStringAsFixed(1)}\t${_x[3].toStringAsFixed(1)}\t${_x[4].toStringAsFixed(1)}\t${_x[5].toStringAsFixed(1)}\t${_x[6].toStringAsFixed(1)}',
      );
      _controller.sink.add(
        DataPoint(
          _time.elapsed,
          Vector.fromList([_x[0], _x[1], _x[2]], dtype: DType.float64),
          _x[3],
          _x[4],
          _x[5],
        ),
      );
    });
  }

  void predict() {
    // state transition matrix
    final F = Matrix.fromList(
      [
        [1.0, 0.0, 0.0, _dt * cos(_x[4]), 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, -_dt * sin(_x[4]), 0.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, _dt / _x[6], 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
      ],
      dtype: DType.float64,
    );

    // extrapolate state
    // There is no input and thus no control matrix.
    _x = (F * _x).toVector();

    // extrapolate uncertainty
    _P = F * _P * F.transpose() + _Q;
  }

  void correctBarometer(double pressure) {
    var z = Vector.fromList(
      [44307.7 * (1 - pow(pressure / 1013.25, 0.190284))],
      dtype: DType.float64,
    );
    // observation matrix
    var H = Matrix.fromList(
      [
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    // measurement covariance
    var R = Matrix.fromList(
      [
        [0.1],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  void correctPhoneCompass(
    double heading,
    double accuracy,
  ) {
    // print('$heading\t$accuracy');
    var z = Vector.fromList(
      [heading],
      dtype: DType.float64,
    );

    var H = Matrix.fromList(
      [
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    // measurement covariance
    var R = Matrix.fromList(
      [
        [20],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  // http://www.brokking.net/YMFC-32/YMFC-32_document_1.pdf
  void correctEarableCompass(
    // double yaw,
    double roll,
    double pitch,
    double magnetometerX,
    double magnetometerY,
    double magnetometerZ,
  ) {
    // var z = Vector.fromList(
    //   [yaw],
    //   dtype: DType.float64,
    // );

    double magnetometerXCorrected = magnetometerX * cos(pitch) +
        magnetometerY * sin(roll) * sin(pitch) -
        magnetometerZ * cos(roll) * sin(pitch);
    double magnetometerYCorrected =
        magnetometerY * cos(roll) + magnetometerZ * sin(roll);
    var z = Vector.fromList(
      [atan2(-magnetometerYCorrected, magnetometerXCorrected)],
      dtype: DType.float64,
    );
    // print(z[0]);
    // print('${magnetometerXCorrected}\t${magnetometerYCorrected}');
    // print('${magnetometerX}\t${magnetometerY}\t${magnetometerZ}');
    // print('${roll}\t${pitch}');

    // observation matrix
    var H = Matrix.fromList(
      [
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    // measurement covariance
    var R = Matrix.fromList(
      [
        [_earableAccuracy],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  void correctPedometer(int totalSteps) {
    var z = Vector.fromList([totalSteps], dtype: DType.float64);
    // observation matrix
    var H = Matrix.fromList(
      [
        [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      ],
      dtype: DType.float64,
    );
    // measurement covariance
    var R = Matrix.fromList(
      [
        [100.0],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  void correctWalkingStopped() {
    var z = Vector.fromList([0.0], dtype: DType.float64);
    // observation matrix
    var H = Matrix.fromList(
      [
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    // measurement covariance
    var R = Matrix.fromList(
      [
        [0.0],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  void correct(Vector z, Matrix H, Matrix R) {
    // kalman gain
    final K = _P * H.transpose() * (H * _P * H.transpose() + R).inverse();
    // update estimate
    _x = _x + K * (z - H * _x);
    // update estimate uncertainty
    var iKH = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H);
    _P = iKH * _P * iKH.transpose() + K * R * K.transpose();
  }

  void setIsWalking(bool walking) {
    // The pedestrian status may change to 'standing' before the last step count update is received.
    // In that case the last step count change makes the Kalman filter set the velocity to somethign non-zero.
    // This is a problem when the users stops walking.
    // To fix this we remember that the pedestrian status is 'standing' and reset the velocity in the predict timer.
    // This on the other hand creates a problem when a 'walking' pedestrian status update is lost.
    // This does happen, especially when starting the Kalman filter.
    // To fix this we set the walking status back to walking after a short time period.
    // This fixes both problems as stray step count updates don't happen after this time period.
    _walking = walking;
    if (!_walking) {
      correctWalkingStopped();
      Future.delayed(const Duration(milliseconds: 3000), () {
        _walking = true;
      });
    }
  }

  void cancel() {
    _predictTimer.cancel();
    _reportTimer.cancel();
  }
}
