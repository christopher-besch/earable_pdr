import 'dart:async';

import 'package:ml_linalg/linalg.dart';
import 'package:sensors_plus/sensors_plus.dart';

class DataPoint {
  Duration time;
  Vector position;
  Vector velocity;
  Vector acceleration;
  DataPoint(this.time, this.position, this.velocity, this.acceleration);
}

class KalmanFilter {
  // time interval between update steps in seconds
  // while the sensor input is asynchronous and thus polled at different time intervals the update step is performed synchronously
  // This isn't a Duration to make calculating with it easier.
  late double _dt;

  // current state:
  // position_x
  // position_y
  // position_z
  // velocity_x
  // velocity_y
  // velocity_z
  // acceleration_x
  // acceleration_y
  // acceleration_z
  late Vector _x;
  // state transition matrix
  late Matrix _F;
  // estimate covariance
  late Matrix _P;
  // process noise covariance
  late Matrix _Q;
// observation matrix
  late Matrix _H;
  // measurement covariance
  late Matrix _R;

  late Stopwatch _time;

  final StreamController<DataPoint> _controller = StreamController<DataPoint>();
  get stream => _controller.stream;

  KalmanFilter() {
    _time = Stopwatch()..start();

    _dt = 0.05;
    _x = Vector.fromList([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        dtype: DType.float64);
    _F = Matrix.fromList([
      [1.0, 0.0, 0.0, _dt, 0.0, 0.0, .5 * _dt, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0, _dt, 0.0, 0.0, .5 * _dt, 0.0],
      [0.0, 0.0, 1.0, 0.0, 0.0, _dt, 0.0, 0.0, .5 * _dt],
      [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, _dt, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, _dt, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, _dt],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
    ], dtype: DType.float64);
    // assume the starting position is correct -> high confidence
    _P = Matrix.fromList([
      [100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 100.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 100.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 100.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 100.0],
    ], dtype: DType.float64);
    _Q = Matrix.fromList([
      [0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.01, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.01, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.01],
    ], dtype: DType.float64);
    // no rotation so far
    _H = Matrix.fromList([
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
    ], dtype: DType.float64);
    _R = Matrix.fromList([
      [0.01, 0.0, 0.0],
      [0.0, 0.01, 0.0],
      [0.0, 0.0, 0.01],
    ], dtype: DType.float64);

    Timer.periodic(Duration(microseconds: (_dt * 1000000).round()), (_) {
      predict();
      _controller.sink.add(DataPoint(
          _time.elapsed,
          Vector.fromList([_x[0], _x[1], _x[2]], dtype: DType.float64),
          Vector.fromList([_x[3], _x[3], _x[5]], dtype: DType.float64),
          Vector.fromList([_x[6], _x[7], _x[8]], dtype: DType.float64)));
    });

    // TODO: handle error
    // TODO: does stream need to be canceled before destruction?
    accelerometerEventStream().listen((event) {
      correct(
          Vector.fromList([event.x, event.y, event.z], dtype: DType.float64));
    });
  }

  // measurement vector:
  // phone accelerometer x
  // phone accelerometer y
  // phone accelerometer z
  correct(Vector z) {
    // TODO: make sure this isn't actually calculating the inverse
    // kalman gain
    final K = _P * _H.transpose() * (_H * _P * _H.transpose() + _R).inverse();
    // update estimate
    _x = _x + K * (z - _H * _x);
    // update estimate uncertainty
    // TODO: don't calculate things twice
    _P = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * _H) *
            _P *
            (Matrix.identity(K.rowCount, dtype: DType.float64) - K * _H)
                .transpose() +
        K * _R * K.transpose();
  }

  predict() {
    // extrapolate state
    // There is no input and thus no control matrix.
    _x = (_F * _x).toVector();

    // extrapolate uncertainty
    _P = _F * _P * _F.transpose() + _Q;
  }
}
