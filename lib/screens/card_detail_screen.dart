import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../models/video_card.dart';
import '../services/ffmpeg_service.dart';

class CardDetailScreen extends StatefulWidget {
  final VideoCard card;

  const CardDetailScreen({super.key, required this.card});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final _ffmpeg = FfmpegService();

  late RangeValues _range;
  bool _busy = false;
  String? _error;
  List<File> _frames = [];
  final Set<String> _selectedFramePaths = {};
  File? _gifFile;

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
    _loadExistingFrames();
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
              ],
            ),
    );
  }
}
