import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String channelIdAlerts = 'steristep_alerts';
  static const String channelNameAlerts = 'SteriStep Critical Alerts';
  static const String channelDescAlerts = 'Notifications for shoe contamination, sterilization, and safety';

  static const String channelIdBg = 'steristep_bg_service';
  static const String channelNameBg = 'SteriStep Background Service';

  // Distinct Notification IDs
  static const int idShoeGasAlert = 1001;
  static const int idLeftShoeSterilizing = 1002;
  static const int idRightShoeSterilizing = 1003;
  static const int idCabinetCycle = 1004;
  static const int idCabinetDoorSafety = 1005;

  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings: initSettings);

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // 1. High Priority Alert Channel (Heads-up banner, sound, vibration)
      const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
        channelIdAlerts,
        channelNameAlerts,
        description: channelDescAlerts,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(alertChannel);

      // 2. Low Priority Background Service Channel
      const AndroidNotificationChannel bgChannel = AndroidNotificationChannel(
        channelIdBg,
        channelNameBg,
        description: 'Persistent notification while monitoring system',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );
      await androidPlugin.createNotificationChannel(bgChannel);
    }
  }

  Future<void> requestPermissions() async {
    try {
      // Request Android 13+ Notification permission
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // Request permission via permission_handler as well for reliability
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // Battery optimization prompt for uninterrupted background monitoring
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelIdAlerts,
      channelNameAlerts,
      channelDescription: channelDescAlerts,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'SteriStep Alert',
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> logAlertToFirebase({
    required String title,
    required String message,
  }) async {
    try {
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        final prefs = await SharedPreferences.getInstance();
        uid = prefs.getString('user_uid');
      }

      if (uid != null && uid.isNotEmpty) {
        final db = FirebaseDatabase.instance.ref();
        final alertId = db.child('users/$uid/alerts').push().key;
        if (alertId != null) {
          await db.child('users/$uid/alerts/$alertId').set({
            'title': title,
            'message': message,
            'timestamp': ServerValue.timestamp,
          });
        }
      }
    } catch (e) {
      debugPrint('Error logging alert to Firebase: $e');
    }
  }
}
