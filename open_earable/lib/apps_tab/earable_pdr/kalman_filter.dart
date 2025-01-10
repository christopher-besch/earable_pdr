import 'dart:async';
import 'dart:math';
import 'package:ml_linalg/linalg.dart';

// the output of the Kalman Filter to be sent every dataRate seconds
class DataPoint {
  // time since the Kalman Filter started
  Duration time;
  // 3d vector
  // xy position relative to the starting position in m
  // z is the height in m above NN
  Vector position;
  // the current velocity in m/s
  double velocity;
  // the heading in radians, 0 is north
  double heading;
  // absolute step count (starting to count when the app was installed)
  double totalSteps;
  DataPoint(
    this.time,
    this.position,
    this.velocity,
    this.heading,
    this.totalSteps,
  );
}

// The Kalman Filter combines the different sensor readings to provide the likeliest current system state.
// Time is given in seconds, length in meters, speed in meters per second, pressure in hectopascal and angles in radians.
// The variable names x, P, Q, F, z, H, R and K are the standard for Kalman Filters and thus used here.
class KalmanFilter {
  // time interval between update steps in seconds
  // While the sensor input is asynchronous and thus polled at different time intervals the update step is performed synchronously.
  // This isn't a Duration to make calculating with it easier.
  late double _dt;
  late Timer _predictTimer;
  // time interval between Kalman Filter DataPoint output
  late double _dataRate;
  late Timer _reportTimer;

  // the accuracy of the earable-provided heading
  final _earableAccuracy = 1000000.0;

