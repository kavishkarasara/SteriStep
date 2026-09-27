import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import 'login_screen.dart';

class ScreenHeader extends StatelessWidget {
  final String greeting;
  final String title;

  const ScreenHeader({super.key, required this.greeting, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 38, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_logged_in', false);
              
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class ConnectingIndicator extends StatefulWidget {
  const ConnectingIndicator({super.key});

  @override
  State<ConnectingIndicator> createState() => _ConnectingIndicatorState();
}

class _ConnectingIndicatorState extends State<ConnectingIndicator> {
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isOffline = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(greeting: 'System Status', title: 'Connection'),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isOffline)
                    const CircularProgressIndicator(color: AppColors.blueDark)
                  else
                    const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text(
                    _isOffline ? 'ESP32 Disconnected' : 'Connecting to ESP32...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isOffline ? AppColors.danger : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Make sure your ESP32 is turned on and connected to Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const PrimaryButton({super.key, required this.text, required this.onPressed});

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.blueBg1, AppColors.blueBg2],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.blue.withValues(alpha: _isPressed ? 0.15 : 0.3),
                blurRadius: _isPressed ? 10 : 20,
                offset: Offset(0, _isPressed ? 5 : 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14.0),
          alignment: Alignment.center,
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.6),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const GhostButton({super.key, required this.text, required this.onPressed});

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: _isPressed ? const Color(0xFFf3f7ff) : Colors.white,
            border: Border.all(color: const Color(0xFFd7e0f5), width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(12.0),
          alignment: Alignment.center,
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.blueDark, fontWeight: FontWeight.w600, fontSize: 12.8),
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bgColor;
  final bool showDot;

  const Pill({super.key, required this.text, required this.color, required this.bgColor, this.showDot = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11.2, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class MiniCard extends StatelessWidget {
  final String label;
  final String value;

  const MiniCard({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(fontSize: 10.4, color: AppColors.muted, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 20.8, fontWeight: FontWeight.w700, color: AppColors.blueDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 18, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.2,
          fontWeight: FontWeight.w700,
          color: AppColors.blueDark,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
