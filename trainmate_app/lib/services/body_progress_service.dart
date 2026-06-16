import 'dart:convert';

import '../core/plan_templates.dart';
import 'api_service.dart';
import 'app_preferences_service.dart';
import '../models/body_progress_result.dart';

class BodyProgressService {
  Future<BodyProgressResult> analyze({
    String? beforePhotoBase64,
    String? afterPhotoBase64,
    String? category,
    bool useVisionEnhancement = true,
  }) async {
    final lang = AppPreferencesService.instance.locale.languageCode;
    final cat = category?.trim() ?? '';
    final template = cat.isNotEmpty
        ? PlanTemplates.prescriptionCategory(null, cat)
        : null;
    final r = await ApiService.post(
      '/api/ml/body-comparison?lang=$lang',
      body: {
        if (beforePhotoBase64 != null && beforePhotoBase64.isNotEmpty)
          'beforePhotoBase64': beforePhotoBase64,
        if (afterPhotoBase64 != null && afterPhotoBase64.isNotEmpty)
          'afterPhotoBase64': afterPhotoBase64,
        if (cat.isNotEmpty) 'category': cat,
        if (template != null && template.isNotEmpty) 'template_category': template,
        'languageCode': lang,
        'useVisionEnhancement': useVisionEnhancement,
      },
      auth: true,
      requestTimeout: const Duration(seconds: 60),
    );

    if (r.statusCode == 200) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      return BodyProgressResult.fromJson(m);
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }
}
