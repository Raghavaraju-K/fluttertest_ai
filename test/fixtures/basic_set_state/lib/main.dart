import 'package:flutter/material.dart';

/// A pure counter helper class that can be unit-tested without Flutter.
class CounterHelper {
  int value = 0;
  void increment() => value++;
  void reset() => value = 0;
  bool get isPositive => value > 0;
}

/// A minimal setState counter screen with public UI signals.
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  int _count = 0;

  void _increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Center(
        child: Column(
          children: [
            const Text('Count'),
            Text('$_count'),
            ElevatedButton(
              key: const ValueKey('increment-button'),
              onPressed: _increment,
              child: const Text('Increment'),
            ),
          ],
        ),
      ),
    );
  }
}
