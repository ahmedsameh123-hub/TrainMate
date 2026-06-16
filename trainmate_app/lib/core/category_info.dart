import '../l10n/app_text.dart';

class CategoryInfo {  CategoryInfo({
    required this.focus,
    required this.description,
    required this.bullets,
  });

  final String focus;
  final String description;
  final List<String> bullets;
}

CategoryInfo getCategoryInfo(String category, AppText t) {
  final isAr = t.isArabic;
  switch (category) {    case 'Strength':
      return CategoryInfo(
        focus: isAr ? 'التركيز: زيادة القوة' : 'Focus: Max strength',
        description: isAr
            ? 'هذه الفئة تبني قدرة أعلى على رفع أوزان ثقيلة مع تقدم تدريجي.'
            : 'This category builds your ability to move heavier loads progressively.',
        bullets: isAr
            ? ['عدد تكرارات أقل وجودة أعلى', 'زيادة الحمل التدريجي', 'راحة أطول بين الجولات']
            : ['Lower reps with better quality', 'Progressive overload planning', 'Longer set rest for performance'],
      );
    case 'Muscle Gain':
      return CategoryInfo(
        focus: isAr ? 'التركيز: تضخم عضلي' : 'Focus: Hypertrophy',
        description: isAr
            ? 'موجهة لزيادة الكتلة العضلية عبر حجم تمرين أعلى.'
            : 'Designed to increase muscle size through higher training volume.',
        bullets: isAr
            ? ['حجم تمرين أعلى', 'تكنيك مضبوط بمدى حركة كامل', 'تغذية واستشفاء أساسيان']
            : ['Higher volume sessions', 'Strict form with full range', 'Recovery and nutrition emphasis'],
      );
    case 'Weight Loss':
      return CategoryInfo(
        focus: isAr ? 'التركيز: خفض الدهون' : 'Focus: Fat loss',
        description: isAr
            ? 'تمزج تمارين مقاومة مع نشاط أعلى لتحسين معدل الحرق.'
            : 'Combines resistance work with higher activity to improve calorie burn.',
        bullets: isAr
            ? ['كثافة أعلى وراحة أقل', 'متابعة الالتزام الأسبوعي', 'أفضل مع عجز سعرات محسوب']
            : ['Higher density sessions', 'Weekly consistency tracking', 'Works best with caloric deficit'],
      );
    case 'Endurance':
      return CategoryInfo(
        focus: isAr ? 'التركيز: التحمل' : 'Focus: Endurance',
        description: isAr
            ? 'تحسين القدرة على الأداء لفترات أطول بدون هبوط سريع.'
            : 'Improves your ability to sustain effort for longer durations.',
        bullets: isAr
            ? ['تكرارات أعلى', 'استراحة أقصر', 'تدرج أسبوعي في التحمل']
            : ['Higher rep ranges', 'Shorter rest windows', 'Week-over-week endurance progression'],
      );
    default:
      return CategoryInfo(
        focus: isAr ? 'التركيز: المرونة والحركة' : 'Focus: Mobility',
        description: isAr
            ? 'تزيد جودة الحركة وتقلل التيبّس وتحسن وضعية الجسم.'
            : 'Improves movement quality, reduces stiffness, and supports posture.',
        bullets: isAr
            ? ['مرونة المفاصل', 'تحكم أفضل في الحركة', 'تقليل مخاطر الإصابة']
            : ['Joint mobility emphasis', 'Better movement control', 'Lower injury risk'],
      );
  }
}
