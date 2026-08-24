import 'dart:io';

import 'package:path/path.dart' as p;

class WhisperException implements Exception {
  final String message;
  WhisperException(this.message);

  @override
  String toString() => 'WhisperException: $message';
}

/// Thin wrapper around whisper.cpp's `whisper-cli` for local, offline
/// speech-to-text. Assumes `whisper-cli` is on PATH (see README for setup)
/// and a ggml model has been downloaded locally.
class WhisperService {
  /// Path to the ggml model file. See README "Prerequisites" for where to
  /// download this from.
  static const String defaultModelPath = r'C:\tools\whisper-cpp\models\ggml-base.bin';

  final String modelPath;

  WhisperService({this.modelPath = defaultModelPath});

  /// Transcribes a 16kHz mono WAV file (see [FfmpegService.extractAudio])
  /// and returns the plain-text transcript.
  Future<String> transcribe(String wavPath) async {
    if (!File(modelPath).existsSync()) {
      throw WhisperException('Whisper model not found at $modelPath');
    }

    final outputBase = p.setExtension(wavPath, '');
    final expectedTxtPath = '$outputBase.txt';

    final result = await Process.run('whisper-cli', [
      '-m', modelPath,
      '-f', wavPath,
      '-otxt',
      '-of', outputBase,
      '-nt', // no per-segment timestamps in the txt output
    ]);

    if (result.exitCode != 0) {
      throw WhisperException(result.stderr.toString().trim());
    }

    final txtFile = File(expectedTxtPath);
    if (!await txtFile.exists()) {
      throw WhisperException(
        'whisper-cli did not produce expected output at $expectedTxtPath',
      );
    }
    return (await txtFile.readAsString()).trim();
  }
}
