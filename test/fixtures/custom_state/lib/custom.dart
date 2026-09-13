import 'package:flutter/material.dart';

/// A custom state container that no known package owns.
class AppStore {
  String value = '';
}

/// A screen reading the custom store through plain constructor injection.
class CustomScreen extends StatelessWidget {
  const CustomScreen({super.key, this.store});

  final AppStore? store;

  @override
  Widget build(BuildContext context) {
    final value = store?.value ?? '';
    return Scaffold(
      body: Column(
        children: [
          Text(value.isEmpty ? 'Custom' : value),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
