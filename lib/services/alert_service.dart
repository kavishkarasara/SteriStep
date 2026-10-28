import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

class AlertService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final NotificationService _notificationService = NotificationService();

  // State Tracking
  bool _wasWearingContaminated = false;
  DateTime? _lastShoeWearAlertTime;

  bool _wasLeftSterilizing = false;
  bool _wasRightSterilizing = false;

  String _lastCabinetStatus = 'Idle';
  bool _wasDoorOpenDuringSterilization = false;
  DateTime? _lastDoorAlertTime;
  DateTime? _lastAutoCabinetStart;

  void evaluateData(Map<String, dynamic> data, BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

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

    // =========================================================================
    // RULE 1: Smart Shoe Flowchart (Fig 7) - High Gas While Wearing
    // =========================================================================
    if (isFootDetected && isContaminated) {
      final now = DateTime.now();
      final bool stateChanged = !_wasWearingContaminated;
      final bool reminderDue = _lastShoeWearAlertTime != null && 
                               now.difference(_lastShoeWearAlertTime!).inMinutes >= 3;

      if (stateChanged || reminderDue) {
        _lastShoeWearAlertTime = now;
        _wasWearingContaminated = true;

        _triggerAlert(
          id: NotificationService.idShoeGasAlert,
          title: 'Sterilization Required ⚠️',
          message: 'put the shoe in the sterilization cabinet Sterilization in process',
          context: context,
        );
      }
    } else {
      // Reset state so that next time shoe is worn or contaminated, alert fires immediately
      _wasWearingContaminated = false;
    }

    // =========================================================================
    // RULE 2: Cabinet Flowchart (Fig 8) - Shoe Placed in Cabinet (No Foot)
    // =========================================================================
    if (!isFootDetected && isContaminated && !doorOpen && cabinetStatus == 'Idle') {
      final now = DateTime.now();
      if (_lastAutoCabinetStart == null || now.difference(_lastAutoCabinetStart!).inMinutes >= 2) {
        _lastAutoCabinetStart = now;
        if (maxGas >= 2500) {
          _sendCommand(uid, 'START_HEAVY');
        } else {
          _sendCommand(uid, 'START_UVC');
        }
      }
    }

    // =========================================================================
    // RULE 3: Cabinet Sterilization Started (Fig 8)
    // =========================================================================
    final bool isCabinetRunning = cabinetStatus == 'Sterilization in process' || 
                                  cabinetStatus == 'UVC Sterilization in process';
    final bool wasCabinetNotRunning = _lastCabinetStatus == 'Idle' || 
                                     _lastCabinetStatus == 'Cleaning process is done';

    if (isCabinetRunning && wasCabinetNotRunning) {
      final isHeavy = cabinetStatus == 'Sterilization in process';
      _triggerAlert(
        id: NotificationService.idCabinetCycle,
        title: 'Cabinet Sterilization in Process 🧴',
        message: isHeavy 
            ? 'Sterilization in process (Dual H₂O₂ + UVC)'
            : 'UVC Sterilization in process',
        context: context,
      );
    }

    // =========================================================================
    // RULE 4: Cabinet Door Opened During Sterilization (Safety Interlock)
    // =========================================================================
    if (isCabinetRunning && doorOpen) {
      final now = DateTime.now();
      if (!_wasDoorOpenDuringSterilization || 
          (_lastDoorAlertTime != null && now.difference(_lastDoorAlertTime!).inMinutes >= 1)) {
        _wasDoorOpenDuringSterilization = true;
        _lastDoorAlertTime = now;

        _triggerAlert(
          id: NotificationService.idCabinetDoorSafety,
          title: 'Cabinet Safety Alert ⚠️',
          message: 'Cabinet door opened! Sterilization paused for safety. Please close the door.',
          context: context,
        );
      }
    } else if (!doorOpen) {
      _wasDoorOpenDuringSterilization = false;
    }

    // =========================================================================
    // RULE 5: Cabinet Sterilization Done (Fig 8)
    // =========================================================================
    if (cabinetStatus == 'Cleaning process is done' && _lastCabinetStatus != 'Cleaning process is done') {
      _triggerAlert(
        id: NotificationService.idCabinetCycle,
        title: 'Cabinet Sterilization Complete ✅',
        message: 'Cleaning process is done',
        context: context,
      );
    }

    // =========================================================================
    // RULE 6: Shoe Sterilization Started (Fig 7)
    // =========================================================================
    if (!_wasLeftSterilizing && leftIsSterilizing) {
      _triggerAlert(
        id: NotificationService.idLeftShoeSterilizing,
        title: 'Smart Shoe Sanitization 👟',
        message: 'Left Shoe: Sterilization in process',
        context: context,
      );
    }
    if (!_wasRightSterilizing && rightIsSterilizing) {
      _triggerAlert(
        id: NotificationService.idRightShoeSterilizing,
        title: 'Smart Shoe Sanitization 👟',
        message: 'Right Shoe: Sterilization in process',
        context: context,
      );
    }

    // =========================================================================
    // RULE 7: Shoe Sterilization Done (Fig 7)
    // =========================================================================
    if (_wasLeftSterilizing && !leftIsSterilizing) {
      _triggerAlert(
        id: NotificationService.idLeftShoeSterilizing,
        title: 'Smart Shoe Sanitization Complete ✅',
        message: 'Left Shoe: Cleaning process is done',
        context: context,
      );
    }
    if (_wasRightSterilizing && !rightIsSterilizing) {
      _triggerAlert(
        id: NotificationService.idRightShoeSterilizing,
        title: 'Smart Shoe Sanitization Complete ✅',
        message: 'Right Shoe: Cleaning process is done',
        context: context,
      );
    }

    // Update state history
    _wasLeftSterilizing = leftIsSterilizing;
    _wasRightSterilizing = rightIsSterilizing;
    _lastCabinetStatus = cabinetStatus;
  }

  Future<void> _sendCommand(String uid, String cmd) async {
    try {
      final snapshot = await _db.child('users/$uid/system_id').get();
      if (snapshot.exists && snapshot.value != null) {
        final systemId = snapshot.value.toString();
        await _db.child('devices/$systemId/cabinet/command').set(cmd);
      }
    } catch (e) {
      debugPrint('Error sending cabinet command: $e');
    }
  }

  Future<void> _triggerAlert({
    required int id,
    required String title,
    required String message,
    required BuildContext context,
  }) async {
    // 1. Android Heads-Up Notification (Sound + Vibration + Banner)
    await _notificationService.showNotification(
      id: id,
      title: title,
      body: message,
    );

    // 2. Persist to Firebase Alerts Database
    await _notificationService.logAlertToFirebase(
      title: title,
      message: message,
    );

    // 3. In-App Floating Notification Banner
    if (context.mounted) {
      _showInAppNotification(context, title, message);
    }
  }

  void _showInAppNotification(BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1B2A4A),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
