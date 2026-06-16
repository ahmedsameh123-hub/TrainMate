class EmailNotVerifiedException implements Exception {
  EmailNotVerifiedException(this.email);
  final String email;

  @override
  String toString() => 'EmailNotVerifiedException($email)';
}
