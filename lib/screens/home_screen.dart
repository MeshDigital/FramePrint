import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/video_card.dart';
import 'new_card_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<VideoCard>> _cardsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _cardsFuture = AppDatabase.instance.allCards();
    });
  }

  Future<void> _openNewCard() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewCardScreen()),
    );
    if (created == true) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FramePrint')),
      body: FutureBuilder<List<VideoCard>>(
        future: _cardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final cards = snapshot.data ?? [];
          if (cards.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No cards yet.\nTap + to turn a YouTube video into a printable card.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return ListTile(
                leading: _statusIcon(card.status),
                title: Text(card.summaryTitle ?? card.youtubeUrl),
                subtitle: Text(card.status.name),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewCard,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _statusIcon(CardStatus status) {
    switch (status) {
      case CardStatus.pending:
        return const Icon(Icons.schedule);
      case CardStatus.downloading:
        return const Icon(Icons.downloading);
      case CardStatus.downloaded:
        return const Icon(Icons.movie);
      case CardStatus.processing:
        return const Icon(Icons.auto_awesome);
      case CardStatus.ready:
        return const Icon(Icons.check_circle, color: Colors.green);
      case CardStatus.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }
}
