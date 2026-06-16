import 'package:flutter/material.dart';

import '../core/colors.dart';
import 'app_logo.dart';

/// Shared layout for auth screens: gradient header + form card.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.child,
  });

  final String heroTitle;
  final String heroSubtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.heroGradient,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const AppLogo(size: 34),
              ),
              const SizedBox(height: 28),
              Text(
                heroTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                heroSubtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 6,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              physics: const BouncingScrollPhysics(),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
