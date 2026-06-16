import 'dart:convert';

import 'package:flutter/services.dart';

class ExerciseCatalogService {
  ExerciseCatalogService._();
  static final ExerciseCatalogService instance = ExerciseCatalogService._();

  List<String>? _cachedExercises;

  Future<List<String>> getExercises() async {
    if (_cachedExercises != null) return _cachedExercises!;
    final raw = await rootBundle.loadString('assets/models/classes.json');
    final parsed = (jsonDecode(raw) as List<dynamic>)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _cachedExercises = parsed;
    return parsed;
  }

  String toDisplayName(String exercise) {
    if (exercise.isEmpty) return exercise;
    return exercise
        .split(RegExp(r'[\s_-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
}
