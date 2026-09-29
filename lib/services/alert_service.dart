import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
class AlertService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  // Track last alert times to prevent spamming
  DateTime? _lastShoeAlert;
  DateTime? _lastCabinetStartAlert;
  
  bool _wasLeftSterilizing = false;
  bool _wasRightSterilizing = false;
  String _lastCabinetStatus = 'Idle';

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

    // RULE 1: Smart Shoe Flow - High gas while wearing
    if (isFootDetected && maxGas >= 1200) {
      if (_lastShoeAlert == null || DateTime.now().difference(_lastShoeAlert!).inMinutes > 2) {
        _lastShoeAlert = DateTime.now();
        // Exact flowchart string
        _createAlert(uid, 'put the shoe in the sterilization cabinet Sterilization in process', 'Sterilization Required', context);
      }
    }

    // RULE 2: Cabinet Flow - Shoe placed in cabinet (no foot) and needs sterilization
    if (!isFootDetected && maxGas >= 1200 && !doorOpen && cabinetStatus == 'Idle') {
      if (_lastCabinetStartAlert == null || DateTime.now().difference(_lastCabinetStartAlert!).inMinutes > 2) {
        _lastCabinetStartAlert = DateTime.now();
        
        if (maxGas >= 2500) {
          _createAlert(uid, 'Shoe placed in cabinet. H2O2 + UVC Sterilization started.', 'Heavy Sterilization Started', context);
          _sendCommand(uid, 'START_HEAVY');
        } else {
          _createAlert(uid, 'Shoe placed in cabinet. UVC Sterilization started.', 'Normal Sterilization Started', context);
          _sendCommand(uid, 'START_UVC');
        }
      }
    }

    // RULE 3: Cabinet Sterilization Done
    if (cabinetStatus == 'Cleaning process is done' && _lastCabinetStatus != 'Cleaning process is done') {
      _createAlert(uid, 'Cleaning process is done', 'Cabinet Sterilization', context);
    }

    // RULE 4: Shoe Sterilization Started (Send Message: "Sterilization in process")
    if (!_wasLeftSterilizing && leftIsSterilizing) {
      _createAlert(uid, 'Sterilization in process', 'Left Shoe Sterilization', context);
    }
    if (!_wasRightSterilizing && rightIsSterilizing) {
      _createAlert(uid, 'Sterilization in process', 'Right Shoe Sterilization', context);
    }

    // RULE 5: Shoe Sterilization Done (Send Message: "Cleaning process is done")
    if (_wasLeftSterilizing && !leftIsSterilizing) {
      _createAlert(uid, 'Cleaning process is done', 'Left Shoe Sterilization', context);
    }
    if (_wasRightSterilizing && !rightIsSterilizing) {
      _createAlert(uid, 'Cleaning process is done', 'Right Shoe Sterilization', context);
    }

    _wasLeftSterilizing = leftIsSterilizing;
    _wasRightSterilizing = rightIsSterilizing;
    _lastCabinetStatus = cabinetStatus;
  }

  Future<void> _sendCommand(String uid, String cmd) async {
    final snapshot = await _db.child('users/$uid/system_id').get();
    if (snapshot.exists) {
      final systemId = snapshot.value.toString();
      await _db.child('devices/$systemId/cabinet/command').set(cmd);
    }
  }

  Future<void> _createAlert(String uid, String message, String title, BuildContext context) async {
    final alertId = _db.child('users/$uid/alerts').push().key;
    if (alertId == null) return;

    await _db.child('users/$uid/alerts/$alertId').set({
      'title': title,
      'message': message,
      'timestamp': ServerValue.timestamp,
    });
    
    if (!context.mounted) return;
    _showInAppNotification(context, title, message);
  }


  void _showInAppNotification(BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(message),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
