import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';
import 'shared_widgets.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  DatabaseReference? _alertsRef;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isLoggedIn = true;
      _alertsRef = FirebaseDatabase.instance.ref('users/${user.uid}/alerts');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn || _alertsRef == null) {
      return const Center(child: Text('Please log in to see alerts.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(greeting: 'Recent', title: 'Alerts & History'),
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            stream: _alertsRef!.orderByChild('timestamp').limitToLast(50).onValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Center(child: Text('Error loading alerts', style: TextStyle(color: AppColors.muted)));
              }

              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return const Center(child: Text('No recent alerts.', style: TextStyle(color: AppColors.muted)));
              }

              final dataMap = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
              final alerts = dataMap.entries.map((e) {
                final val = Map<String, dynamic>.from(e.value as Map);
                return {
                  'key': e.key,
                  'title': val['title']?.toString() ?? 'Alert',
                  'message': val['message']?.toString() ?? '',
                  'timestamp': (val['timestamp'] as num?)?.toInt() ?? 0,
                };
              }).toList();

              // Sort newest first
              alerts.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 800));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  final time = DateTime.fromMillisecondsSinceEpoch(alert['timestamp'] as int);
                  
                  // Determine icon and color based on title
                  String iconStr = '◐';
                  Color color = AppColors.warning;
                  
                  final title = alert['title'] as String;
                  if (title.contains('Sterilization Required') || title.contains('Heavy Sterilization')) {
                    iconStr = '⚠';
                    color = AppColors.danger;
                  } else if (title.contains('Done') || title.contains('Complete')) {
                    iconStr = '✓';
                    color = AppColors.safe;
                  } else if (title.contains('Normal Sterilization')) {
                    iconStr = '◐';
                    color = AppColors.blue;
                  }

                  // Format time
                  final timeStr = '${time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}';
                  final dateStr = '${time.month}/${time.day}';

                  return _buildAlert(
                    iconStr: iconStr,
                    color: color,
                    title: title,
                    desc: '${alert['message']} · $dateStr $timeStr',
                  );
                },
              ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlert({
    required String iconStr,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(iconStr, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.6, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 11.2, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
