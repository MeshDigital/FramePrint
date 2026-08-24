import 'dart:convert';

enum CardStatus { pending, downloading, downloaded, processing, ready, error }

/// A single video -> paper "knowledge card", following the schema from
/// the FramePrint pipeline plan (see README).
class VideoCard {
  final String id;
  final String youtubeUrl;
  final DateTime createdAt;

  String? localVideoPath;
  String? localAudioPath;
  String? gifPath;
  String? framesDir;
  int? durationSeconds;

  int? segmentStartSeconds;
  int? segmentEndSeconds;
  List<String> selectedFrames;

  String? transcriptText;

  String? summaryTitle;
  List<String> summarySteps;
  List<String> summaryInsights;
  List<String> summaryWarnings;

  String? pdfPath;
  String? qrPayload;

  CardStatus status;
  String? errorMessage;

  VideoCard({
    required this.id,
    required this.youtubeUrl,
    required this.createdAt,
    this.localVideoPath,
    this.localAudioPath,
    this.gifPath,
    this.framesDir,
    this.durationSeconds,
    this.segmentStartSeconds,
    this.segmentEndSeconds,
    List<String>? selectedFrames,
    this.transcriptText,
    this.summaryTitle,
    List<String>? summarySteps,
    List<String>? summaryInsights,
    List<String>? summaryWarnings,
    this.pdfPath,
    this.qrPayload,
    this.status = CardStatus.pending,
    this.errorMessage,
  })  : selectedFrames = selectedFrames ?? [],
        summarySteps = summarySteps ?? [],
        summaryInsights = summaryInsights ?? [],
        summaryWarnings = summaryWarnings ?? [];

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'youtube_url': youtubeUrl,
      'created_at': createdAt.toIso8601String(),
      'local_video_path': localVideoPath,
      'local_audio_path': localAudioPath,
      'gif_path': gifPath,
      'frames_dir': framesDir,
      'duration_seconds': durationSeconds,
      'segment_start': segmentStartSeconds,
      'segment_end': segmentEndSeconds,
      'selected_frames': jsonEncode(selectedFrames),
      'transcript_text': transcriptText,
      'summary_title': summaryTitle,
      'summary_steps': jsonEncode(summarySteps),
      'summary_insights': jsonEncode(summaryInsights),
      'summary_warnings': jsonEncode(summaryWarnings),
      'pdf_path': pdfPath,
      'qr_payload': qrPayload,
      'status': status.name,
      'error_message': errorMessage,
    };
  }

  static List<String> _decodeList(Object? raw) {
    if (raw == null) return [];
    final decoded = jsonDecode(raw as String) as List;
    return decoded.map((e) => e.toString()).toList();
  }

  factory VideoCard.fromMap(Map<String, Object?> map) {
    return VideoCard(
      id: map['id'] as String,
      youtubeUrl: map['youtube_url'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      localVideoPath: map['local_video_path'] as String?,
      localAudioPath: map['local_audio_path'] as String?,
      gifPath: map['gif_path'] as String?,
      framesDir: map['frames_dir'] as String?,
      durationSeconds: map['duration_seconds'] as int?,
      segmentStartSeconds: map['segment_start'] as int?,
      segmentEndSeconds: map['segment_end'] as int?,
      selectedFrames: _decodeList(map['selected_frames']),
      transcriptText: map['transcript_text'] as String?,
      summaryTitle: map['summary_title'] as String?,
      summarySteps: _decodeList(map['summary_steps']),
      summaryInsights: _decodeList(map['summary_insights']),
      summaryWarnings: _decodeList(map['summary_warnings']),
      pdfPath: map['pdf_path'] as String?,
      qrPayload: map['qr_payload'] as String?,
      status: CardStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => CardStatus.pending,
      ),
      errorMessage: map['error_message'] as String?,
    );
  }
}
