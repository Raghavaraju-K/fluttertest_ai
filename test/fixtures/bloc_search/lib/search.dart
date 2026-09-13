import 'package:flutter/material.dart';

/// A minimal search screen with a utility class and a form.
class SearchFormatter {
  String normalize(String query) => query.trim().toLowerCase();
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          TextFormField(key: const ValueKey('search-field')),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}
