class UserModel {
  final int id;
  final String email;
  final String? name;
  final bool emailVerified;
  final String? phone;
  final String? pendingEmail;

  UserModel({
    required this.id,
    required this.email,
    this.name,
    this.emailVerified = false,
    this.phone,
    this.pendingEmail,
  });
}
