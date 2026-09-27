# SteriStep App (Flutter prototype)

Companion mobile app for the SteriStep smart shoe project.

## Screens included
- **Home** – overview of gas, temperature, humidity, pressure, cabinet status
- **Pressure Map** – toe / midfoot / heel pressure (FSR sensors)
- **Gas Detection** – MQ135 reading + Level 1/2/3 thresholds (report Table 3)
- **Temp & Humidity** – DHT22 readings + safe/warning/danger zones (report Table 4)
- **Cabinet** – sterilization cycle status + manual start + flowchart steps
- **Profile** – age/gender based shoe size lookup (report Table 6)

## Running it
1. Install Flutter SDK: https://docs.flutter.dev/get-started/install
2. `cd steristep_app`
3. `flutter pub get`
4. `flutter run` (with an emulator or phone connected)

## Currently uses fake data
`lib/models/sensor_data.dart` has `MockSensorService`, which generates random
readings every 2 seconds so you can see the UI working without hardware.

## Connecting the real ESP32 later
In `lib/main.dart`, `_sensorService` is the single place all screens get data
from. Swap `MockSensorService` for a real client that publishes the same
`SensorSnapshot` objects:
- **BLE**: add `flutter_blue_plus` package, read characteristics from the ESP32
- **WiFi/REST**: add `http` package, poll or use a WebSocket from the ESP32's
  IP address, parse into `SensorSnapshot`

No screen code needs to change — they all just read whatever `SensorSnapshot`
comes through the stream.
