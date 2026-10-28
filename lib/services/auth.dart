import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // Sign In
  Future<UserCredential> signIn(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    final prefs = await SharedPreferences.getInstance();
    
    // Fetch system ID from Firebase when logging in (with error fallback)
    await prefs.setString('user_uid', userCredential.user!.uid);
    try {
      final snapshot = await _db.child('users/${userCredential.user!.uid}/system_id').get();
      if (snapshot.exists && snapshot.value != null) {
        await prefs.setString('system_id', snapshot.value.toString());
      }
    } catch (e) {
      debugPrint('Warning: Could not fetch system_id from Firebase: $e');
    }

    // If still no system_id in prefs, provide fallback to default
    if (prefs.getString('system_id') == null || prefs.getString('system_id')!.isEmpty) {
      await prefs.setString('system_id', 'steristep_001');
    }
    
    return userCredential;
  }

  // Sign Up
  Future<UserCredential> signUp(String email, String password, String name, String systemId) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    // Always save name, system ID and user_uid to shared prefs immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_uid', userCredential.user!.uid);
    await prefs.setString('user_name', name);
    await prefs.setString('system_id', systemId.isNotEmpty ? systemId : 'steristep_001');

    // Save systemId to Firebase under user's profile (with error guard)
    try {
      await _db.child('users/${userCredential.user!.uid}/system_id').set(systemId);
    } catch (e) {
      debugPrint('Warning: Could not save system_id to Firebase RTDB: $e');
    }
    
    return userCredential;
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('user_uid');
  }

  // Save successful login session locally
  Future<void> saveLoginSession(String email, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('user_email', email);
    if (name.isNotEmpty) {
      await prefs.setString('user_name', name);
    }
  }
}
