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

class GasMetrics {
  /// Converts raw MQ135 analog ADC reading (0-4095) to approximate PPM as defined in Table 3 of the project report
  static int toPpm(int analog) {
    if (analog <= 0) return 0;
    if (analog <= 1200) {
      // Level 1: 0 - 1200 ADC -> 0 - 1300 PPM
      return ((analog / 1200.0) * 1300.0).round();
    } else if (analog <= 2500) {
      // Level 2: 1201 - 2500 ADC -> 1300 - 2300 PPM
      return (1300.0 + ((analog - 1200.0) / 1300.0) * 1000.0).round();
    } else {
      // Level 3: 2501 - 4095 ADC -> 2300 - 3800 PPM
      return (2300.0 + ((analog - 2500.0) / 1595.0) * 1500.0).clamp(2300.0, 4000.0).round();
    }
  }

  /// Returns Level 1, 2, or 3 based on Table 3
  static int getLevel(int analog) {
    if (analog <= 1200) return 1;
    if (analog <= 2500) return 2;
    return 3;
  }
}

class GasStatus {
  final String label;
  final Color color;
  final String action;
  final int level;
  final int ppm;
  const GasStatus(this.label, this.color, this.action, this.level, this.ppm);

  factory GasStatus.fromReading(int analog) {
    final ppm = GasMetrics.toPpm(analog);
    if (analog <= 1200) {
      return GasStatus('Minimal Bacteria (Level 1)', AppColors.safe, 'Surgical vapor only (30s)', 1, ppm);
    } else if (analog <= 2500) {
      return GasStatus('Moderate Growth (Level 2)', AppColors.warning, 'UVC Light only (15 min)', 2, ppm);
    }
    return GasStatus('Heavy Growth (Level 3)', AppColors.danger, 'UVC + H₂O₂ Surgical Vapor', 3, ppm);
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
