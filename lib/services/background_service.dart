import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

// State tracking for background service
String _lastCabinetStatus = 'Idle';
bool _wasLeftSterilizing = false;
bool _wasRightSterilizing = false;
DateTime? _lastShoeAlertTime;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create notification channel for foreground service
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'steristep_bg_service',
    'SteriStep Background Service',
    description: 'Keeps monitoring shoe & cabinet status',
    importance: Importance.low,
  );

  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'steristep_bg_service',
      initialNotificationTitle: 'SteriStep',
      initialNotificationContent: 'Monitoring your shoes & cabinet...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase in background isolate
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Initialize notifications
  const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidInit);
  await _notificationsPlugin.initialize(settings: initSettings);

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'SteriStep',
      content: 'Monitoring your shoes & cabinet...',
    );
  }

  // Listen to stop
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Get system ID from shared preferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final systemId = prefs.getString('system_id');

  if (systemId == null || systemId.isEmpty) {
    // No system ID, keep service running but poll until available
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final sid = p.getString('system_id');
      if (sid != null && sid.isNotEmpty) {
        timer.cancel();
        _startFirebaseListener(service, sid);
      }
    });
    return;
  }

  _startFirebaseListener(service, systemId);
}

void _startFirebaseListener(ServiceInstance service, String systemId) {
  final ref = FirebaseDatabase.instance.ref('devices/$systemId');

  ref.onValue.listen((event) {
    if (event.snapshot.value == null) return;

    final data = Map<String, dynamic>.from(event.snapshot.value as Map);
    _evaluateAndNotify(data, service);
  });
}

bool _isFirstEvaluation = true;

void _evaluateAndNotify(Map<String, dynamic> data, ServiceInstance service) {
  final leftData = data['left_shoe'] != null ? Map<String, dynamic>.from(data['left_shoe'] as Map) : {};
  final rightData = data['right_shoe'] != null ? Map<String, dynamic>.from(data['right_shoe'] as Map) : {};
  final cabinetData = data['cabinet'] != null ? Map<String, dynamic>.from(data['cabinet'] as Map) : {};

  final lGas = (leftData['gasAnalog'] as num?)?.toInt() ?? 0;
  final rGas = (rightData['gasAnalog'] as num?)?.toInt() ?? 0;
  final lFoot = leftData['footDetected'] as bool? ?? false;
  final rFoot = rightData['footDetected'] as bool? ?? false;
  final leftIsSterilizing = leftData['isSterilizing'] as bool? ?? false;
  final rightIsSterilizing = rightData['isSterilizing'] as bool? ?? false;
  final cabinetStatus = cabinetData['cabinetStatus']?.toString() ?? 'Idle';

  final maxGas = lGas > rGas ? lGas : rGas;
  final isFootDetected = lFoot || rFoot;

  if (!_isFirstEvaluation) {
    // RULE 1: High gas while wearing shoe
    if (isFootDetected && maxGas >= 1200) {
      if (_lastShoeAlertTime == null || DateTime.now().difference(_lastShoeAlertTime!).inMinutes > 2) {
        _lastShoeAlertTime = DateTime.now();
        _sendNotification('Sterilization Required', 'put the shoe in the sterilization cabinet Sterilization in process');
      }
    }

    // RULE 2: Cabinet sterilization done
    if (cabinetStatus == 'Cleaning process is done' && _lastCabinetStatus != 'Cleaning process is done') {
      _sendNotification('Cabinet Sterilization', 'Cleaning process is done');
    }

    // RULE 3: Shoe sterilization started
    if (!_wasLeftSterilizing && leftIsSterilizing) {
      _sendNotification('Left Shoe Sterilization', 'Sterilization in process');
    }
    if (!_wasRightSterilizing && rightIsSterilizing) {
      _sendNotification('Right Shoe Sterilization', 'Sterilization in process');
    }

    // RULE 4: Shoe sterilization done
    if (_wasLeftSterilizing && !leftIsSterilizing) {
      _sendNotification('Left Shoe Sterilization', 'Cleaning process is done');
    }
    if (_wasRightSterilizing && !rightIsSterilizing) {
      _sendNotification('Right Shoe Sterilization', 'Cleaning process is done');
    }
  }

  _isFirstEvaluation = false;
  
  // Update state
  _lastCabinetStatus = cabinetStatus;
  _wasLeftSterilizing = leftIsSterilizing;
  _wasRightSterilizing = rightIsSterilizing;

  // Update foreground notification
  if (service is AndroidServiceInstance) {
    String statusText = 'Monitoring...';
    if (leftIsSterilizing || rightIsSterilizing) {
      statusText = 'Shoe sterilization in progress';
    } else if (cabinetStatus == 'Sterilization in process' || cabinetStatus == 'UVC Sterilization in process') {
      statusText = 'Cabinet: Sterilization in progress';
    }
    service.setForegroundNotificationInfo(
      title: 'SteriStep',
      content: statusText,
    );
  }
}

Future<void> _sendNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'steristep_alerts',
    'SteriStep Alerts',
    channelDescription: 'Notifications for shoe and cabinet status',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);

  await _notificationsPlugin.show(
    id: DateTime.now().millisecondsSinceEpoch % 100000,
    title: title,
    body: body,
    notificationDetails: details,
  );
}
