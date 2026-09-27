import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const blueDark = Color(0xFF0b3d91);
  static const blue = Color(0xFF1565c0);
  static const blueLight = Color(0xFF3f8ee8);
  static const blueBg1 = Color(0xFF0a2a66);
  static const blueBg2 = Color(0xFF1c63c9);
  
  static const cardBg = Color(0xFFffffff);
  static const text = Color(0xFF16213a);
  static const muted = Color(0xFF6b7a99);
  
  static const safe = Color(0xFF2ecc71);
  static const warning = Color(0xFFf5a623);
  static const danger = Color(0xFFe94b4b);
  static const bgTop = Color(0xFFeef3fb);
  static const bgMid = Color(0xFFdfe9fb);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent, // Background handled manually via gradients
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      primary: AppColors.blue,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardBg,
      elevation: 8,
      shadowColor: const Color(0xFF14285a).withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 14),
    ),
  );
}

class GasStatus {
  final String label;
  final Color color;
  final String action;
  const GasStatus(this.label, this.color, this.action);

  factory GasStatus.fromReading(int analog) {
    if (analog <= 1200) {
      return const GasStatus('Minimal Bacteria', AppColors.safe, 'Surgical vapor only (30s)');
    } else if (analog <= 2500) {
      return const GasStatus('Moderate Growth', AppColors.warning, 'UVC Light only (15 min)');
    }
    return const GasStatus('Heavy Growth', AppColors.danger, 'UVC + Surgical Vapor');
  }
}

class HumidityStatus {
  final String label;
  final Color color;
  const HumidityStatus(this.label, this.color);

  factory HumidityStatus.fromValue(double rh) {
    if (rh <= 65) return const HumidityStatus('Normal', AppColors.safe);
    if (rh <= 75) return const HumidityStatus('Warning · Drying needed', AppColors.warning);
    return const HumidityStatus('Danger · Skin breakdown risk', AppColors.danger);
  }
}
