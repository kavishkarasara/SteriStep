import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../theme.dart';
import 'shared_widgets.dart';

class CabinetScreen extends StatelessWidget {
  final SensorSnapshot? data;
  final Function(int)? onNavigate;

  const CabinetScreen({super.key, required this.data, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const ConnectingIndicator();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(greeting: 'Cabinet', title: 'Sterilization in Progress'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('CYCLE PROGRESS', style: TextStyle(fontSize: 11.2, color: AppColors.muted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('${data!.cabinetProgress}%', style: const TextStyle(fontSize: 38.4, fontWeight: FontWeight.w700, color: AppColors.blueDark)),
                        const SizedBox(height: 12),
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(color: const Color(0xFFe9eef8), borderRadius: BorderRadius.circular(6)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (data!.cabinetProgress / 100).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(colors: [AppColors.blue, AppColors.blueLight]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data!.cabinetStatus == 'Done' ? 'Sterilization Complete' :
                          data!.cabinetStatus == 'Idle' ? 'Ready to Sterilize' : 'Est. ${60 - (data!.cabinetProgress / 100 * 60).toInt()} sec remaining', 
                          style: const TextStyle(fontSize: 12.0, color: AppColors.muted)
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CYCLE STAGES', style: TextStyle(fontSize: 11.2, color: AppColors.muted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        Builder(builder: (context) {
                          int s1 = 0, s2 = 0, s3 = 0, s4 = 0;
                          if (data!.cabinetStatus == 'Done') {
                            s1 = 2; s2 = 2; s3 = 2; s4 = 2;
                          } else if (data!.cabinetStatus != 'Idle') {
                            s1 = 2;
                            if (data!.cabinetProgress < 30) {
                              if (data!.cabinetStatus.contains('H2O2')) {
                                s2 = 1; s3 = 0; s4 = 0;
                              } else {
                                s2 = 0; s3 = 1; s4 = 0; // Skip H2O2
                              }
                            } else if (data!.cabinetProgress < 80) {
                              if (data!.cabinetStatus.contains('H2O2')) s2 = 2;
                              s3 = 1; s4 = 0;
                            } else {
                              if (data!.cabinetStatus.contains('H2O2')) s2 = 2;
                              s3 = 2; s4 = 1;
                            }
                          }

                          final avgGas = ((data!.leftShoe.gasAnalog + data!.rightShoe.gasAnalog) / 2).round();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStage(text: 'Gas level check ($avgGas ppm)', state: s1, number: '1'),
                              _buildStage(text: 'H₂O₂ vapor release', state: s2, number: '2'),
                              _buildStage(text: 'UVC light sterilization', state: s3, number: '3'),
                              _buildStage(text: 'Ventilation & cool-down', state: s4, number: '4'),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: const Text(
                            'Door Sensor',
                            style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: AppColors.text),
                          ),
                        ),
                        if (data!.isDoorOpen)
                          Pill(text: 'Open · Warning', color: AppColors.danger, bgColor: AppColors.danger.withValues(alpha: 0.15))
                        else
                          Pill(text: 'Closed · Safe', color: AppColors.safe, bgColor: AppColors.safe.withValues(alpha: 0.15)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                GhostButton(
                  text: 'Cancel Cycle',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sterilization cycle cancelled.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    if (onNavigate != null) onNavigate!(0); // Go back to home
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

  // state: 0 = pending, 1 = active, 2 = done
  Widget _buildStage({required String text, required int state, String number = '✓'}) {
    final bool isDone = state == 2;
    final bool isActive = state == 1;
    
    Color bgColor = const Color(0xFFe9eef8);
    Color textColor = AppColors.blueDark;
    
    if (isDone) {
      bgColor = AppColors.safe;
      textColor = Colors.white;
    } else if (isActive) {
      bgColor = AppColors.blue;
      textColor = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              isDone ? '✓' : number,
              style: TextStyle(color: textColor, fontSize: 10.4, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
