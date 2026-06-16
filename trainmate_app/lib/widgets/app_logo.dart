import 'package:flutter/material.dart';

/// In-app brand/icon image. This is separate from the splash logo.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 56,
    this.fit = BoxFit.contain,
  });

  final double size;
  final BoxFit fit;

  /// App icon/brand asset (used inside UI, and also by launcher icon generator).
  static const String assetPath = 'assets/images/app_icon.png';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        fit: fit,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Icon(
          Icons.fitness_center_rounded,
          size: size * 0.85,
          color: Colors.white,
        ),
      ),
    );
  }
}
