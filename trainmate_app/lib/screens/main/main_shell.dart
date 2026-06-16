import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../home/smart_home_screen.dart';
import '../profile/profile_screen.dart';
import '../workout/workout_hub_screen.dart';

/// Main shell: Home, Workout, Profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  /// Tab index when opening the shell (e.g. deep links).
  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index;
  late final List<bool> _visited;

  Widget _screenAt(int index) {
    switch (index) {
      case 0:
        return const SmartHomeScreen();
      case 1:
        return const WorkoutHubScreen();
      case 2:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 2);
    _visited = [false, false, false];
    _visited[_index] = true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          3,
          (i) => _visited[i] ? _screenAt(i) : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 12,
        shadowColor: Colors.black26,
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: NavigationBar(
                  height: 64,
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    if (i == _index) return;
                    setState(() {
                      _index = i;
                      _visited[i] = true;
                    });
                  },
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor: cs.primaryContainer.withValues(alpha: 0.85),
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    NavigationDestination(
                      icon: Icon(
                        Icons.home_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      selectedIcon: Icon(Icons.home_rounded, color: cs.primary),
                      label: t.tr('nav.home'),
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.fitness_center_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      selectedIcon:
                          Icon(Icons.fitness_center_rounded, color: cs.primary),
                      label: t.tr('nav.workout'),
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.person_outline_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      selectedIcon:
                          Icon(Icons.person_rounded, color: cs.primary),
                      label: t.tr('nav.profile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
