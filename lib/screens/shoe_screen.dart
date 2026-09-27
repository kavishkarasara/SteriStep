import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../theme.dart';
import 'shared_widgets.dart';

class ShoeScreen extends StatefulWidget {
  final SensorSnapshot? data;

  const ShoeScreen({super.key, required this.data});

  @override
  State<ShoeScreen> createState() => _ShoeScreenState();
}

class _ShoeScreenState extends State<ShoeScreen> {
  bool _isLeftSelected = false; // Default to Right Foot

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return const ConnectingIndicator();
    }

    final snapshot = widget.data!;
    final shoeData = _isLeftSelected ? snapshot.leftShoe : snapshot.rightShoe;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(greeting: 'Live from', title: 'Smart Shoe'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Foot Selector Toggle
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isLeftSelected = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isLeftSelected ? AppColors.blueDark : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.blueDark.withValues(alpha: _isLeftSelected ? 0.0 : 0.1)),
                            boxShadow: _isLeftSelected
                                ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))]
                                : [],
                          ),
                          alignment: Alignment.center,
                          child: Text('Left Shoe', style: TextStyle(color: _isLeftSelected ? Colors.white : AppColors.muted, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isLeftSelected = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isLeftSelected ? AppColors.blueDark : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.blueDark.withValues(alpha: !_isLeftSelected ? 0.0 : 0.1)),
                            boxShadow: !_isLeftSelected
                                ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))]
                                : [],
                          ),
                          alignment: Alignment.center,
                          child: Text('Right Shoe', style: TextStyle(color: !_isLeftSelected ? Colors.white : AppColors.muted, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('${_isLeftSelected ? 'LEFT' : 'RIGHT'} FOOT PRESSURE MAP', style: const TextStyle(fontSize: 11.2, color: AppColors.muted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 240,
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.flip(
                                flipX: !_isLeftSelected, // Flipped logic to match image orientation
                                child: Image.asset('lib/assets/foot.png', height: 240, fit: BoxFit.contain),
                              ),
                              CustomPaint(
                                size: const Size(double.infinity, 240),
                                painter: _SingleFootprintPainter(
                                  shoeData.toePressure, 
                                  shoeData.midfootPressure, 
                                  shoeData.heelPressure, 
                                  _isLeftSelected
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Heel pressure elevated — shift weight', style: TextStyle(fontSize: 10.4, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    MiniCard(label: 'Gas (MQ-137)', value: '${shoeData.gasAnalog} ppm'),
                    const SizedBox(width: 12),
                    MiniCard(label: 'Skin Temp', value: '${shoeData.temperatureC.toStringAsFixed(1)}°C'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    MiniCard(label: 'Humidity', value: '${shoeData.humidityPct.toStringAsFixed(0)}% RH'),
                    const SizedBox(width: 12),
                    const MiniCard(label: 'Battery', value: '76%'),
                  ],
                ),
                const SectionLabel('In-shoe Vapor'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: const Text(
                            'Micro-atomizer',
                            style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: AppColors.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Pill(text: 'Standby', color: AppColors.safe, bgColor: AppColors.safe.withValues(alpha: 0.15)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                GhostButton(
                  text: 'Trigger Manual Mist',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Manual mist activated for ${_isLeftSelected ? 'Left' : 'Right'} shoe.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _SingleFootprintPainter extends CustomPainter {
  final double toePressure;
  final double midPressure;
  final double heelPressure;
  final bool isLeft;

  _SingleFootprintPainter(this.toePressure, this.midPressure, this.heelPressure, this.isLeft);

  Color _getColorForPressure(double pressure) {
    if (pressure < 15) return AppColors.safe; // Green for low pressure
    if (pressure < 50) return AppColors.warning; // Yellow for medium
    return AppColors.danger; // Red for high
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final blurPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    // Toe heatmap (dynamic)
    blurPaint.color = _getColorForPressure(toePressure).withValues(alpha: 0.85);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.22), width: h * 0.5, height: h * 0.35),
      blurPaint,
    );

    // Mid heatmap (dynamic)
    blurPaint.color = _getColorForPressure(midPressure).withValues(alpha: 0.85);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.55), width: h * 0.45, height: h * 0.4),
      blurPaint,
    );

    // Heel heatmap (dynamic)
    blurPaint.color = _getColorForPressure(heelPressure).withValues(alpha: 0.85);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.85), width: h * 0.4, height: h * 0.3),
      blurPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
