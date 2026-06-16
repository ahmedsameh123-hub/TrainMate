import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../models/workout_plan_model.dart';

class UserProfileData {
  UserProfileData({
    this.age,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.profileImageBase64,
  });

  final int? age;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final String? profileImageBase64;

  bool get isComplete =>
      age != null && sex != null && heightCm != null && weightKg != null;
}

class UserPlanData {
  UserPlanData({
    this.category,
    this.durationWeeks,
    this.beforePhotoBase64,
    this.afterPhotoBase64,
    this.onboardingCompleted = false,
  });

  final String? category;
  final int? durationWeeks;
  final String? beforePhotoBase64;
  final String? afterPhotoBase64;
  final bool onboardingCompleted;

  bool get isComplete =>
      category != null &&
      category!.trim().isNotEmpty &&
      durationWeeks != null &&
      durationWeeks! >= 4 &&
      durationWeeks! <= 12 &&
      beforePhotoBase64 != null &&
      beforePhotoBase64!.trim().isNotEmpty &&
      onboardingCompleted;
}

class MeData {
  MeData({
    required this.id,
    required this.email,
    required this.name,
    this.profile,
    this.plan,
    this.workoutPlans = const [],
    this.activePlan,
  });

  final int id;
  final String email;
  final String? name;
  final UserProfileData? profile;
  final UserPlanData? plan;
  final List<WorkoutPlanModel> workoutPlans;
  final WorkoutPlanModel? activePlan;

  bool get needsProfileStep =>
      name == null ||
      name!.trim().isEmpty ||
      profile == null ||
      !profile!.isComplete;

  bool get needsPlanStep {
    final ap = activePlan;
    if (ap != null) return !ap.isComplete;
    final p = plan;
    return p == null || !p.isComplete;
  }

  bool get needsOnboarding => needsProfileStep || needsPlanStep;
}

class UserService {
  static const _meCacheKey = 'trainmate_me_cache_v1';

