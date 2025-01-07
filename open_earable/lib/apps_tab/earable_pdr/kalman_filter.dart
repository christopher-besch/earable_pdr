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

  final StreamController<DataPoint> _controller = StreamController<DataPoint>();
  get stream => _controller.stream;

  KalmanFilter() {
    _time = Stopwatch()..start();

    _dt = 0.05;
    _x = Vector.fromList(
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.82],
      dtype: DType.float64,
    );
    // assume the starting position and velocity is correct -> high confidence
    // the height and step count is likely completely wrong -> low confidence
    // the step size is assumed completely constant
    _P = Matrix.fromList(
      [
        [0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 1000.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );
    _Q = Matrix.fromList(
      [
        [0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.01, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      ],
      dtype: DType.float64,
    );

    Timer.periodic(Duration(microseconds: (_dt * 1000000).round()), (_) {
      predict();
      print(_x);
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
        [0.0, 1.0, 0.0, _dt * sin(_x[4]), 0.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, _dt * _x[6], 0.0, 1.0, 0.0],
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

  void correctMagnetometer(Vector z) {
    // TODO: implement
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
        [0.01],
      ],
      dtype: DType.float64,
    );
  }

  // measurement vector z:
  // total steps until now
  void correctPedometer(Vector z) {
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
        [0.0],
      ],
      dtype: DType.float64,
    );

    // kalman gain
    final K = _P * H.transpose() * (H * _P * H.transpose() + R).inverse();
    // update estimate
    _x = _x + K * (z - H * _x);
    // update estimate uncertainty
    // TODO: don't calculate things twice
    _P = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H) *
            _P *
            (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H)
                .transpose() +
        K * R * K.transpose();
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

    // kalman gain
    final K = _P * H.transpose() * (H * _P * H.transpose() + R).inverse();
    // update estimate
    _x = _x + K * (z - H * _x);
    // update estimate uncertainty
    // TODO: don't calculate things twice
    _P = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H) *
            _P *
            (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H)
                .transpose() +
        K * R * K.transpose();
  }

  // measurement vector z:
  // phone accelerometer x
  // phone accelerometer y
  // phone accelerometer z
  void correctAcceleration(Vector z) {
    // TODO: remove
    // // TODO: make sure this isn't actually calculating the inverse
    // // kalman gain
    // final K = _P * _H.transpose() * (_H * _P * _H.transpose() + _R).inverse();
    // // update estimate
    // _x = _x + K * (z - _H * _x);
    // // update estimate uncertainty
    // // TODO: don't calculate things twice
    // _P = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * _H) *
    //         _P *
    //         (Matrix.identity(K.rowCount, dtype: DType.float64) - K * _H)
    //             .transpose() +
    //     K * _R * K.transpose();
  }
}
