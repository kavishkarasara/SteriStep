import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

// State tracking for background service
String _lastCabinetStatus = 'Idle';
bool _wasLeftSterilizing = false;
bool _wasRightSterilizing = false;
bool _wasWearingContaminated = false;
DateTime? _lastShoeAlertTime;
bool _wasDoorOpenDuringSterilization = false;
DateTime? _lastDoorAlertTime;

bool _isAppInForeground = false;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create high-importance alert channel
  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    NotificationService.channelIdAlerts,
    NotificationService.channelNameAlerts,
    description: NotificationService.channelDescAlerts,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  // Create low-importance persistent service channel
  const AndroidNotificationChannel bgChannel = AndroidNotificationChannel(
    NotificationService.channelIdBg,
    NotificationService.channelNameBg,
    description: 'Keeps monitoring shoe & cabinet status',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  final androidPlugin = _notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(alertChannel);
  await androidPlugin?.createNotificationChannel(bgChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: NotificationService.channelIdBg,
      initialNotificationTitle: 'SteriStep',
      initialNotificationContent: 'Monitoring shoes & cabinet...',
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
      title: 'SteriStep Active',
      content: 'Real-time monitoring active',
    );
  }

  // Listen to UI foreground / background transitions
  service.on('setAppForeground').listen((event) {
    if (event != null && event.containsKey('isForeground')) {
      _isAppInForeground = event['isForeground'] as bool? ?? false;
    }
  });

  // Listen to stop
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Get system ID from shared preferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final systemId = prefs.getString('system_id');

  if (systemId == null || systemId.isEmpty) {
    Timer.periodic(const Duration(seconds: 10), (timer) async {
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
  }, onError: (error) {
    // Ignore background database permission / network errors quietly
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
  final doorOpen = (cabinetData['doorOpen'] as num?)?.toInt() == 1;

  final maxGas = lGas > rGas ? lGas : rGas;
  final isFootDetected = lFoot || rFoot;
  final isContaminated = maxGas >= 1200;

  final bool isCabinetRunning = cabinetStatus == 'Sterilization in process' || 
                                cabinetStatus == 'UVC Sterilization in process';
  final bool wasCabinetNotRunning = _lastCabinetStatus == 'Idle' || 
                                   _lastCabinetStatus == 'Cleaning process is done';

  // Only trigger background notifications when the app is in background or closed
  if (!_isFirstEvaluation && !_isAppInForeground) {
    // 1. High gas while wearing shoe
    if (isFootDetected && isContaminated) {
      final now = DateTime.now();
      final bool stateChanged = !_wasWearingContaminated;
      final bool reminderDue = _lastShoeAlertTime != null && 
                               now.difference(_lastShoeAlertTime!).inMinutes >= 3;

      if (stateChanged || reminderDue) {
        _lastShoeAlertTime = now;
        _wasWearingContaminated = true;
        _sendNotification(
          NotificationService.idShoeGasAlert,
          'Sterilization Required ⚠️',
          'put the shoe in the sterilization cabinet Sterilization in process',
        );
      }
    } else {
      _wasWearingContaminated = false;
    }

    // 2. Cabinet Sterilization Started
    if (isCabinetRunning && wasCabinetNotRunning) {
      final isHeavy = cabinetStatus == 'Sterilization in process';
      _sendNotification(
        NotificationService.idCabinetCycle,
        'Cabinet Sterilization in Process 🧴',
        isHeavy ? 'Sterilization in process (Dual H₂O₂ + UVC)' : 'UVC Sterilization in process',
      );
    }

    // 3. Cabinet Door Opened During Sterilization (Safety Interlock)
    if (isCabinetRunning && doorOpen) {
      final now = DateTime.now();
      if (!_wasDoorOpenDuringSterilization || 
          (_lastDoorAlertTime != null && now.difference(_lastDoorAlertTime!).inMinutes >= 1)) {
        _wasDoorOpenDuringSterilization = true;
        _lastDoorAlertTime = now;
        _sendNotification(
          NotificationService.idCabinetDoorSafety,
          'Cabinet Safety Alert ⚠️',
          'Cabinet door opened! Sterilization paused for safety. Please close the door.',
        );
      }
    } else if (!doorOpen) {
      _wasDoorOpenDuringSterilization = false;
    }

    // 4. Cabinet Sterilization Done
    if (cabinetStatus == 'Cleaning process is done' && _lastCabinetStatus != 'Cleaning process is done') {
      _sendNotification(
        NotificationService.idCabinetCycle,
        'Cabinet Sterilization Complete ✅',
        'Cleaning process is done',
      );
    }

    // 5. Shoe Sterilization Started
    if (!_wasLeftSterilizing && leftIsSterilizing) {
      _sendNotification(
        NotificationService.idLeftShoeSterilizing,
        'Smart Shoe Sanitization 👟',
        'Left Shoe: Sterilization in process',
      );
    }
    if (!_wasRightSterilizing && rightIsSterilizing) {
      _sendNotification(
        NotificationService.idRightShoeSterilizing,
        'Smart Shoe Sanitization 👟',
        'Right Shoe: Sterilization in process',
      );
    }

    // 6. Shoe Sterilization Done
    if (_wasLeftSterilizing && !leftIsSterilizing) {
      _sendNotification(
        NotificationService.idLeftShoeSterilizing,
        'Smart Shoe Sanitization Complete ✅',
        'Left Shoe: Cleaning process is done',
      );
    }
    if (_wasRightSterilizing && !rightIsSterilizing) {
      _sendNotification(
        NotificationService.idRightShoeSterilizing,
        'Smart Shoe Sanitization Complete ✅',
        'Right Shoe: Cleaning process is done',
      );
    }
  }

  _isFirstEvaluation = false;
  _lastCabinetStatus = cabinetStatus;
  _wasLeftSterilizing = leftIsSterilizing;
  _wasRightSterilizing = rightIsSterilizing;

  // Update persistent foreground notification text
  if (service is AndroidServiceInstance) {
    String statusText = 'Monitoring shoes & cabinet';
    if (leftIsSterilizing || rightIsSterilizing) {
      statusText = 'Shoe UV sterilization in progress';
    } else if (cabinetStatus == 'Sterilization in process' || cabinetStatus == 'UVC Sterilization in process') {
      statusText = 'Cabinet sterilization in progress';
    } else if (doorOpen) {
      statusText = 'Cabinet door is open';
    }
    service.setForegroundNotificationInfo(
      title: 'SteriStep System Active',
      content: statusText,
    );
  }
}

Future<void> _sendNotification(int id, String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    NotificationService.channelIdAlerts,
    NotificationService.channelNameAlerts,
    channelDescription: NotificationService.channelDescAlerts,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    showWhen: true,
    ticker: 'SteriStep Alert',
    icon: '@mipmap/ic_launcher',
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);

  await _notificationsPlugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: details,
  );

  // Also log to Firebase RTDB from background if user uid is known
  try {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_uid');
    if (uid != null && uid.isNotEmpty) {
      final db = FirebaseDatabase.instance.ref();
      final alertId = db.child('users/$uid/alerts').push().key;
      if (alertId != null) {
        await db.child('users/$uid/alerts/$alertId').set({
          'title': title,
          'message': body,
          'timestamp': ServerValue.timestamp,
        });
      }
    }
  } catch (_) {}
}