  static Future<void> clearCachedMe() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_meCacheKey);
  }

  Future<void> _saveCachedMe(MeData me) async {
    final p = await SharedPreferences.getInstance();
    final body = <String, dynamic>{
      'id': me.id,
      'email': me.email,
      'name': me.name,
      'profile': me.profile == null
          ? null
          : {
              'age': me.profile!.age,
              'sex': me.profile!.sex,
              'height_cm': me.profile!.heightCm,
              'weight_kg': me.profile!.weightKg,
              'profile_image_base64': me.profile!.profileImageBase64,
            },
      'plan': me.plan == null
          ? null
          : {
              'category': me.plan!.category,
              'duration_weeks': me.plan!.durationWeeks,
              'before_photo_base64': me.plan!.beforePhotoBase64,
              'after_photo_base64': me.plan!.afterPhotoBase64,
              'onboarding_completed': me.plan!.onboardingCompleted,
            },
      'workout_plans': me.workoutPlans.map((p) => {
            'id': p.id,
            'name': p.name,
            'plan_kind': p.planKind,
            'template_category': p.templateCategory,
            'exercises': p.exercises,
            'duration_weeks': p.durationWeeks,
            'before_photo_base64': p.beforePhotoBase64,
            'after_photo_base64': p.afterPhotoBase64,
            'is_active': p.isActive,
            'created_at': p.createdAt,
            'target_sessions': p.targetSessions,
            'sessions_completed': p.sessionsCompleted,
            'is_completed': p.isCompleted,
            'completed_at': p.completedAt,
            'completion_percent': p.completionPercent,
            'ai_overall_score': p.aiOverallScore,
            'ai_alignment_percent': p.aiAlignmentPercent,
          }).toList(),
      'active_plan': me.activePlan == null
          ? null
          : {
              'id': me.activePlan!.id,
              'name': me.activePlan!.name,
              'plan_kind': me.activePlan!.planKind,
              'template_category': me.activePlan!.templateCategory,
              'exercises': me.activePlan!.exercises,
              'duration_weeks': me.activePlan!.durationWeeks,
              'before_photo_base64': me.activePlan!.beforePhotoBase64,
              'after_photo_base64': me.activePlan!.afterPhotoBase64,
              'is_active': me.activePlan!.isActive,
              'created_at': me.activePlan!.createdAt,
              'target_sessions': me.activePlan!.targetSessions,
              'sessions_completed': me.activePlan!.sessionsCompleted,
              'is_completed': me.activePlan!.isCompleted,
              'completed_at': me.activePlan!.completedAt,
              'completion_percent': me.activePlan!.completionPercent,
              'ai_overall_score': me.activePlan!.aiOverallScore,
              'ai_alignment_percent': me.activePlan!.aiAlignmentPercent,
            },
    };
    await p.setString(_meCacheKey, jsonEncode(body));
  }

  static MeData _parseMeJson(Map<String, dynamic> j, {required String emailFallback}) {
    final profileMap = j['profile'] as Map<String, dynamic>?;
    final planMap = j['plan'] as Map<String, dynamic>?;

    UserPlanData? plan;
    if (planMap != null) {
      plan = UserPlanData(
        category: planMap['category'] as String?,
        durationWeeks: planMap['duration_weeks'] as int?,
        beforePhotoBase64: planMap['before_photo_base64'] as String?,
        afterPhotoBase64: planMap['after_photo_base64'] as String?,
        onboardingCompleted: planMap['onboarding_completed'] as bool? ?? false,
      );
    }

    final wpRaw = j['workout_plans'] as List<dynamic>?;
    final workoutPlans = wpRaw == null
        ? <WorkoutPlanModel>[]
        : wpRaw.whereType<Map<String, dynamic>>().map(WorkoutPlanModel.fromJson).toList();

    WorkoutPlanModel? activePlan;
    final apRaw = j['active_plan'] as Map<String, dynamic>?;
    if (apRaw != null) {
      activePlan = WorkoutPlanModel.fromJson(apRaw);
    } else {
      for (final p in workoutPlans) {
        if (p.isActive) {
          activePlan = p;
          break;
        }
      }
    }

    final userMap = j['user'] as Map<String, dynamic>?;
    final id = (userMap?['id'] as num?)?.toInt() ?? (j['id'] as num?)?.toInt() ?? 0;

    return MeData(
      id: id,
      email: (j['email'] as String?) ?? emailFallback,
      name: j['name'] as String?,
      profile: profileMap == null
          ? null
          : UserProfileData(
              age: profileMap['age'] as int?,
              sex: profileMap['sex'] as String?,
              heightCm: (profileMap['height_cm'] as num?)?.toDouble(),
              weightKg: (profileMap['weight_kg'] as num?)?.toDouble(),
              profileImageBase64: profileMap['profile_image_base64'] as String?,
            ),
      plan: plan,
      workoutPlans: workoutPlans,
      activePlan: activePlan,
    );
  }

  Future<MeData?> getCachedMe() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_meCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _parseMeJson(j, emailFallback: '');
    } catch (_) {
      return null;
    }
  }

  Future<MeData> getMe() async {
    final r = await ApiService.get('/api/users/me');
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final u = j['user'] as Map<String, dynamic>;
    final merged = Map<String, dynamic>.from(j);
    merged['id'] = u['id'];
    merged['email'] = u['email'];
    merged['name'] = u['name'];
    final me = _parseMeJson(merged, emailFallback: u['email'] as String);
    await _saveCachedMe(me);
    return me;
  }

  Future<UserProfileData> updateProfile({
    int? age,
    String? sex,
    double? heightCm,
    double? weightKg,
    String? profileImageBase64,
  }) async {
    final body = <String, dynamic>{};
    if (age != null) body['age'] = age;
    if (sex != null) body['sex'] = sex;
    if (heightCm != null) body['height_cm'] = heightCm;
    if (weightKg != null) body['weight_kg'] = weightKg;
    if (profileImageBase64 != null) body['profile_image_base64'] = profileImageBase64;

    final r = await ApiService.patch('/api/users/me/profile', body: body);
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final p = jsonDecode(r.body) as Map<String, dynamic>;
    return UserProfileData(
      age: p['age'] as int?,
      sex: p['sex'] as String?,
      heightCm: (p['height_cm'] as num?)?.toDouble(),
      weightKg: (p['weight_kg'] as num?)?.toDouble(),
      profileImageBase64: p['profile_image_base64'] as String?,
    );
  }

  Future<UserPlanData> updatePlan({
    String? category,
    int? durationWeeks,
    String? beforePhotoBase64,
    String? afterPhotoBase64,
    bool? onboardingCompleted,
  }) async {
    final body = <String, dynamic>{};
    if (category != null) body['category'] = category;
    if (durationWeeks != null) body['duration_weeks'] = durationWeeks;
    if (beforePhotoBase64 != null) {
      body['before_photo_base64'] = beforePhotoBase64;
    }
    if (afterPhotoBase64 != null) body['after_photo_base64'] = afterPhotoBase64;
    if (onboardingCompleted != null) {
      body['onboarding_completed'] = onboardingCompleted;
    }

    final r = await ApiService.patch('/api/users/me/plan', body: body);
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final p = jsonDecode(r.body) as Map<String, dynamic>;
    return UserPlanData(
      category: p['category'] as String?,
      durationWeeks: p['duration_weeks'] as int?,
      beforePhotoBase64: p['before_photo_base64'] as String?,
      afterPhotoBase64: p['after_photo_base64'] as String?,
      onboardingCompleted: p['onboarding_completed'] as bool? ?? false,
    );
  }

  Future<MeData> updateAccount({
    String? name,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['current_password'] = currentPassword;
    }
    if (newPassword != null && newPassword.isNotEmpty) {
      body['new_password'] = newPassword;
    }
    final r = await ApiService.patch('/api/users/me/account', body: body);
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    return getMe();
  }
}
