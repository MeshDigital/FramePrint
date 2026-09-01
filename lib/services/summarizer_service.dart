import '../models/video_card.dart';
import 'llm_service.dart';
import 'whisper_service.dart';

class CardSummary {
  final String title;
  final List<SummaryStep> steps;
  final List<String> insights;
  final List<String> warnings;

  CardSummary({
    required this.title,
    required this.steps,
    required this.insights,
    required this.warnings,
  });
}

const _timestampInstructions = '''
Each line of the transcript is prefixed with a timestamp like [01:23]
showing when it was said. When you list a step, prefix it with the
timestamp of the moment that step begins, in the same [MM:SS] format,
taken from the transcript line it's based on. Insights and warnings
don't need timestamps.
''';

const _chunkSystemPrompt = '''
You are a summarization assistant.

Task: From the transcript chunk below, extract:
1. Key steps (imperative, ordered).
2. Key insights (short bullet points).
3. Warnings (risks, caveats, important notes).

$_timestampInstructions

Output in this exact format:

# Steps
- [MM:SS] ...

# Insights
- ...

# Warnings
- ...

Only include a section's bullets if the transcript actually supports them;
otherwise leave the section empty.
''';

const _mergeSystemPrompt = '''
You are creating a final instruction card from one or more partial summaries.

Task: From the summaries below, produce:
1. A clear, concise title.
2. A unified list of key steps (max 10).
3. A list of key insights (max 7).
4. A list of warnings (max 7).

The step bullets you're given are prefixed with a [MM:SS] timestamp.
Keep that same timestamp prefix on each step you output, reusing the
timestamp from the partial summary it came from.

If the partial summaries have no real content for a section, leave that
section's header with no bullets underneath it. Never invent placeholder
bullets like "no steps provided" or ask for more information - just omit
the bullets.

Output in this exact format:

# Title
<one line>

# Steps
- [MM:SS] ...

# Insights
- ...

# Warnings
- ...
''';

final _stepTimestampPattern = RegExp(r'^\[(\d+):(\d{2})\]\s*(.+)$');

/// Signature of [LlmService.chat], factored out so tests can inject a fake
/// without hitting a real llama-server.
typedef ChatFn = Future<String> Function({
  required String systemPrompt,
  required String userPrompt,
  int maxTokens,
  double temperature,
});

/// Implements the chunk -> per-chunk summarize -> merge pipeline: splits a
/// long transcript into word-count-bounded chunks of whole segments (so
/// each stays well within the model's context window, and timestamps stay
/// meaningful), summarizes each chunk, then merges the partial summaries
/// into one final card. Steps carry a timestamp back to the moment in the
/// source video they were drawn from.
class SummarizerService {
  final ChatFn _chat;

  SummarizerService({LlmService? llm, ChatFn? chat})
      : _chat = chat ?? (llm ?? LlmService.instance).chat;

  List<String> _chunkSegments(List<TranscriptSegment> segments, {int wordsPerChunk = 900}) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var wordCount = 0;

    void flush() {
      if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
      buffer.clear();
      wordCount = 0;
    }

    for (final segment in segments) {
      if (segment.text.trim().isEmpty) continue;
      buffer.writeln('[${_formatTimestamp(segment.startSeconds)}] ${segment.text.trim()}');
      wordCount += segment.text.trim().split(RegExp(r'\s+')).length;
      if (wordCount >= wordsPerChunk) flush();
    }
    flush();
    return chunks;
  }

  String _formatTimestamp(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double? _parseTimestampTag(String mmss) {
    final match = RegExp(r'^(\d+):(\d{2})$').firstMatch(mmss);
    if (match == null) return null;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    return (minutes * 60 + seconds).toDouble();
  }

  /// Parses a "# Section\n- bullet\n- bullet" formatted response into a
  /// map of lower-cased section name -> bullet lines (title sections keep
  /// their single line of free text instead).
  Map<String, List<String>> _parseSections(String text) {
    final sections = <String, List<String>>{};
    String? current;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      final headerMatch = RegExp(r'^#+\s*(.+)$').firstMatch(line);
      if (headerMatch != null) {
        current = headerMatch.group(1)!.trim().toLowerCase();
        sections[current] = [];
        continue;
      }
      if (current == null || line.isEmpty) continue;
      final bulletMatch = RegExp(r'^[-*]\s*(.+)$').firstMatch(line);
      sections[current]!.add(bulletMatch != null ? bulletMatch.group(1)!.trim() : line);
    }
    // Drop empty bullet placeholders like a lone "-" or "...".
    for (final key in sections.keys) {
      sections[key] = sections[key]!
          .where((l) => l.isNotEmpty && l != '...' && l != '-')
          .toList();
    }
    return sections;
  }

  List<SummaryStep> _parseSteps(List<String> rawSteps) {
    return rawSteps.map((raw) {
      final match = _stepTimestampPattern.firstMatch(raw);
      if (match == null) return SummaryStep(text: raw);
      return SummaryStep(
        text: match.group(3)!.trim(),
        timestampSeconds: _parseTimestampTag('${match.group(1)}:${match.group(2)}'),
      );
    }).toList();
  }

  Future<String> _summarizeChunk(String chunk) {
    return _chat(
      systemPrompt: _chunkSystemPrompt,
      userPrompt: 'Transcript chunk:\n"""\n$chunk\n"""',
      maxTokens: 600,
    );
  }

  Future<CardSummary> _merge(String fallbackTitle, List<String> partialSummaries) async {
    final merged = await _chat(
      systemPrompt: _mergeSystemPrompt,
      userPrompt: 'Partial summaries:\n"""\n${partialSummaries.join('\n\n')}\n"""',
      maxTokens: 800,
    );
    final sections = _parseSections(merged);
    final titleLines = sections['title'];
    return CardSummary(
      title: (titleLines != null && titleLines.isNotEmpty) ? titleLines.first : fallbackTitle,
      steps: _parseSteps(sections['steps'] ?? []),
      insights: sections['insights'] ?? [],
      warnings: sections['warnings'] ?? [],
    );
  }

  /// Summarizes [segments] (a timestamped transcript, see [WhisperService])
  /// into a [CardSummary]. [fallbackTitle] (e.g. the source video's title)
  /// is used if the model doesn't produce one.
  Future<CardSummary> summarize(
    List<TranscriptSegment> segments, {
    String fallbackTitle = 'Untitled',
  }) async {
    final chunks = _chunkSegments(segments);
    if (chunks.isEmpty) {
      return CardSummary(title: fallbackTitle, steps: [], insights: [], warnings: []);
    }

    if (chunks.length == 1) {
      return _merge(fallbackTitle, [await _summarizeChunk(chunks.first)]);
    }

    final partials = <String>[];
    for (final chunk in chunks) {
      partials.add(await _summarizeChunk(chunk));
    }
    return _merge(fallbackTitle, partials);
  }
}
