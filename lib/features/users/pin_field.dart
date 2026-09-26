import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Four to six digits, hidden as they are typed.
class PinField extends StatelessWidget {
  const PinField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onFieldSubmitted: onSubmitted,
      style: TextStyle(fontSize: 22, letterSpacing: 8, color: t.ink),
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}

/// A role as the shop reads it.
String roleName(AppStrings s, Role role) => switch (role) {
  Role.owner => s.roleOwner,
  Role.manager => s.roleManager,
  Role.accountant => s.roleAccountant,
  Role.cashier => s.roleCashier,
};
