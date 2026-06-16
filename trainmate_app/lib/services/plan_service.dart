import 'dart:convert';

import 'api_service.dart';
import 'app_preferences_service.dart';
import '../models/plan_completion_data.dart';
import '../models/workout_plan_model.dart';

class PlanService {
  int computeTargetSessions(int durationWeeks) {
    final days = AppPreferencesService.instance.trainingDaysPerWeek.clamp(2, 6);
    return durationWeeks * days;
  }

  Future<List<WorkoutPlanModel>> listPlans() async {
    final r = await ApiService.get('/api/users/me/plans', auth: true);
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(WorkoutPlanModel.fromJson)
        .toList();
  }

  Future<List<WorkoutPlanModel>> listCompletedPlans() async {
    final r = await ApiService.get('/api/users/me/plans/completed', auth: true);
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(WorkoutPlanModel.fromJson)
        .toList();
  }

  Future<WorkoutPlanModel> createPlan(
    WorkoutPlanModel plan, {
    bool activate = true,
    bool? onboardingCompleted,
  }) async {
    final target = computeTargetSessions(plan.durationWeeks);
    final r = await ApiService.post(
      '/api/users/me/plans',
      body: plan.toCreateJson(
        activate: activate,
        onboardingCompleted: onboardingCompleted,
        targetSessions: target,
      ),
      auth: true,
    );
    if (r.statusCode == 201 || r.statusCode == 200) {
      return WorkoutPlanModel.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<WorkoutPlanModel> updatePlan(
    int id, {
    String? name,
    List<String>? exercises,
    int? durationWeeks,
    String? beforePhotoBase64,
    String? afterPhotoBase64,
    bool? onboardingCompleted,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (exercises != null) body['exercises'] = exercises;
    if (durationWeeks != null) {
      body['duration_weeks'] = durationWeeks;
      body['target_sessions'] = computeTargetSessions(durationWeeks);
    }
    if (beforePhotoBase64 != null) body['before_photo_base64'] = beforePhotoBase64;
    if (afterPhotoBase64 != null) body['after_photo_base64'] = afterPhotoBase64;
    if (onboardingCompleted != null) body['onboarding_completed'] = onboardingCompleted;

    final r = await ApiService.patch('/api/users/me/plans/$id', body: body, auth: true);
    if (r.statusCode == 200) {
      return WorkoutPlanModel.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<WorkoutPlanModel> activatePlan(int id) async {
    final r = await ApiService.post('/api/users/me/plans/$id/activate', body: {}, auth: true);
    if (r.statusCode == 200) {
      return WorkoutPlanModel.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<PlanCompletionData> completePlan(
    int id, {
    required String afterPhotoBase64,
    required String languageCode,
  }) async {
    final r = await ApiService.post(
      '/api/users/me/plans/$id/complete',
      body: {
        'afterPhotoBase64': afterPhotoBase64,
        'languageCode': languageCode,
      },
      auth: true,
      requestTimeout: const Duration(seconds: 90),
    );
    if (r.statusCode == 200) {
      return PlanCompletionData.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<PlanCompletionData> getPlanCompletion(int id) async {
    final r = await ApiService.get('/api/users/me/plans/$id/completion', auth: true);
    if (r.statusCode == 200) {
      return PlanCompletionData.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<Map<String, dynamic>> analyzePlanBody(int id, {required String languageCode}) async {
    final lang = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
    final r = await ApiService.post(
      '/api/users/me/plans/$id/analyze-body?lang=$lang',
      body: {},
      auth: true,
      requestTimeout: const Duration(seconds: 90),
    );
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<void> deletePlan(int id) async {
    final r = await ApiService.delete('/api/users/me/plans/$id', auth: true);
    if (r.statusCode != 204 && r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
  }
}
