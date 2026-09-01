import 'package:flutter_test/flutter_test.dart';
import 'package:frameprint/services/summarizer_service.dart';
import 'package:frameprint/services/whisper_service.dart';

TranscriptSegment _seg(double start, double end, String text) =>
    TranscriptSegment(startSeconds: start, endSeconds: end, text: text);

void main() {
  group('SummarizerService.summarize', () {
    test('returns an empty summary without calling the model for no segments', () async {
      var callCount = 0;
      final service = SummarizerService(
        chat: ({
          required String systemPrompt,
          required String userPrompt,
          int maxTokens = 512,
          double temperature = 0.3,
        }) async {
          callCount++;
          return '';
        },
      );

      final summary = await service.summarize([], fallbackTitle: 'Fallback');

      expect(callCount, 0);
      expect(summary.title, 'Fallback');
      expect(summary.steps, isEmpty);
      expect(summary.insights, isEmpty);
      expect(summary.warnings, isEmpty);
    });

    test('parses title, timestamped steps, insights and warnings from a single chunk', () async {
      final segments = [_seg(0, 3, 'Preheat the oven to 350 degrees.')];
      var callCount = 0;

      final service = SummarizerService(
        chat: ({
          required String systemPrompt,
          required String userPrompt,
          int maxTokens = 512,
          double temperature = 0.3,
        }) async {
          callCount++;
          // First call is the per-chunk summarize, second is the merge.
          if (callCount == 1) {
            return '''
# Steps
- [00:00] Preheat the oven to 350 degrees.

# Insights
- Even heat matters.

# Warnings
- Don't touch the hot rack.
''';
          }
          return '''
# Title
How to bake bread

# Steps
- [00:00] Preheat the oven to 350 degrees.

# Insights
- Even heat matters.

# Warnings
- Don't touch the hot rack.
''';
        },
      );

      final summary = await service.summarize(segments, fallbackTitle: 'Fallback');

      expect(callCount, 2);
      expect(summary.title, 'How to bake bread');
      expect(summary.steps, hasLength(1));
      expect(summary.steps.single.text, 'Preheat the oven to 350 degrees.');
      expect(summary.steps.single.timestampSeconds, 0.0);
      expect(summary.insights, ['Even heat matters.']);
      expect(summary.warnings, ["Don't touch the hot rack."]);
    });

    test('splits a long transcript into multiple word-bounded chunks before merging', () async {
      // 950 words per segment forces a new chunk (wordsPerChunk defaults to 900),
      // so three such segments should produce three chunk-summarize calls
      // plus one merge call.
      final longText = List.generate(950, (i) => 'word').join(' ');
      final segments = [
        _seg(0, 10, longText),
        _seg(10, 20, longText),
        _seg(20, 30, longText),
      ];

      final chunkPromptsSeen = <String>[];
      String? mergePrompt;

      final service = SummarizerService(
        chat: ({
          required String systemPrompt,
          required String userPrompt,
          int maxTokens = 512,
          double temperature = 0.3,
        }) async {
          if (systemPrompt.contains('From the transcript chunk below')) {
            chunkPromptsSeen.add(userPrompt);
            return '# Steps\n- [00:00] did the thing';
          }
          mergePrompt = userPrompt;
          return '# Title\nMerged\n\n# Steps\n- [00:00] did the thing';
        },
      );

      final summary = await service.summarize(segments, fallbackTitle: 'Fallback');

      expect(chunkPromptsSeen, hasLength(3));
      expect(mergePrompt, isNotNull);
      expect(summary.title, 'Merged');
    });

    test('falls back to the given title when the model omits one', () async {
      final segments = [_seg(0, 3, 'hello world')];

      final service = SummarizerService(
        chat: ({
          required String systemPrompt,
          required String userPrompt,
          int maxTokens = 512,
          double temperature = 0.3,
        }) async =>
            '# Steps\n- no timestamp here',
      );

      final summary = await service.summarize(segments, fallbackTitle: 'Fallback Title');

      expect(summary.title, 'Fallback Title');
      // A step line with no [MM:SS] prefix still comes through, just without a timestamp.
      expect(summary.steps.single.text, 'no timestamp here');
      expect(summary.steps.single.timestampSeconds, isNull);
    });

    test('drops placeholder bullets like a lone "-" or "..."', () async {
      final segments = [_seg(0, 3, 'hello world')];

      final service = SummarizerService(
        chat: ({
          required String systemPrompt,
          required String userPrompt,
          int maxTokens = 512,
          double temperature = 0.3,
        }) async =>
            '''
# Title
A Title

# Steps
- [00:01] Do the real thing

# Insights
-
- ...

# Warnings
''',
      );

      final summary = await service.summarize(segments, fallbackTitle: 'Fallback');

      expect(summary.steps, hasLength(1));
      expect(summary.insights, isEmpty);
      expect(summary.warnings, isEmpty);
    });
  });
}
