import 'package:flutter/material.dart';

import '../plans/plan_form_screen.dart';

/// Onboarding step 2 — pick a ready plan or create a custom one.
class OnboardingPlanScreen extends StatelessWidget {
  const OnboardingPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlanFormScreen(onboardingMode: true);
  }
}
