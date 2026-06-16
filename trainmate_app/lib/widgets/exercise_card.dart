import 'package:flutter/material.dart';

class ExerciseCard extends StatelessWidget {
  final String title;
  final String muscle;

  const ExerciseCard({super.key, required this.title, required this.muscle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: ListTile(
        title: Text(title),
        subtitle: Text(muscle),
        trailing: const Icon(Icons.fitness_center),
      ),
    );
  }
}
