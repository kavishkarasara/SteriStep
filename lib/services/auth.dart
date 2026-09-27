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
    
    // Fetch system ID from Firebase when logging in
    final snapshot = await _db.child('users/${userCredential.user!.uid}/system_id').get();
    if (snapshot.exists) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('system_id', snapshot.value.toString());
    }
    
    return userCredential;
  }

  // Sign Up
  Future<UserCredential> signUp(String email, String password, String name, String systemId) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    // Save systemId to Firebase under user's profile
    await _db.child('users/${userCredential.user!.uid}/system_id').set(systemId);
    
    // Save name and system ID to shared prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    await prefs.setString('system_id', systemId);
    
    return userCredential;
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
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
