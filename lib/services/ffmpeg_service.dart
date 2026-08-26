import 'dart:io';

class FfmpegException implements Exception {
  final String message;
  FfmpegException(this.message);

  @override
  String toString() => 'FfmpegException: $message';
}

/// Thin wrapper around the ffmpeg CLI for the clip -> gif/frames/audio
/// steps of the FramePrint pipeline. Assumes `ffmpeg` is available on PATH.
class FfmpegService {
  Future<void> _run(List<String> args) async {
    final result = await Process.run('ffmpeg', ['-y', ...args]);
    if (result.exitCode != 0) {
      throw FfmpegException(result.stderr.toString().trim());
    }
  }

  /// Extracts the audio track as 16kHz mono PCM WAV, the format whisper.cpp
  /// expects.
  Future<void> extractAudio({
    required String videoPath,
    required String outputAudioPath,
  }) => _run([
        '-i', videoPath,
        '-vn',
        '-ar', '16000',
        '-ac', '1',
        '-c:a', 'pcm_s16le',
        outputAudioPath,
      ]);

  /// Cuts [start, end] (in seconds) from [videoPath] into a small looping
  /// preview GIF.
  Future<void> makeGif({
    required String videoPath,
    required int startSeconds,
    required int endSeconds,
    required String outputGifPath,
    int fps = 12,
    int width = 640,
  }) => _run([
        '-ss', '$startSeconds',
        '-to', '$endSeconds',
        '-i', videoPath,
        '-vf', 'fps=$fps,scale=$width:-1:flags=lanczos',
        outputGifPath,
      ]);

  /// Extracts a single frame at [atSeconds] into [outputPath]. Used to grab
  /// a representative image for a specific moment (e.g. a summarized
  /// step's timestamp) rather than a generic range of frames.
  Future<void> extractFrameAt({
    required String videoPath,
    required double atSeconds,
    required String outputPath,
    int width = 480,
  }) => _run([
        '-ss', atSeconds.toStringAsFixed(2),
        '-i', videoPath,
        '-frames:v', '1',
        '-vf', 'scale=$width:-1',
        outputPath,
      ]);

  /// Extracts one frame per second from [start, end] into [outputDir] as
  /// frame_001.png, frame_002.png, ...
  Future<void> extractFrames({
    required String videoPath,
    required int startSeconds,
    required int endSeconds,
    required String outputDir,
    int fps = 1,
    int width = 640,
  }) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _run([
      '-ss', '$startSeconds',
      '-to', '$endSeconds',
      '-i', videoPath,
      '-vf', 'fps=$fps,scale=$width:-1',
      '$outputDir/frame_%03d.png',
    ]);
  }
}
