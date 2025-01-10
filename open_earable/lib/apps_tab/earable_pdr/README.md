# earable_pdr

Positioning without GPS or terrestrial positioning systems, i.e., underground, is difficult.
Pedestrian dead reckoning can solve this problem by using a known starting point and integrating velocity and acceleration.
While many pedestrian dead reckoning applications place inertial-systems on the user's boots or chest, the Earable is worn in the user's ear and the phone in her pocket.
Therefore, the Flutter App shows that accurate positioning can be achieved without special hardware.

Two inertial systems provide sensor readings to the app, one in the user's pocket and another in the user's ear.
These include an accelerometer for acceleration, gyroscope for angular velocity, magnetometer for cardinal direction and barometer for elevation.
A Kalman Filter allows these sensor values to be combined in real-time and calculate the user's likely position.
It does this by first predicting the system's state using a state transition matrix and then updating that state based on observations using the observation matrix.
This detail is important because of the differing sensor polling rates:
While the prediction step is performed every constant time interval, partial update steps are performed whenever new sensor data arrives.

The state model assumes the heading and velocity to be static.
Changes in these variables are interpreted as normally distributed noise.
