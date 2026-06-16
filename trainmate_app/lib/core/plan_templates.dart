/// Built-in plan templates and exercise pools.
///
/// IMPORTANT: every exercise listed here MUST exist in the app's real
/// exercise catalog (`assets/models/classes.json`), because those are the
/// only movements the workout tracker / ML classifier can recognise.
class PlanTemplates {
  PlanTemplates._();

  static const builtIn = [
    'Strength',
    'Muscle Gain',
    'Weight Loss',
    'Endurance',
    'Mobility',
  ];

  /// The only exercises the app actually supports (kept in sync with
  /// `assets/models/classes.json`).
  static const supportedExercises = [
    'barbell biceps curl',
    'push-up',
    'shoulder press',
    'squat',
  ];

  static const exercisesByTemplate = {
    'Strength': [
      'squat',
      'shoulder press',
      'push-up',
    ],
    'Muscle Gain': [
      'push-up',
      'barbell biceps curl',
      'shoulder press',
      'squat',
    ],
    'Weight Loss': [
      'squat',
      'push-up',
    ],
    'Endurance': [
      'push-up',
      'squat',
      'shoulder press',
    ],
    'Mobility': [
      'squat',
      'push-up',
    ],
  };

  static List<String> exercisesFor(String template) {
    return List<String>.from(
      exercisesByTemplate[template] ?? exercisesByTemplate['Muscle Gain']!,
    );
  }

  static String prescriptionCategory(String? templateCategory, String planName) {
    if (templateCategory != null &&
        templateCategory.isNotEmpty &&
        builtIn.contains(templateCategory)) {
      return templateCategory;
    }
    if (builtIn.contains(planName)) return planName;
    return 'Muscle Gain';
  }
}
