import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
/// Snapshot of all sensor readings for one shoe at one moment.
/// Field names follow the components in the report's Component List (4.4.3):
/// MQ135 (gas), FSR (pressure), DHT22 (temp/humidity).
class ShoeData {
  final int gasAnalog; // 0-4095, MQ135 raw reading
  final double toePressure; // kPa
  final double heelPressure;
  final double midfootPressure;
  final double temperatureC; // DHT22
  final double humidityPct; // DHT22
  final bool footDetected;
  final bool isSterilizing;

  ShoeData({
    required this.gasAnalog,
    required this.toePressure,
    required this.heelPressure,
    required this.midfootPressure,
    required this.temperatureC,
    required this.humidityPct,
    required this.footDetected,
    required this.isSterilizing,
  });
}

class SensorSnapshot {
  final ShoeData leftShoe;
  final ShoeData rightShoe;
  final double cabinetTemperatureC;
  final double cabinetHumidityPct;
  final String cabinetStatus; // "Idle" | "UVC Sterilizing" | "UVC+H2O2 Sterilizing" | "Done"
  final int cabinetProgress; // 0 to 100
  final bool isDoorOpen;
  final bool isLeftConnected;
  final bool isRightConnected;
  final bool isCabinetConnected;
  final DateTime timestamp;

  SensorSnapshot({
    required this.leftShoe,
    required this.rightShoe,
    required this.cabinetTemperatureC,
    required this.cabinetHumidityPct,
    required this.cabinetStatus,
    required this.cabinetProgress,
    required this.isDoorOpen,
    required this.isLeftConnected,
    required this.isRightConnected,
    required this.isCabinetConnected,
    required this.timestamp,
  });
}

class ESP32SensorService {
  final _controller = StreamController<SensorSnapshot?>.broadcast();
  StreamSubscription<DatabaseEvent>? _subscription;
  Timer? _ticker;

  int _lastLeftUptime = -1;
  int _lastRightUptime = -1;
  int _lastCabinetUptime = -1;

  DateTime _leftSeen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _rightSeen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _cabinetSeen = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> _latestData = {};

  Stream<SensorSnapshot?> get stream => _controller.stream;

  void start({Function(Map<String, dynamic>)? onDataRaw}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final systemId = prefs.getString('system_id');
    
    if (systemId == null || systemId.isEmpty) {
      _controller.add(null);
      return;
    }

    final ref = FirebaseDatabase.instance.ref('devices/$systemId');
    
    _subscription = ref.onValue.listen((event) {
      if (event.snapshot.value != null) {
        _latestData = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (onDataRaw != null) onDataRaw(_latestData);
        _processData();
      } else {
        _controller.add(null);
      }
    });

    // Run a periodic ticker to update the connection status (in case a module drops offline)
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      _processData();
    });
  }

  void _processData() {
    if (_latestData.isEmpty) return;
    
    final leftData = _latestData['left_shoe'] != null ? Map<String, dynamic>.from(_latestData['left_shoe'] as Map) : {};
    final rightData = _latestData['right_shoe'] != null ? Map<String, dynamic>.from(_latestData['right_shoe'] as Map) : {};
    final cabinetData = _latestData['cabinet'] != null ? Map<String, dynamic>.from(_latestData['cabinet'] as Map) : {};

    // Track uptimes
    final lUptime = (leftData['uptime'] as num?)?.toInt() ?? -1;
    final rUptime = (rightData['uptime'] as num?)?.toInt() ?? -1;
    final cUptime = (cabinetData['uptime'] as num?)?.toInt() ?? -1;

    final now = DateTime.now();
    
    // Left Shoe
    if (lUptime != _lastLeftUptime && lUptime != -1) {
      if (_lastLeftUptime == -1) {
        // First load from Firebase. We don't know if this data is old or fresh.
        // Record it, but don't mark as 'seen recently' until it changes!
        _lastLeftUptime = lUptime;
      } else {
        _lastLeftUptime = lUptime;
        _leftSeen = now;
      }
    }
    
    // Right Shoe
    if (rUptime != _lastRightUptime && rUptime != -1) {
      if (_lastRightUptime == -1) {
        _lastRightUptime = rUptime;
      } else {
        _lastRightUptime = rUptime;
        _rightSeen = now;
      }
    }
    
    // Cabinet
    if (cUptime != _lastCabinetUptime && cUptime != -1) {
      if (_lastCabinetUptime == -1) {
        _lastCabinetUptime = cUptime;
      } else {
        _lastCabinetUptime = cUptime;
        _cabinetSeen = now;
      }
    }

    final isLeftConnected = now.difference(_leftSeen).inSeconds < 15;
    final isRightConnected = now.difference(_rightSeen).inSeconds < 15;
    final isCabinetConnected = now.difference(_cabinetSeen).inSeconds < 15;

    final leftShoe = ShoeData(
      gasAnalog: (leftData['gasAnalog'] as num?)?.toInt() ?? 0,
      toePressure: (leftData['toePressure'] as num?)?.toDouble() ?? 0.0,
      heelPressure: (leftData['heelPressure'] as num?)?.toDouble() ?? 0.0,
      midfootPressure: (leftData['midfootPressure'] as num?)?.toDouble() ?? 0.0,
      temperatureC: (leftData['temperatureC'] as num?)?.toDouble() ?? 0.0,
      humidityPct: (leftData['humidityPct'] as num?)?.toDouble() ?? 0.0,
      footDetected: leftData['footDetected'] as bool? ?? false,
      isSterilizing: leftData['isSterilizing'] as bool? ?? false,
    );

    final rightShoe = ShoeData(
      gasAnalog: (rightData['gasAnalog'] as num?)?.toInt() ?? 0,
      toePressure: (rightData['toePressure'] as num?)?.toDouble() ?? 0.0,
      heelPressure: (rightData['heelPressure'] as num?)?.toDouble() ?? 0.0,
      midfootPressure: (rightData['midfootPressure'] as num?)?.toDouble() ?? 0.0,
      temperatureC: (rightData['temperatureC'] as num?)?.toDouble() ?? 0.0,
      humidityPct: (rightData['humidityPct'] as num?)?.toDouble() ?? 0.0,
      footDetected: rightData['footDetected'] as bool? ?? false,
      isSterilizing: rightData['isSterilizing'] as bool? ?? false,
    );

    _controller.add(SensorSnapshot(
      leftShoe: leftShoe,
      rightShoe: rightShoe,
      cabinetTemperatureC: (cabinetData['temperatureC'] as num?)?.toDouble() ?? 0.0,
      cabinetHumidityPct: (cabinetData['humidityPct'] as num?)?.toDouble() ?? 0.0,
      cabinetStatus: cabinetData['cabinetStatus']?.toString() ?? 'Idle',
      cabinetProgress: (cabinetData['progress'] as num?)?.toInt() ?? 0,
      isDoorOpen: (cabinetData['doorOpen'] as num?)?.toInt() == 1,
      isLeftConnected: isLeftConnected,
      isRightConnected: isRightConnected,
      isCabinetConnected: isCabinetConnected,
      timestamp: now,
    ));
  }

  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    _controller.close();
  }
}
