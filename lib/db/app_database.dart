import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/video_card.dart';

/// Wraps the local SQLite database that acts as FramePrint's offline
/// "paper database" catalog of VideoCards.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'frameprint'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'frameprint.db');

    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE video_card ADD COLUMN duration_seconds INTEGER',
            );
          }
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE video_card (
              id TEXT PRIMARY KEY,
              youtube_url TEXT NOT NULL,
              created_at TEXT NOT NULL,
              local_video_path TEXT,
              local_audio_path TEXT,
              gif_path TEXT,
              frames_dir TEXT,
              duration_seconds INTEGER,
              segment_start INTEGER,
              segment_end INTEGER,
              selected_frames TEXT,
              transcript_text TEXT,
              summary_title TEXT,
              summary_steps TEXT,
              summary_insights TEXT,
              summary_warnings TEXT,
              pdf_path TEXT,
              qr_payload TEXT,
              status TEXT NOT NULL,
              error_message TEXT
            )
          ''');
        },
      ),
    );
  }

  /// Where downloaded videos/audio/frames/pdfs for a given card are stored:
  /// `<app support dir>/frameprint/media/<card id>/`
  Future<Directory> mediaDirFor(String cardId) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(supportDir.path, 'frameprint', 'media', cardId),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> insertCard(VideoCard card) async {
    final db = await database;
    await db.insert(
      'video_card',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCard(VideoCard card) async {
    final db = await database;
    await db.update(
      'video_card',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deleteCard(String id) async {
    final db = await database;
    await db.delete('video_card', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<VideoCard>> allCards() async {
    final db = await database;
    final rows = await db.query('video_card', orderBy: 'created_at DESC');
    return rows.map(VideoCard.fromMap).toList();
  }
}
