import 'package:flutter/material.dart';

/// TrainMate colors — athletic teal + orange for CTA.
abstract final class AppColors {
  static const Color seedTeal = Color(0xFF0D9488);
  static const Color seedTealDark = Color(0xFF0F766E);
  static const Color accentOrange = Color(0xFFEA580C);
  static const Color accentAmber = Color(0xFFF59E0B);

  static const Color slate950 = Color(0xFF0F172A);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color surface = Color(0xFFF8FAFC);

  static const List<Color> heroGradient = [
    Color(0xFF0D9488),
    Color(0xFF0E7490),
    Color(0xFF134E4A),
  ];

  static const List<Color> splashGradient = [
    Color(0xFF042F2E),
    Color(0xFF0D9488),
    Color(0xFF2DD4BF),
  ];
}
