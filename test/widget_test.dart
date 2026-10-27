// 书架页冒烟测试。
//
// widget 测试环境没有平台插件（sqflite / path_provider 等），
// 因此通过 Repositories.overrideForTest 注入内存实现后再 pump ReaderApp。

import 'package:flutter_test/flutter_test.dart';

import 'package:ebook_reader/app.dart';
import 'package:ebook_reader/data/models/annotation.dart';
import 'package:ebook_reader/data/models/book.dart';
import 'package:ebook_reader/data/repo/repositories.dart';

/// 内存版书库（测试替身）
class _MemLibrary implements LibraryRepository {
  final Map<String, Book> books = {};

  @override
  Future<List<Book>> getAllBooks() async => books.values.toList();

  @override
  Future<void> upsertBook(Book book) async => books[book.id] = book;

  @override
  Future<void> deleteBook(String id) async => books.remove(id);

  @override
  Future<Book?> getBook(String id) async => books[id];
}

class _MemAnnotations implements AnnotationRepository {
  final Map<String, List<Annotation>> byBook = {};

  @override
  Future<List<Annotation>> forBook(String bookId) async =>
      byBook[bookId] ?? const [];

  @override
  Future<void> upsert(Annotation a) async {
    final list = byBook.putIfAbsent(a.bookId, () => []);
    list.removeWhere((x) => x.id == a.id);
    list.add(a);
  }

  @override
  Future<void> remove(String id) async {
    for (final list in byBook.values) {
      list.removeWhere((x) => x.id == id);
    }
  }

  @override
  Future<void> removeForBook(String bookId) async => byBook.remove(bookId);
}

class _MemContent implements BookContentStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String bookId) async => _store[bookId];

  @override
  Future<void> write(String bookId, String content) async =>
      _store[bookId] = content;

  @override
  Future<void> delete(String bookId) async => _store.remove(bookId);
}

void main() {
  setUp(() {
    Repositories.overrideForTest(
      library: _MemLibrary(),
      annotations: _MemAnnotations(),
      content: _MemContent(),
    );
  });

  testWidgets('书架页冒烟测试：ReaderApp 可构建并显示空书架', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    await tester.pumpAndSettle();

    // 顶栏标题
    expect(find.text('书架'), findsOneWidget);
    // seedSampleBook 已将内置示例书播种进内存书库并显示在书架上
    expect(find.text('示例：山海异闻（内置样章）'), findsOneWidget);
  });
}
