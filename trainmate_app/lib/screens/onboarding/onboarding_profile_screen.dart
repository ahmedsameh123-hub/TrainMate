import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/app_preferences_service.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';
import 'onboarding_plan_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  State<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  final _user = UserService();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  DateTime? _birthDate;
  String? _sex;
  bool _loading = false;
  bool _bootLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primeCachedProfile();
    _loadCurrent();
  }

  void _applyProfile(MeData me) {
    if (me.name != null) _name.text = me.name!;
    final p = me.profile;
    if (p?.age != null) _age.text = '${p!.age}';
    if (p?.heightCm != null) _height.text = '${p!.heightCm}';
    if (p?.weightKg != null) _weight.text = '${p!.weightKg}';
    _sex = p?.sex;
    _birthDate = AppPreferencesService.instance.birthDate;
    if (_birthDate != null) {
      _age.text = '${_calculateAge(_birthDate!)}';
    }
  }

  Future<void> _primeCachedProfile() async {
    final cached = await _user.getCachedMe();
    if (!mounted || cached == null) return;
    setState(() {
      _applyProfile(cached);
      _bootLoading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    try {
      final me = await _user.getMe().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _applyProfile(me);
        _bootLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _bootLoading = false);
    }
  }

  Route<void> _toPlanRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const OnboardingPlanScreen(),
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.14, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  Future<void> _saveAndContinue() async {
    final t = AppText.of(context);
    final newName = _name.text.trim();
    if (newName.isEmpty) {
      setState(() => _error = t.tr('onboarding.nameRequired'));
      return;
    }
    if (_sex == null || _sex!.isEmpty) {
      setState(() => _error = t.tr('onboarding.sexRequired'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final age = int.tryParse(_age.text.trim());
      final effectiveAge = _birthDate == null ? age : _calculateAge(_birthDate!);
      final h = double.tryParse(_height.text.trim());
      final w = double.tryParse(_weight.text.trim());

      await _user.updateAccount(name: newName);
      await _user.updateProfile(
        age: effectiveAge,
        sex: _sex,
        heightCm: h,
        weightKg: w,
      );
      await AppPreferencesService.instance.setBirthDate(_birthDate);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(_toPlanRoute());
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    if (_bootLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.tr('onboarding.step1Title'))),
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.tr('onboarding.step1Title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t.tr('onboarding.step1Desc'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: t.tr('common.name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake_outlined),
                    title: Text(t.tr('profile.birthDate')),
                    subtitle: Text(
                      _birthDate == null
                          ? t.tr('profile.birthDateNotSet')
                          : _formatDate(_birthDate!),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _birthDate ?? DateTime(now.year - 20),
                          firstDate: DateTime(1950),
                          lastDate: DateTime(now.year - 10),
                        );
                        if (picked == null || !mounted) return;
                        setState(() {
                          _birthDate = picked;
                          _age.text = '${_calculateAge(picked)}';
                        });
                      },
                      child: Text(t.tr('profile.selectBirthDate')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.tr('common.age')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_sex),
                    initialValue: _sex,
                    decoration: InputDecoration(labelText: t.tr('common.sex')),
                    items: [
                      DropdownMenuItem(
                        value: 'Male',
                        child: Text(t.tr('sex.male')),
                      ),
                      DropdownMenuItem(
                        value: 'Female',
                        child: Text(t.tr('sex.female')),
                      ),
                    ],
                    onChanged: (v) => setState(() => _sex = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t.tr('common.heightCm'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t.tr('common.weightKg'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _saveAndContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              _loading ? t.tr('common.saving') : t.tr('onboarding.continue'),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],
      ),
    );
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final beforeBirthday =
        now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day);
    if (beforeBirthday) age--;
    return age.clamp(10, 100);
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
