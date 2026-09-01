import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/llm_service.dart';

void main() {
  runApp(const FramePrintApp());
}

class FramePrintApp extends StatefulWidget {
  const FramePrintApp({super.key});

  @override
  State<FramePrintApp> createState() => _FramePrintAppState();
}

class _FramePrintAppState extends State<FramePrintApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Stop the resident llama-server (if this app instance started one) when
  // the app is closed, so it doesn't linger holding GPU memory.
  // AppLifecycleState.detached fires on normal window close on desktop.
  // Deliberately not triggered by `paused` (backgrounding) since the whole
  // point of keeping the server resident is to survive being minimized.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      LlmService.instance.stopServer();
    }
  }

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