  // When this is false the speed is set back to 0 at every update interval.
  // See the comment in the setIsWalking function.
  bool _walking = true;

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
  // assume low process noise everywhere except the stride length, this never changes
  final Matrix _Q = Matrix.fromList(
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

  late Stopwatch _time;

  // This stream outputs the current state of the Kalman Filter.
  final StreamController<DataPoint> _controller = StreamController<DataPoint>();
  Stream<DataPoint> get stream => _controller.stream;

  // predictionRate: time interval between update steps in seconds
  // dataRate: time interval between Kalman Filter DataPoint output
  // stepLength: the stride length of the user
  KalmanFilter(double predictionRate, double dataRate, double stepLength) {
    _time = Stopwatch()..start();

    _dt = predictionRate;
    _dataRate = dataRate;
    // initialize state vector
    _x = Vector.fromList(
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, stepLength],
      dtype: DType.float64,
    );
    // initialize the estimate covariance
    // assume the starting xy position and velocity is correct -> low variance
    // the height, step count and heading are likely completely wrong -> high variance
    // the step size is assumed completely constant -> no variance
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

    _predictTimer =
        Timer.periodic(Duration(microseconds: (_dt * 1000000).round()), (_) {
      predict();
      // see the comment in setIsWalking
      if (!_walking) {
        correctWithWalkingStopped();
      }
    });

    _reportTimer = Timer.periodic(
        Duration(microseconds: (_dataRate * 1000000).round()), (_) {
      // optional debug print
      // print(
      //   '${_x[0].toStringAsFixed(1)}\t${_x[1].toStringAsFixed(1)}\t${_x[2].toStringAsFixed(1)}\t${_x[3].toStringAsFixed(1)}\t${_x[4].toStringAsFixed(1)}\t${_x[5].toStringAsFixed(1)}\t${_x[6].toStringAsFixed(1)}',
      // );

      // send a new DataPoint to the consumer of the Kalman Filter
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

  // Perform a prediction step of the Kalman Filter.
  // This function should be called every _dt seconds.
  void predict() {
    // state transition matrix
    final F = Matrix.fromList(
      [
        // Adjust the position according to the current velocity and heading.
        [1.0, 0.0, 0.0, _dt * cos(_x[4]), 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, -_dt * sin(_x[4]), 0.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        // The step count should change according to the velocity and stride length.
        [0.0, 0.0, 0.0, _dt / _x[6], 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
      ],
      dtype: DType.float64,
    );

    // Kalman Filter prediction equations //
    // extrapolate state
    // There is no input and thus no control matrix.
    _x = (F * _x).toVector();

    // extrapolate uncertainty
    _P = F * _P * F.transpose() + _Q;
  }

  // called whenever the phone's barometer produces a new measurement
  // pressure: the current air pressure
  void correctWithBarometer(double pressure) {
    // calculate inclination from pressure
    // see: https://www.weather.gov/media/epz/wxcalc/pressureAltitude.pdf
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

  // called whenever the phone's compass produces a new measurement
  // heading: the current compass heading in radians
  // accuracy: the accuracy of the current compass heading in radians
  void correctWithPhoneCompass(
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
        // increase the variance a little to smooth out the heading (i.e. add a low-pass filter)
        [20 * heading],
      ],
      dtype: DType.float64,
    );

    correct(z, H, R);
  }

  // called whenever the earable produces a new IMU measurement
  // roll: the earable's roll
  // pitch: the earable's pitch
  // magnetometerX: the earable's magnetometer reading in x
  // magnetometerY: the earable's magnetometer reading in y
  // magnetometerZ: the earable's magnetometer reading in z
  void correctWithEarableCompass(
    double roll,
    double pitch,
    double magnetometerX,
    double magnetometerY,
    double magnetometerZ,
  ) {
    // tilt correct the magnetometer readings using the accelerometer
    // see http://www.brokking.net/YMFC-32/YMFC-32_document_1.pdf
    double magnetometerXCorrected = magnetometerX * cos(pitch) +
        magnetometerY * sin(roll) * sin(pitch) -
        magnetometerZ * cos(roll) * sin(pitch);
    double magnetometerYCorrected =
        magnetometerY * cos(roll) + magnetometerZ * sin(roll);
    // convert tilt-corrected magnetometer readings into a heading
    var z = Vector.fromList(
      [atan2(-magnetometerYCorrected, magnetometerXCorrected)],
      dtype: DType.float64,
    );

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

  // called whenever the phone's pedometer updates the step count.
  // The Kalman Filter takes care of updating the velocity with this.
  // totalSteps: the absolute number of steps starting from the app's installation (or some other fixed point)
  void correctWithPedometer(int totalSteps) {
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

  // called whenever the system is sure the user stopped walking
  void correctWithWalkingStopped() {
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

  // Perform a Kalman Filter correction step using the Kalman Filter correct equations.
  // z: measurement vector
  // H: observation matrix
  // R: measurement covariance
  void correct(Vector z, Matrix H, Matrix R) {
    // kalman gain
    final pHT = _P * H.transpose();
    final K = pHT * (H * pHT + R).inverse();

    // update estimate
    _x = _x + K * (z - H * _x);

    // update estimate uncertainty
    var iKH = (Matrix.identity(K.rowCount, dtype: DType.float64) - K * H);
    _P = iKH * _P * iKH.transpose() + K * R * K.transpose();
  }

  void setIsWalking(bool walking) {
    // The pedestrian status may change to 'standing' before the last step count update is received.
    // In that case the last step count change makes the Kalman Filter set the velocity to something non-zero.
    // This is a problem when the user stops walking.
    // To fix this we remember that the pedestrian status is 'standing' and reset the velocity in the predict timer.
    // This on the other hand creates a problem when a 'walking' pedestrian status update is lost.
    // This does happen, especially when starting the Kalman Filter.
    // To fix this we set the walking status back to walking after a short time period.
    // This fixes both problems as stray step count updates don't happen after this time period.
    _walking = walking;
    if (!_walking) {
      correctWithWalkingStopped();
      Future.delayed(const Duration(milliseconds: 3000), () {
        _walking = true;
      });
    }
  }

  // stop the KalmanFilter
  // The KalmanFilter cannot be started again after this (though this could be implemented without too much hassle).
  void cancel() {
    _predictTimer.cancel();
    _reportTimer.cancel();
  }
}
