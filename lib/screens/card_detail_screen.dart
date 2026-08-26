import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../models/video_card.dart';
import '../services/ffmpeg_service.dart';
import '../services/summarizer_service.dart';
import '../services/whisper_service.dart';
import 'pdf_preview_screen.dart';

class CardDetailScreen extends StatefulWidget {
  final VideoCard card;

  const CardDetailScreen({super.key, required this.card});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final _ffmpeg = FfmpegService();
  final _whisper = WhisperService();
  final _summarizer = SummarizerService();

  late RangeValues _range;
  bool _busy = false;
  String? _error;
  List<File> _frames = [];
  final Set<String> _selectedFramePaths = {};
  File? _gifFile;

  bool _transcribing = false;
  String? _transcribeError;
  String? _transcript;

  bool _summarizing = false;
  String? _summarizeError;
  CardSummary? _summary;

  static const _maxSelectedFrames = 6;

  int get _duration => widget.card.durationSeconds ?? 60;

  @override
  void initState() {
    super.initState();
    final start = widget.card.segmentStartSeconds ?? 0;
    final end = widget.card.segmentEndSeconds ??
        (_duration < 60 ? _duration : 60);
    _range = RangeValues(start.toDouble(), end.clamp(start, _duration).toDouble());
    _selectedFramePaths.addAll(widget.card.selectedFrames);
    _transcript = widget.card.transcriptText;
    if (widget.card.summarySteps.isNotEmpty ||
        widget.card.summaryInsights.isNotEmpty ||
        widget.card.summaryWarnings.isNotEmpty) {
      _summary = CardSummary(
        title: widget.card.summaryTitle ?? 'Untitled',
        steps: widget.card.summarySteps,
        insights: widget.card.summaryInsights,
        warnings: widget.card.summaryWarnings,
      );
    }
    _loadExistingFrames();
  }

