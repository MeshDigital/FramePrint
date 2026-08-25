import 'llm_service.dart';

class CardSummary {
  final String title;
  final List<String> steps;
  final List<String> insights;
  final List<String> warnings;

  CardSummary({
    required this.title,
    required this.steps,
    required this.insights,
    required this.warnings,
  });
}

const _chunkSystemPrompt = '''
You are a summarization assistant.

Task: From the transcript chunk below, extract:
1. Key steps (imperative, ordered).
2. Key insights (short bullet points).
3. Warnings (risks, caveats, important notes).

Output in this exact format:

# Steps
- ...

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

Output in this exact format:

# Title
<one line>

# Steps
- ...

# Insights
- ...

# Warnings
- ...
''';

/// Implements the chunk -> per-chunk summarize -> merge pipeline: splits a
/// long transcript into word-count-bounded chunks (so each stays well
/// within the model's context window alongside the system prompt and
/// generation budget), summarizes each chunk, then merges the partial
/// summaries into one final card.
class SummarizerService {
  final LlmService _llm;

  SummarizerService({LlmService? llm}) : _llm = llm ?? LlmService.instance;

  List<String> _chunkTranscript(String transcript, {int wordsPerChunk = 900}) {
    final words = transcript.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || (words.length == 1 && words.first.isEmpty)) {
      return [];
    }
    final chunks = <String>[];
    for (var i = 0; i < words.length; i += wordsPerChunk) {
      final end = (i + wordsPerChunk < words.length) ? i + wordsPerChunk : words.length;
      chunks.add(words.sublist(i, end).join(' '));
    }
    return chunks;
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

  Future<String> _summarizeChunk(String chunk) {
    return _llm.chat(
      systemPrompt: _chunkSystemPrompt,
      userPrompt: 'Transcript chunk:\n"""\n$chunk\n"""',
      maxTokens: 500,
    );
  }

  Future<CardSummary> _merge(String fallbackTitle, List<String> partialSummaries) async {
    final merged = await _llm.chat(
      systemPrompt: _mergeSystemPrompt,
      userPrompt: 'Partial summaries:\n"""\n${partialSummaries.join('\n\n')}\n"""',
      maxTokens: 700,
    );
    final sections = _parseSections(merged);
    final titleLines = sections['title'];
    return CardSummary(
      title: (titleLines != null && titleLines.isNotEmpty) ? titleLines.first : fallbackTitle,
      steps: sections['steps'] ?? [],
      insights: sections['insights'] ?? [],
      warnings: sections['warnings'] ?? [],
    );
  }

  /// Summarizes [transcript] into a [CardSummary]. [fallbackTitle] (e.g.
  /// the source video's title) is used if the model doesn't produce one.
  Future<CardSummary> summarize(String transcript, {String fallbackTitle = 'Untitled'}) async {
    final chunks = _chunkTranscript(transcript);
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
