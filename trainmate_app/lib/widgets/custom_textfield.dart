import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.obscure = false,
    this.keyboardType,
    this.prefixIcon,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        prefixIcon: prefixIcon != null
            ? Icon(
                prefixIcon,
                size: 22,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.85),
              )
            : null,
      ),
    );
  }
}
