import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class WhisperException implements Exception {
  final String message;
  WhisperException(this.message);

  @override
  String toString() => 'WhisperException: $message';
}

/// One spoken segment of a transcript, with its position in the source
/// audio. Lets later pipeline steps (summarization, frame extraction) know
/// *when* something was said, not just *what* was said.
class TranscriptSegment {
  final double startSeconds;
  final double endSeconds;
  final String text;

  TranscriptSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });

  Map<String, Object?> toMap() => {
        'start': startSeconds,
        'end': endSeconds,
        'text': text,
      };

  factory TranscriptSegment.fromMap(Map<String, dynamic> map) => TranscriptSegment(
        startSeconds: (map['start'] as num).toDouble(),
        endSeconds: (map['end'] as num).toDouble(),
        text: map['text'] as String,
      );
}

class TranscriptResult {
  final String fullText;
  final List<TranscriptSegment> segments;

  TranscriptResult({required this.fullText, required this.segments});
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
  /// and returns both the plain-text transcript and per-segment timestamps.
  Future<TranscriptResult> transcribe(String wavPath) async {
    if (!File(modelPath).existsSync()) {
      throw WhisperException('Whisper model not found at $modelPath');
    }

    final outputBase = p.setExtension(wavPath, '');
    final expectedJsonPath = '$outputBase.json';

    final result = await Process.run('whisper-cli', [
      '-m', modelPath,
      '-f', wavPath,
      '-oj',
      '-of', outputBase,
    ]);

    if (result.exitCode != 0) {
      throw WhisperException(result.stderr.toString().trim());
    }

    final jsonFile = File(expectedJsonPath);
    if (!await jsonFile.exists()) {
      throw WhisperException(
        'whisper-cli did not produce expected output at $expectedJsonPath',
      );
    }

    final json = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    final rawSegments = json['transcription'] as List;

    final segments = rawSegments.map((raw) {
      final offsets = raw['offsets'] as Map<String, dynamic>;
      return TranscriptSegment(
        startSeconds: (offsets['from'] as num) / 1000.0,
        endSeconds: (offsets['to'] as num) / 1000.0,
        text: (raw['text'] as String).trim(),
      );
    }).toList();

    return TranscriptResult(
      fullText: segments.map((s) => s.text).join(' ').trim(),
      segments: segments,
    );
  }
}
