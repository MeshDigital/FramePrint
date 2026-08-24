import 'dart:convert';
import 'dart:io';

class YtDlpMetadata {
  final String title;
  final double durationSeconds;

  YtDlpMetadata({required this.title, required this.durationSeconds});
}

class YtDlpException implements Exception {
  final String message;
  YtDlpException(this.message);

  @override
  String toString() => 'YtDlpException: $message';
}

/// Thin wrapper around the yt-dlp CLI. Assumes `yt-dlp` is available on PATH.
class YtDlpService {
  static final RegExp _youtubeUrlPattern = RegExp(
    r'^(https?://)?(www\.)?(youtube\.com|youtu\.be|m\.youtube\.com)/',
    caseSensitive: false,
  );

  bool isValidYoutubeUrl(String url) => _youtubeUrlPattern.hasMatch(url.trim());

  Future<YtDlpMetadata> fetchMetadata(String url) async {
    final result = await Process.run('yt-dlp', [
      '--dump-json',
      '--no-playlist',
      url,
    ]);

    if (result.exitCode != 0) {
      throw YtDlpException(result.stderr.toString().trim());
    }

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return YtDlpMetadata(
      title: json['title'] as String? ?? 'Untitled',
      durationSeconds: (json['duration'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Downloads [url] into [outputPath] (a full file path, extension is
  /// controlled by yt-dlp's chosen format). Streams progress lines from
  /// yt-dlp's stdout via [onOutput].
  Future<String> downloadVideo(
    String url,
    String outputTemplate, {
    void Function(String line)? onOutput,
  }) async {
    final process = await Process.start('yt-dlp', [
      '--no-playlist',
      '-f',
      'bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b',
      '--merge-output-format',
      'mp4',
      '-o',
      outputTemplate,
      '--print',
      'after_move:filepath',
      url,
    ]);

    final stdoutLines = <String>[];
    final stderrBuffer = StringBuffer();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdoutLines.add(line);
      onOutput?.call(line);
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderrBuffer.writeln(line);
      onOutput?.call(line);
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw YtDlpException(stderrBuffer.toString().trim());
    }

    // The last non-empty stdout line printed via --print after_move:filepath
    // is the final downloaded file path.
    final filePath = stdoutLines.lastWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    if (filePath.isEmpty) {
      throw YtDlpException('yt-dlp did not report an output file path');
    }
    return filePath;
  }
}
