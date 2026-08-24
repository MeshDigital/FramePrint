import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const FramePrintApp());
}

class FramePrintApp extends StatelessWidget {
  const FramePrintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FramePrint',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
