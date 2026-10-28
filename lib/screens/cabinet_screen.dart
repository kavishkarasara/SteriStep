import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          ScreenHeader(
            greeting: 'Cabinet', 
            title: (data!.cabinetStatus == 'Cleaning process is done' || data!.cabinetStatus == 'Done') 
                ? 'Sterilization Complete ✅' 
                : data!.cabinetStatus == 'Idle' 
                    ? 'Ready to Sterilize' 
                    : 'Sterilization in Progress'
          ),
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
                          (data!.cabinetStatus == 'Done' || data!.cabinetStatus == 'Cleaning process is done') ? 'Sterilization Complete' :
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
                          final bool isDone = data!.cabinetStatus == 'Cleaning process is done' || data!.cabinetStatus == 'Done';
                          final bool isRunning = data!.cabinetStatus != 'Idle' && !isDone;
                          final bool isHeavy = data!.cabinetStatus == 'Sterilization in process';

                          if (isDone) {
                            s1 = 2; s2 = 2; s3 = 2; s4 = 2;
                          } else if (isRunning) {
                            s1 = 2; // Gas check done
                            
                            if (!isHeavy) {
                              s2 = -1; // Skipped (Strikethrough)
                            } else {
                              s2 = data!.cabinetProgress < 100 ? 1 : 2; // H2O2 Active together with UVC
                            }
                            
                            s3 = data!.cabinetProgress < 100 ? 1 : 2; 
                            s4 = data!.cabinetProgress > 80 ? 1 : 0; // Vent near end
                          }

                          final avgGas = ((data!.leftShoe.gasAnalog + data!.rightShoe.gasAnalog) / 2).round();
                          final avgPpm = GasMetrics.toPpm(avgGas);
                          final gasLevel = GasMetrics.getLevel(avgGas);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isRunning) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: (isHeavy ? Colors.purple : AppColors.blue).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isHeavy ? Icons.waves : Icons.lightbulb_outline,
                                        size: 16,
                                        color: isHeavy ? Colors.purple : AppColors.blue,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isHeavy ? 'Dual Mode: H₂O₂ Vapor & UVC Active' : 'Surface Mode: UVC Only (No H₂O₂)',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: isHeavy ? Colors.purple : AppColors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              _buildStage(text: 'Gas level check ($avgPpm ppm · Level $gasLevel)', state: s1, number: '1'),
                              _buildStage(
                                text: isHeavy 
                                    ? 'H₂O₂ vapor release (Active)' 
                                    : (!isRunning && !isDone 
                                        ? 'H₂O₂ vapor release' 
                                        : 'H₂O₂ vapor release (Not needed for Level 2)'), 
                                state: s2, 
                                number: '2'
                              ),
                              _buildStage(text: 'UVC light sterilization', state: s3, number: '3'),
                              _buildStage(text: 'Ventilation & cool-down', state: s4, number: '4'),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    MiniCard(
                      label: 'Inside Temp',
                      value: '${data!.cabinetTemperatureC.toStringAsFixed(1)}°C',
                    ),
                    const SizedBox(width: 8),
                    MiniCard(
                      label: 'Inside Humidity',
                      value: '${data!.cabinetHumidityPct.toStringAsFixed(0)}% RH',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (data!.isDoorOpen ? AppColors.danger : AppColors.safe).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                data!.isDoorOpen ? Icons.sensor_door_outlined : Icons.sensor_door,
                                color: data!.isDoorOpen ? AppColors.danger : AppColors.safe,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CABINET DOOR',
                                  style: TextStyle(fontSize: 10.4, color: AppColors.muted, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  data!.isDoorOpen ? 'Door Open (Safety Pause)' : 'Door Closed (Secure)',
                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.blueDark),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (data!.isDoorOpen)
                          Pill(text: 'Open · Warning', color: AppColors.danger, bgColor: AppColors.danger.withValues(alpha: 0.15))
                        else
                          Pill(text: 'Closed · Safe', color: AppColors.safe, bgColor: AppColors.safe.withValues(alpha: 0.15)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final bool isRunning = data!.cabinetStatus != 'Idle' && 
                                        data!.cabinetStatus != 'Done' && 
                                        data!.cabinetStatus != 'Cleaning process is done';

                  if (isRunning) {
                    return GhostButton(
                      text: 'Cancel Sterilization Cycle',
                      onPressed: () {
                        _cancelCycle(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sterilization cycle cancelled.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    );
                  }

                  final avgGas = ((data!.leftShoe.gasAnalog + data!.rightShoe.gasAnalog) / 2).round();
                  final gasLevel = GasMetrics.getLevel(avgGas);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        text: 'Start Dual Cycle (H₂O₂ Vapor + UVC)',
                        onPressed: () {
                          if (data!.isDoorOpen) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot start cycle: Cabinet door is OPEN! Please close door.'))
                            );
                            return;
                          }
                          _startCycle(context, 'START_HEAVY');
                        },
                      ),
                      const SizedBox(height: 8),
                      GhostButton(
                        text: 'Start UVC Only Cycle (15 min)',
                        onPressed: () {
                          if (data!.isDoorOpen) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot start cycle: Cabinet door is OPEN! Please close door.'))
                            );
                            return;
                          }
                          _startCycle(context, 'START_UVC');
                        },
                      ),
                      const SizedBox(height: 8),
                      GhostButton(
                        text: 'Auto Start (Level $gasLevel: ${gasLevel == 3 ? "Dual H₂O₂ + UVC" : "UVC Only"})',
                        onPressed: () {
                          if (data!.isDoorOpen) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot start cycle: Cabinet door is OPEN! Please close door.'))
                            );
                            return;
                          }
                          _startCycle(context, avgGas >= 2500 ? 'START_HEAVY' : 'START_UVC');
                        },
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // state: -1 = skipped, 0 = pending, 1 = active, 2 = done
  Widget _buildStage({required String text, required int state, String number = '✓'}) {
    final bool isDone = state == 2;
    final bool isActive = state == 1;
    final bool isSkipped = state == -1;
    
    Color bgColor = const Color(0xFFe9eef8);
    Color textColor = AppColors.blueDark;
    
    if (isDone) {
      bgColor = AppColors.safe;
      textColor = Colors.white;
    } else if (isActive) {
      bgColor = AppColors.blue;
      textColor = Colors.white;
    } else if (isSkipped) {
      bgColor = Colors.grey.withValues(alpha: 0.2);
      textColor = Colors.grey;
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
              isDone ? '✓' : (isSkipped ? '!' : number),
              style: TextStyle(color: textColor, fontSize: 10.4, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5, 
              color: isSkipped ? Colors.grey : AppColors.text,
              decoration: isSkipped ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  void _cancelCycle(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final systemId = prefs.getString('system_id');
    if (systemId != null && systemId.isNotEmpty) {
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/command').set('CANCEL');
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/cabinetStatus').set('Idle');
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/progress').set(0);
    }
  }

  void _startCycle(BuildContext context, String cmd) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final systemId = prefs.getString('system_id');
    if (systemId != null && systemId.isNotEmpty) {
      String status = cmd == 'START_HEAVY' ? 'Sterilization in process' : 'UVC Sterilization in process';
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/command').set(cmd);
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/cabinetStatus').set(status);
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/progress').set(0);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cmd == 'START_HEAVY' 
              ? 'Starting Dual Sterilization (H₂O₂ Vapor + UVC Light)...' 
              : 'Starting UVC Surface Sterilization...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
