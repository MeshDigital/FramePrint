import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/video_card.dart';
import '../services/ytdlp_service.dart';

class NewCardScreen extends StatefulWidget {
  const NewCardScreen({super.key});

  @override
  State<NewCardScreen> createState() => _NewCardScreenState();
}

class _NewCardScreenState extends State<NewCardScreen> {
  final _urlController = TextEditingController();
  final _ytDlp = YtDlpService();
  final _log = <String>[];

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    setState(() => _log.add(line));
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (!_ytDlp.isValidYoutubeUrl(url)) {
      setState(() => _error = 'Enter a valid YouTube URL');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _log.clear();
    });

    final card = VideoCard(
      id: const Uuid().v4(),
      youtubeUrl: url,
      createdAt: DateTime.now(),
      qrPayload: url,
      status: CardStatus.downloading,
    );

    try {
      await AppDatabase.instance.insertCard(card);

      _appendLog('Fetching video info...');
      final metadata = await _ytDlp.fetchMetadata(url);
      card.summaryTitle = metadata.title;
      _appendLog('Found: ${metadata.title}');

      final mediaDir = await AppDatabase.instance.mediaDirFor(card.id);
      final outputTemplate = p.join(mediaDir.path, 'source.%(ext)s');

      _appendLog('Downloading video...');
      final downloadedPath = await _ytDlp.downloadVideo(
        url,
        outputTemplate,
        onOutput: _appendLog,
      );

      card
        ..localVideoPath = downloadedPath
        ..status = CardStatus.downloaded;
      await AppDatabase.instance.updateCard(card);

      _appendLog('Done: $downloadedPath');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      card
        ..status = CardStatus.error
        ..errorMessage = e.toString();
      await AppDatabase.instance.updateCard(card);
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New card')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'YouTube URL',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _busy ? null : _startDownload(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _startDownload,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Download'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.black87,
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (context, index) => Text(
                    _log[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
