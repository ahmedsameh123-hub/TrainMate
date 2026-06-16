import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

import '../../services/app_preferences_service.dart';
import '../../l10n/app_text.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _user = UserService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _picker = ImagePicker();
  String? _profileImageBase64;
  String? _sex;
  DateTime? _birthDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primeCachedMe();
    _load();
  }

  void _applyMe(MeData me) {
    _name.text = me.name ?? '';
    _email.text = me.email;
    _profileImageBase64 = me.profile?.profileImageBase64;
    if (me.profile?.age != null) _age.text = '${me.profile!.age}';
    if (me.profile?.heightCm != null) _height.text = '${me.profile!.heightCm}';
    if (me.profile?.weightKg != null) _weight.text = '${me.profile!.weightKg}';
    _sex = me.profile?.sex;
    _birthDate = AppPreferencesService.instance.birthDate;
    if (_birthDate != null) {
      _age.text = '${_calculateAge(_birthDate!)}';
    }
  }

  Future<void> _primeCachedMe() async {
    final cached = await _user.getCachedMe();
    if (!mounted || cached == null) return;
    setState(() {
      _applyMe(cached);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await _user.getMe().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _applyMe(me);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _user.updateAccount(
        name: _name.text.trim(),
        email: _email.text.trim(),
        currentPassword: _current.text.trim(),
        newPassword: _next.text.trim(),
      );
      final age = int.tryParse(_age.text.trim());
      final h = double.tryParse(_height.text.trim());
      final w = double.tryParse(_weight.text.trim());
      final effectiveAge = _birthDate == null ? age : _calculateAge(_birthDate!);
      await _user.updateProfile(
        profileImageBase64: _profileImageBase64,
        age: effectiveAge,
        sex: _sex,
        heightCm: h,
        weightKg: w,
      );
      await AppPreferencesService.instance.setBirthDate(_birthDate);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppText.of(context).tr('settings.accountUpdated'))));
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickProfileImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _profileImageBase64 = base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.tr('settings.account'))),
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.tr('settings.account'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundImage: _profileImageBase64 == null || _profileImageBase64!.isEmpty
                      ? null
                      : MemoryImage(base64Decode(_profileImageBase64!)),
                  child: (_profileImageBase64 == null || _profileImageBase64!.isEmpty)
                      ? Text((_name.text.isNotEmpty ? _name.text[0] : 'U').toUpperCase())
                      : null,
                ),
                TextButton.icon(
                  onPressed: _pickProfileImage,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(t.tr('settings.changeProfilePhoto')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: t.tr('common.name')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            decoration: InputDecoration(labelText: t.tr('common.email')),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t.tr('common.age')),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: InputDecoration(labelText: t.tr('common.sex')),
            items: [
              DropdownMenuItem(value: 'Male', child: Text(t.tr('sex.male'))),
              DropdownMenuItem(value: 'Female', child: Text(t.tr('sex.female'))),
            ],
            onChanged: (v) => setState(() => _sex = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.tr('common.heightCm')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.tr('common.weightKg')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: t.tr('settings.currentPassword')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: InputDecoration(labelText: t.tr('settings.newPassword')),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? t.tr('common.saving') : t.tr('settings.saveAccount')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
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
