import 'package:flutter/material.dart';
import '../theme.dart';

void showSterilizationModal(BuildContext context, VoidCallback onComplete) {
  showGeneralDialog(
    context: context,
    pageBuilder: (context, animation, secondaryAnimation) {
      return SterilizationModal(onComplete: onComplete);
    },
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class SterilizationModal extends StatefulWidget {
  final VoidCallback onComplete;

  const SterilizationModal({super.key, required this.onComplete});

  @override
  State<SterilizationModal> createState() => _SterilizationModalState();
}

class _SterilizationModalState extends State<SterilizationModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6), // 6 seconds for the animation
    );
    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onComplete(); // e.g. navigate to cabinet screen
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blueBg1.withValues(alpha: 0.98),
      body: Center(
        child: AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, child) {
            final progress = _progressAnimation.value;
            final isDone = progress >= 1.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Shoe Area
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Dark/Greyscale Shoe (Not sterilized)
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.grey, Colors.black54],
                        ).createShader(bounds),
                        blendMode: BlendMode.srcATop,
                        child: const Text(
                          '👟',
                          style: TextStyle(fontSize: 120),
                        ),
                      ),
                      
                      // Bright/Sterilized Shoe (Revealed from bottom to top)
                      ClipRect(
                        clipper: _ProgressClipper(progress),
                        child: ShaderMask(
                          shaderCallback: (bounds) => RadialGradient(
                            center: Alignment.center,
                            radius: 1.0,
                            colors: [Colors.cyanAccent, AppColors.blueLight],
                          ).createShader(bounds),
                          blendMode: BlendMode.srcATop,
                          child: const Text(
                            '👟',
                            style: TextStyle(fontSize: 120),
                          ),
                        ),
                      ),
                      
                      // Scanning Laser Line
                      if (!isDone)
                        Positioned(
                          bottom: 20 + (progress * 140), // Moves up based on progress
                          child: Container(
                            width: 140,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.cyanAccent.withValues(alpha: 0.8),
                                  blurRadius: 15,
                                  spreadRadius: 5,
                                ),
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
                
                // Status Text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    isDone ? 'Sterilization Complete!' : 'Sterilizing in Progress...',
                    key: ValueKey(isDone),
                    style: TextStyle(
                      color: isDone ? Colors.cyanAccent : Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Percentage
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;
  _ProgressClipper(this.progress);

  @override
  Rect getClip(Size size) {
    // Reveal from bottom to top
    return Rect.fromLTWH(
      0,
      size.height - (size.height * progress),
      size.width,
      size.height * progress,
    );
  }

  @override
  bool shouldReclip(_ProgressClipper oldClipper) => oldClipper.progress != progress;
}

