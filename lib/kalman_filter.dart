import 'dart:async';

import 'package:ml_linalg/linalg.dart';
import 'package:sensors_plus/sensors_plus.dart';

class DataPoint {
  Duration time;
  Vector acceleration;
  DataPoint(this.time, this.acceleration);
}

class KalmanFilter {
  var _acceleration = Vector.fromList([0.0, 0.0, 0.0], dtype: DType.float64);
  late Stopwatch _time;

  final StreamController<DataPoint> _controller = StreamController<DataPoint>();
  get stream => _controller.stream;

  KalmanFilter() {
    _time = Stopwatch()..start();

    Timer.periodic(Duration(milliseconds: 50), (_) {
      _controller.sink.add(DataPoint(_time.elapsed, _acceleration));
    });

    // TODO: handle error
    // TODO: does stream need to be canceled before destruction?
    accelerometerEventStream().listen((event) {
      _acceleration =
          Vector.fromList([event.x, event.y, event.z], dtype: DType.float64);
    });
  }
}
