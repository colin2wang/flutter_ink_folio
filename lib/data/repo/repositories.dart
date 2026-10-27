import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/annotation.dart';
import '../models/book.dart';

/// 仓储抽象：移动端 sqflite / web 端 SharedPreferences+内存，接口一致。
abstract class LibraryRepository {
  Future<List<Book>> getAllBooks();
  Future<void> upsertBook(Book book);
  Future<void> deleteBook(String id);
  Future<Book?> getBook(String id);
}

abstract class AnnotationRepository {
  Future<List<Annotation>> forBook(String bookId);
  Future<void> upsert(Annotation a);
  Future<void> remove(String id);
  Future<void> removeForBook(String bookId);
}

/// web 下 txt 正文存放点（文件系统不可用，直接放 prefs/内存）
abstract class BookContentStore {
  Future<String?> read(String bookId);
  Future<void> write(String bookId, String content);
  Future<void> delete(String bookId);
}

// ---------------------------------------------------------------------------
// sqflite 实现（Android）
// ---------------------------------------------------------------------------

class SqfliteLibraryRepository implements LibraryRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  @override
  Future<List<Book>> getAllBooks() async {
    final rows = await (await _db)
        .query('books', orderBy: 'COALESCE(lastReadAt, addedAt) DESC');
    return rows.map(Book.fromRow).toList();
  }

  @override
  Future<void> upsertBook(Book b) async {
    await (await _db).insert('books', b.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteBook(String id) async {
    await (await _db).delete('books', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Book?> getBook(String id) async {
    final rows = await (await _db)
        .query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }
}

class SqfliteAnnotationRepository implements AnnotationRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  @override
  Future<List<Annotation>> forBook(String bookId) async {
    final rows = await (await _db).query('annotations',
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'startOffset IS NULL, startOffset, createdAt');
    return rows.map(Annotation.fromRow).toList();
  }

  @override
  Future<void> upsert(Annotation a) async {
    await (await _db).insert('annotations', a.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(String id) async {
    await (await _db).delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> removeForBook(String bookId) async {
    await (await _db)
        .delete('annotations', where: 'bookId = ?', whereArgs: [bookId]);
  }
}

/// 移动端：正文就在沙盒文件里，无需独立 content store
class FileContentStore implements BookContentStore {
  @override
  Future<String?> read(String bookId) async => null;

  @override
  Future<void> write(String bookId, String content) async {}

  @override
  Future<void> delete(String bookId) async {}
}

// ---------------------------------------------------------------------------
// Web 实现（chrome 联调）：内存 + SharedPreferences 持久化
// ---------------------------------------------------------------------------

class WebLibraryRepository implements LibraryRepository {
  static const _kBooks = 'web_books';
  final Map<String, Book> _cache = {};

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Map<String, Book>> _load() async {
    if (_cache.isNotEmpty) return _cache;
    final raw = (await _prefs).getString(_kBooks);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final j in list) {
        final b = Book.fromJson(j);
        _cache[b.id] = b;
      }
    }
    return _cache;
  }

  Future<void> _persist() async {
    final raw = jsonEncode(_cache.values.map((b) => b.toJson()).toList());
    await (await _prefs).setString(_kBooks, raw);
  }

  @override
  Future<List<Book>> getAllBooks() async {
    final m = await _load();
    final list = m.values.toList()
      ..sort((a, b) =>
          (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
    return list;
  }

  @override
  Future<void> upsertBook(Book b) async {
    await _load();
    _cache[b.id] = b;
    await _persist();
  }

  @override
  Future<void> deleteBook(String id) async {
    await _load();
    _cache.remove(id);
    await _persist();
  }

  @override
  Future<Book?> getBook(String id) async => (await _load())[id];
}

class WebAnnotationRepository implements AnnotationRepository {
  static const _kAnnotations = 'web_annotations';
  final Map<String, List<Annotation>> _cache = {};

  Future<Map<String, List<Annotation>>> _load() async {
    if (_cache.isNotEmpty) return _cache;
    final raw = (await SharedPreferences.getInstance()).getString(_kAnnotations);
    if (raw != null) {
      final obj = (jsonDecode(raw) as Map).cast<String, dynamic>();
      obj.forEach((k, v) {
        _cache[k] =
            (v as List).map((e) => Annotation.fromJson((e as Map).cast<String, dynamic>())).toList();
      });
    }
    return _cache;
  }

  Future<void> _persist() async {
    final raw = jsonEncode(_cache.map((k, v) => MapEntry(
        k, v.map((a) => a.toJson()).toList())));
    await SharedPreferences.getInstance()
        .then((p) => p.setString(_kAnnotations, raw));
  }

  @override
  Future<List<Annotation>> forBook(String bookId) async =>
      List.of((await _load())[bookId] ?? const []);

  @override
  Future<void> upsert(Annotation a) async {
    final m = await _load();
    final list = m.putIfAbsent(a.bookId, () => []);
    list.removeWhere((x) => x.id == a.id);
    list.add(a);
    await _persist();
  }

  @override
  Future<void> remove(String id) async {
    for (final list in (await _load()).values) {
      list.removeWhere((x) => x.id == id);
    }
    await _persist();
  }

  @override
  Future<void> removeForBook(String bookId) async {
    (await _load()).remove(bookId);
    await _persist();
  }
}

class WebContentStore implements BookContentStore {
  String _key(String id) => 'web_book_content_$id';

  @override
  Future<String?> read(String bookId) async =>
      (await SharedPreferences.getInstance()).getString(_key(bookId));

  @override
  Future<void> write(String bookId, String content) async {
    final p = await SharedPreferences.getInstance();
    try {
      await p.setString(_key(bookId), content);
    } catch (e) {
      // localStorage 超 5MB 时会抛错：大书在 web 端只保留内存副本
      debugPrint('WebContentStore.write skipped: $e');
    }
  }

  @override
  Future<void> delete(String bookId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(bookId));
  }
}

// ---------------------------------------------------------------------------
// 平台工厂
// ---------------------------------------------------------------------------

class Repositories {
  Repositories._();

  static LibraryRepository? _library;
  static AnnotationRepository? _annotations;
  static BookContentStore? _content;

  static LibraryRepository get library =>
      _library ??= kIsWeb ? WebLibraryRepository() : SqfliteLibraryRepository();

  static AnnotationRepository get annotations =>
      _annotations ??= kIsWeb ? WebAnnotationRepository() : SqfliteAnnotationRepository();

  static BookContentStore get content =>
      _content ??= kIsWeb ? WebContentStore() : FileContentStore();

  /// 测试注入点：widget 测试无平台插件（sqflite 等），需换内存实现
  @visibleForTesting
  static void overrideForTest({
    LibraryRepository? library,
    AnnotationRepository? annotations,
    BookContentStore? content,
  }) {
    _library = library;
    _annotations = annotations;
    _content = content;
  }
}
