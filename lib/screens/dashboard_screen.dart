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

    final leftGas = widget.data!.leftShoe.gasAnalog;
    final rightGas = widget.data!.rightShoe.gasAnalog;
    final validGas = [
      if (leftGas > 0) leftGas,
      if (rightGas > 0) rightGas,
    ];
    final avgGas = validGas.isNotEmpty
        ? (validGas.reduce((a, b) => a + b) / validGas.length).round()
        : 0;

    final leftTemp = widget.data!.leftShoe.temperatureC;
    final rightTemp = widget.data!.rightShoe.temperatureC;
    final validTemps = [
      if (leftTemp > 0) leftTemp,
      if (rightTemp > 0) rightTemp,
    ];
    final avgTemp = validTemps.isNotEmpty ? validTemps.reduce((a, b) => a + b) / validTemps.length : 0.0;

    final leftHum = widget.data!.leftShoe.humidityPct;
    final rightHum = widget.data!.rightShoe.humidityPct;
    final validHums = [
      if (leftHum > 0) leftHum,
      if (rightHum > 0) rightHum,
    ];
    final avgHum = validHums.isNotEmpty ? validHums.reduce((a, b) => a + b) / validHums.length : 0.0;

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
                                          TextSpan(text: '${gas.ppm} ', style: const TextStyle(fontSize: 30.4)),
                                          const TextSpan(text: 'ppm', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                          TextSpan(text: '  (ADC: $avgGas)', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400)),
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
                            widthFactor: (avgGas / 4095.0).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(colors: [AppColors.blue, AppColors.blueLight]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              gas.level == 1 ? Icons.check_circle_outline : (gas.level == 2 ? Icons.lightbulb_outline : Icons.waves),
                              size: 14,
                              color: gas.color,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Recommended: ${gas.action}',
                                style: TextStyle(fontSize: 11.5, color: gas.color, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    MiniCard(label: 'Avg Shoe Temp', value: '${avgTemp.toStringAsFixed(1)}°C'),
                    const SizedBox(width: 12),
                    MiniCard(label: 'Avg Shoe Humidity', value: '${avgHum.toStringAsFixed(0)}%'),
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
                  text: 'Start Cabinet Cycle',
                  onPressed: () {
                    if (widget.data != null && widget.data!.isCabinetConnected) {
                      _showStartCycleSheet(context, avgGas);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cabinet is disconnected!')));
                    }
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
  
  void _sendCommand(BuildContext context, String node, String cmd) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final systemId = prefs.getString('system_id');
    
    if (systemId != null && systemId.isNotEmpty) {
      await FirebaseDatabase.instance.ref('devices/$systemId/$node/command').set(cmd);
      
      if (node == 'cabinet') {
        // Optimistic UI Update so the Cabinet screen shows it starting from 0 immediately
        String status = cmd == 'START_HEAVY' ? 'Sterilization in process' : 'UVC Sterilization in process';
        await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/cabinetStatus').set(status);
        await FirebaseDatabase.instance.ref('devices/$systemId/cabinet/progress').set(0);
      }
    }
  }

  void _showStartCycleSheet(BuildContext context, int avgGas) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final gasLevel = GasMetrics.getLevel(avgGas);
        final ppm = GasMetrics.toPpm(avgGas);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Sterilization Cycle',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.blueDark),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  'Shoe Gas Level: $ppm ppm (Level $gasLevel)',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                
                // Option 1: Dual Sterilization (UVC + H2O2 Vapor)
                ListTile(
                  tileColor: (gasLevel == 3 ? Colors.purple : AppColors.blue).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.waves, color: Colors.white, size: 20),
                  ),
                  title: const Text('Dual Sterilization (H₂O₂ + UVC)', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('20 min: H₂O₂ vapor & UVC light together'),
                  trailing: gasLevel == 3 
                      ? Pill(text: 'Recommended', color: Colors.purple, bgColor: Colors.purple.withValues(alpha: 0.15)) 
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendCommand(context, 'cabinet', 'START_HEAVY');
                    widget.onNavigate(2);
                  },
                ),
                const SizedBox(height: 10),

                // Option 2: UVC Only
                ListTile(
                  tileColor: (gasLevel == 2 ? AppColors.warning : AppColors.blue).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.blue,
                    child: Icon(Icons.lightbulb_outline, color: Colors.white, size: 20),
                  ),
                  title: const Text('UVC Light Only Cycle', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('15 min: Surface sterilization without H₂O₂'),
                  trailing: gasLevel == 2 
                      ? Pill(text: 'Recommended', color: AppColors.warning, bgColor: AppColors.warning.withValues(alpha: 0.15)) 
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendCommand(context, 'cabinet', 'START_UVC');
                    widget.onNavigate(2);
                  },
                ),
                const SizedBox(height: 14),

                // Option 3: Auto Start
                PrimaryButton(
                  text: 'Auto Start (${gasLevel == 3 ? "Dual: H₂O₂ + UVC" : "UVC Only"})',
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendCommand(context, 'cabinet', avgGas >= 2500 ? 'START_HEAVY' : 'START_UVC');
                    widget.onNavigate(2);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