  Future<void> _transcribeAudio() async {
    setState(() {
      _transcribing = true;
      _transcribeError = null;
    });
    try {
      final mediaDir = await AppDatabase.instance.mediaDirFor(widget.card.id);
      final audioPath = p.join(mediaDir.path, 'audio.wav');

      await _ffmpeg.extractAudio(
        videoPath: widget.card.localVideoPath!,
        outputAudioPath: audioPath,
      );

      final result = await _whisper.transcribe(audioPath);

      widget.card
        ..localAudioPath = audioPath
        ..transcriptText = result.fullText
        ..transcriptSegments = result.segments;
      await AppDatabase.instance.updateCard(widget.card);

      setState(() => _transcript = result.fullText);
    } catch (e) {
      setState(() => _transcribeError = e.toString());
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _summarize() async {
    setState(() {
      _summarizing = true;
      _summarizeError = null;
    });
    try {
      final summary = await _summarizer.summarize(
        widget.card.transcriptSegments,
        fallbackTitle: widget.card.summaryTitle ?? 'Untitled',
      );

      // Grab a frame from the exact moment each step was said, so the
      // printed card shows the right picture next to the right instruction.
      final mediaDir = await AppDatabase.instance.mediaDirFor(widget.card.id);
      final stepFramesDir = Directory(p.join(mediaDir.path, 'step_frames'));
      if (await stepFramesDir.exists()) {
        await stepFramesDir.delete(recursive: true);
      }
      await stepFramesDir.create(recursive: true);

      for (var i = 0; i < summary.steps.length; i++) {
        final step = summary.steps[i];
        if (step.timestampSeconds == null) continue;
        final framePath = p.join(
          stepFramesDir.path,
          'step_${i.toString().padLeft(2, '0')}.png',
        );
        try {
          await _ffmpeg.extractFrameAt(
            videoPath: widget.card.localVideoPath!,
            atSeconds: step.timestampSeconds!,
            outputPath: framePath,
          );
          step.framePath = framePath;
        } catch (_) {
          // Leave framePath null for this step if extraction fails.
        }
      }

      widget.card
        ..summaryTitle = summary.title
        ..summarySteps = summary.steps
        ..summaryInsights = summary.insights
        ..summaryWarnings = summary.warnings
        ..status = CardStatus.ready;
      await AppDatabase.instance.updateCard(widget.card);

      setState(() => _summary = summary);
    } catch (e) {
      setState(() => _summarizeError = e.toString());
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _loadExistingFrames() async {
    final dir = widget.card.framesDir;
    if (dir == null) return;
    final d = Directory(dir);
    if (!await d.exists()) return;
    final files = (await d.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (mounted) setState(() => _frames = files);
  }

  Future<void> _extractFrames() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mediaDir = await AppDatabase.instance.mediaDirFor(widget.card.id);
      final framesDir = p.join(mediaDir.path, 'frames');

      final dir = Directory(framesDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      await _ffmpeg.extractFrames(
        videoPath: widget.card.localVideoPath!,
        startSeconds: _range.start.round(),
        endSeconds: _range.end.round(),
        outputDir: framesDir,
      );

      widget.card.framesDir = framesDir;
      widget.card.segmentStartSeconds = _range.start.round();
      widget.card.segmentEndSeconds = _range.end.round();
      await AppDatabase.instance.updateCard(widget.card);

      await _loadExistingFrames();
      setState(() => _selectedFramePaths.clear());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeGif() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mediaDir = await AppDatabase.instance.mediaDirFor(widget.card.id);
      final gifPath = p.join(mediaDir.path, 'preview.gif');

      await _ffmpeg.makeGif(
        videoPath: widget.card.localVideoPath!,
        startSeconds: _range.start.round(),
        endSeconds: _range.end.round(),
        outputGifPath: gifPath,
      );

      widget.card.gifPath = gifPath;
      widget.card.segmentStartSeconds = _range.start.round();
      widget.card.segmentEndSeconds = _range.end.round();
      await AppDatabase.instance.updateCard(widget.card);

      setState(() => _gifFile = File(gifPath));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleFrame(String path) {
    setState(() {
      if (_selectedFramePaths.contains(path)) {
        _selectedFramePaths.remove(path);
      } else if (_selectedFramePaths.length < _maxSelectedFrames) {
        _selectedFramePaths.add(path);
      }
    });
  }

  Future<void> _saveSelection() async {
    widget.card
      ..selectedFrames = _selectedFramePaths.toList()
      ..status = CardStatus.processing;
    await AppDatabase.instance.updateCard(widget.card);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Scaffold(
      appBar: AppBar(title: Text(card.summaryTitle ?? 'Card')),
      body: card.localVideoPath == null
          ? const Center(child: Text('Video not downloaded yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pick the segment to turn into a card (${_fmt(_range.start.round())} - ${_fmt(_range.end.round())})',
                ),
                RangeSlider(
                  values: _range,
                  min: 0,
                  max: _duration.toDouble().clamp(1, double.infinity),
                  divisions: _duration > 0 ? _duration : null,
                  labels: RangeLabels(
                    _fmt(_range.start.round()),
                    _fmt(_range.end.round()),
                  ),
                  onChanged: _busy
                      ? null
                      : (values) => setState(() => _range = values),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _extractFrames,
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Extract frames'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _makeGif,
                      icon: const Icon(Icons.gif),
                      label: const Text('Make preview GIF'),
                    ),
                  ],
                ),
                if (_busy) const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_gifFile != null) ...[
                  const SizedBox(height: 16),
                  Image.file(_gifFile!, height: 180),
                ],
                if (_frames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tap up to $_maxSelectedFrames key frames '
                    '(${_selectedFramePaths.length}/$_maxSelectedFrames selected)',
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _frames.length,
                    itemBuilder: (context, index) {
                      final file = _frames[index];
                      final selected = _selectedFramePaths.contains(file.path);
                      return GestureDetector(
                        onTap: () => _toggleFrame(file.path),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(file, fit: BoxFit.cover),
                            if (selected)
                              Container(
                                color: Colors.black45,
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _selectedFramePaths.isEmpty ? null : _saveSelection,
                    child: const Text('Save selection'),
                  ),
                ],
                const Divider(height: 32),
                Text('Transcript', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _transcribing ? null : _transcribeAudio,
                  icon: const Icon(Icons.subtitles),
                  label: Text(_transcript == null
                      ? 'Transcribe audio'
                      : 'Re-transcribe audio'),
                ),
                if (_transcribing) const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
                if (_transcribeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _transcribeError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_transcript != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_transcript!),
                  ),
                const Divider(height: 32),
                Text('Summary', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: (widget.card.transcriptSegments.isEmpty || _summarizing)
                      ? null
                      : _summarize,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_summary == null ? 'Summarize (local LLM)' : 'Re-summarize'),
                ),
                if (widget.card.transcriptSegments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Transcribe the audio first.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (_summarizing)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 4),
                        Text(
                          'Starting local model if needed, then summarizing...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                if (_summarizeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _summarizeError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_summary != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _summary!.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _StepsSection(steps: _summary!.steps),
                  _SummarySection(title: 'Insights', items: _summary!.insights),
                  _SummarySection(title: 'Warnings', items: _summary!.warnings),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PdfPreviewScreen(card: widget.card),
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generate printable card'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  final List<SummaryStep> steps;

  const _StepsSection({required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Steps', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...steps.asMap().entries.map((entry) {
            final step = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step.framePath != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(step.framePath!),
                          width: 90,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  Expanded(child: Text('${entry.key + 1}. ${step.text}')),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SummarySection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(item)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
