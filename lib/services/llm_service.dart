import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LlmException implements Exception {
  final String message;
  LlmException(this.message);

  @override
  String toString() => 'LlmException: $message';
}

/// Manages a local `llama-server` (llama.cpp) process and talks to its
/// OpenAI-compatible /v1/chat/completions endpoint for local, offline
/// summarization. The server is started lazily and left running for the
/// rest of the app session so the model stays resident in VRAM between
/// calls (reloading a multi-GB GGUF per-request would be far too slow).
///
/// Known limitation: if the Flutter app is killed abruptly (not a normal
/// exit), the llama-server child process can be left running in the
/// background holding GPU memory. There's no cleanup UI for this yet.
class LlmService {
  static const String defaultModelPath =
      r'C:\tools\llama-cpp\models\Qwen2.5-7B-Instruct-Q4_K_M.gguf';
  static const String host = '127.0.0.1';
  static const int port = 8811;

  /// Shared instance so the llama-server process (and the multi-GB model
  /// it loads into VRAM) is reused across screens/cards for the rest of
  /// the app session instead of being started fresh each time.
  static final LlmService instance = LlmService._();

  final String modelPath = defaultModelPath;
  Process? _serverProcess;

  LlmService._();

  Uri get _baseUri => Uri.parse('http://$host:$port');

  Future<bool> _isServerUp() async {
    try {
      final response = await http
          .get(_baseUri.replace(path: '/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Starts `llama-server` if one isn't already listening on [port], and
  /// waits until it reports healthy. Safe to call before every request.
  Future<void> ensureServerRunning() async {
    if (await _isServerUp()) return;

    if (!File(modelPath).existsSync()) {
      throw LlmException('LLM model not found at $modelPath');
    }

    _serverProcess = await Process.start('llama-server', [
      '-m', modelPath,
      '-ngl', '99',
      '-c', '4096',
      '--host', host,
      '--port', '$port',
      '--no-webui',
    ]);

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isServerUp()) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw LlmException('llama-server did not become ready in time');
  }

  /// Stops the llama-server process this [LlmService] instance started, if
  /// any. Does nothing if the server was already running before
  /// [ensureServerRunning] was called (we don't own its lifecycle then).
  void stopServer() {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  Future<String> chat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 512,
    double temperature = 0.3,
  }) async {
    await ensureServerRunning();

    final response = await http.post(
      _baseUri.replace(path: '/v1/chat/completions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': temperature,
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode != 200) {
      throw LlmException('llama-server returned ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List;
    final message = choices.first['message'] as Map<String, dynamic>;
    return (message['content'] as String).trim();
  }
}
