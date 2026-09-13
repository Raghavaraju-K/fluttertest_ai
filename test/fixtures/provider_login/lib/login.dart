import 'package:flutter/material.dart';

/// A minimal email validator exposed as a public API.
class EmailValidator {
  bool isValid(String? email) {
    if (email == null || email.isEmpty) return false;
    return email.contains('@');
  }
}

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        child: Column(
          children: [
            TextFormField(key: const ValueKey('email-field')),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}
