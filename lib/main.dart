import 'package:flutter/material.dart';
import 'models/sensor_data.dart';
import 'screens/dashboard_screen.dart';
import 'screens/shoe_screen.dart';
import 'screens/cabinet_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/login_screen.dart';
import 'services/alert_service.dart';
import 'services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }
  
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  await initializeBackgroundService();

  runApp(const SteriStepApp());
}

class SteriStepApp extends StatelessWidget {
  const SteriStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SteriStep',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () async {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
                isLoggedIn ? const RootShell() : const LoginScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blueBg1,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'lib/assets/Logo.jpeg',
                height: 120,
                width: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'SteriStep',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Smart Sterilization System',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 50),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.8)),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;
  SensorSnapshot? _latest;
  final _sensorService = ESP32SensorService();
  final _alertService = AlertService();

  @override
  void initState() {
    super.initState();
    
    // Request permission once when logged in
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
        
    // Request battery optimization ignore
    _requestBatteryPermission();

    _sensorService.start(
      onDataRaw: (data) {
        if (mounted) {
          _alertService.evaluateData(data, context);
        }
      },
    );
    _sensorService.stream.listen((snapshot) {
      if (mounted) setState(() => _latest = snapshot);
    });
  }

  @override
  void dispose() {
    _sensorService.dispose();
    super.dispose();
  }

  Future<void> _requestBatteryPermission() async {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  void _goTo(int index) => setState(() => _tabIndex = index);

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(data: _latest, onNavigate: _goTo),
      ShoeScreen(data: _latest),
      CabinetScreen(data: _latest, onNavigate: _goTo),
      const AlertsScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFf3f7ff),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35],
            colors: [AppColors.blueBg1, Color(0xFFf3f7ff)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.02, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_tabIndex),
                    child: screens[_tabIndex],
                  ),
                ),
              ),
              _buildNavBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom, // Handle notch/home indicator
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFeef1f8))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, 'Home', Icons.home_outlined),
          _navItem(1, 'Shoe', '👟'),
          _navItem(2, 'Cabinet', '🧴'),
          _navItem(3, 'Alerts', '🔔'),
        ],
      ),
    );
  }

  Widget _navItem(int index, String label, dynamic iconContent) {
    final isActive = _tabIndex == index;
    final color = isActive ? AppColors.blueDark : AppColors.muted;
    
    Widget iconWidget;
    if (iconContent is IconData) {
      iconWidget = Icon(
        iconContent,
        key: ValueKey<bool>(isActive),
        size: 26,
        color: color,
      );
    } else {
      iconWidget = Text(
        iconContent.toString(),
        key: ValueKey<bool>(isActive),
        style: TextStyle(
          fontSize: index == 3 ? 17 : 21, // Slightly smaller for Alert
          color: color,
          height: 1.2,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _goTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: isActive ? 8 : 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.blueDark.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
              child: iconWidget,
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                fontSize: isActive ? 11 : 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
