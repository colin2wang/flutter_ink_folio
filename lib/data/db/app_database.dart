import 'package:sqflite/sqflite.dart';

/// 书库 DB（sqflite）。v1：books + annotations 两张表。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'inkreader.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    return openDatabase(
      _dbName,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT NOT NULL DEFAULT '',
            filePath TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'txt',
            addedAt INTEGER NOT NULL,
            lastReadAt INTEGER,
            percent REAL NOT NULL DEFAULT 0,
            cfi TEXT,
            startOffset INTEGER NOT NULL DEFAULT 0,
            chapterIndex INTEGER NOT NULL DEFAULT 0,
            colorIndex INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_books_lastRead ON books(lastReadAt DESC)');
        await db.execute('''
          CREATE TABLE annotations (
            id TEXT PRIMARY KEY,
            bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            kind TEXT NOT NULL DEFAULT 'highlight',
            text TEXT NOT NULL DEFAULT '',
            note TEXT,
            cfiRange TEXT,
            startOffset INTEGER,
            endOffset INTEGER,
            chapterTitle TEXT,
            colorIndex INTEGER NOT NULL DEFAULT 2,
            createdAt INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_annotations_book ON annotations(bookId, createdAt DESC)');
      },
      onUpgrade: (db, oldV, newV) async {
        // 未来迁移在此追加
      },
    );
  }
}
