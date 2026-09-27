import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';
import '../theme.dart';
import 'shared_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final SensorSnapshot? data;
  final Function(int) onNavigate;

  const DashboardScreen({super.key, required this.data, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = 'Nuthara';
  String _greeting = 'Good evening,';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _updateGreeting();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'User';
    });
  }

  void _updateGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Good morning,';
    } else if (hour < 17) {
      _greeting = 'Good afternoon,';
    } else {
      _greeting = 'Good evening,';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return const ConnectingIndicator();
    }

    final avgGas = ((widget.data!.leftShoe.gasAnalog + widget.data!.rightShoe.gasAnalog) / 2).round();
    final avgTemp = widget.data!.cabinetTemperatureC;
    final avgHum = widget.data!.cabinetHumidityPct;

    final gas = GasStatus.fromReading(avgGas);

    return RefreshIndicator(
      onRefresh: () async {
        // Since Firebase streams real-time data automatically, 
        // this just provides haptic feedback and a small delay for UI satisfaction.
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(greeting: _greeting, title: '$_userName 👋'),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('AVERAGE GAS LEVEL', style: TextStyle(fontSize: 11.2, color: AppColors.muted, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(color: AppColors.blueDark, fontWeight: FontWeight.w700),
                                        children: [
                                          TextSpan(text: '$avgGas ', style: const TextStyle(fontSize: 30.4)),
                                          const TextSpan(text: 'ppm', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Pill(
                              text: gas.label,
                              color: gas.color,
                              bgColor: gas.color.withValues(alpha: 0.15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(color: const Color(0xFFe9eef8), borderRadius: BorderRadius.circular(6)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (avgGas / 3000).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(colors: [AppColors.blue, AppColors.blueLight]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    MiniCard(label: 'Avg Temp', value: '${avgTemp.toStringAsFixed(1)}°C'),
                    const SizedBox(width: 12),
                    MiniCard(label: 'Avg Humidity', value: '${avgHum.toStringAsFixed(0)}%'),
                  ],
                ),
                const SectionLabel('Quick Status'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: const Text('Smart Shoe', style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: AppColors.text)),
                            ),
                            const SizedBox(width: 8),
                            if (!widget.data!.isLeftConnected && !widget.data!.isRightConnected)
                              Pill(text: 'Offline', color: AppColors.muted, bgColor: AppColors.muted.withValues(alpha: 0.15))
                            else if (avgGas >= 1200)
                              Pill(text: 'Needs Sterilization', color: AppColors.danger, bgColor: AppColors.danger.withValues(alpha: 0.15))
                            else
                              Pill(text: 'Connected', color: AppColors.safe, bgColor: AppColors.safe.withValues(alpha: 0.15)),
                          ],
                        ),
                        if ((widget.data!.isLeftConnected || widget.data!.isRightConnected) && avgGas >= 1200) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'Alert: High gas level. Put the shoe in the sterilization cabinet.',
                              style: TextStyle(fontSize: 11.2, color: AppColors.danger, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: const Text('Cabinet', style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: AppColors.text)),
                            ),
                            const SizedBox(width: 8),
                            if (!widget.data!.isCabinetConnected)
                              Pill(text: 'Offline', color: AppColors.muted, bgColor: AppColors.muted.withValues(alpha: 0.15))
                            else
                              Pill(
                                text: widget.data!.cabinetStatus, 
                                color: widget.data!.cabinetStatus == 'Idle' || widget.data!.cabinetStatus == 'Done' ? AppColors.safe : AppColors.warning, 
                                bgColor: widget.data!.cabinetStatus == 'Idle' || widget.data!.cabinetStatus == 'Done' ? AppColors.safe.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15)
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                PrimaryButton(
                  text: 'Start Sterilization',
                  onPressed: () {
                    // Send command to Firebase
                    _sendCommand(context, avgGas >= 2500 ? 'START_HEAVY' : 'START_UVC');
                    widget.onNavigate(2); // Go to Cabinet screen
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
  
  void _sendCommand(BuildContext context, String cmd) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final systemId = prefs.getString('system_id');
    
    if (systemId != null && systemId.isNotEmpty) {
      await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/command').set(cmd);
    }
  }
}
