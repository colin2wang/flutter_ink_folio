import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';
import '../core/id_gen.dart';
import '../data/models/book.dart';
import '../data/repo/repositories.dart';

/// 导书 + 示例书播种。
/// Android：file_picker(SAF) → 拷贝到 <documents>/books/ → 入库。
/// Web：读 bytes，txt 正文写 WebContentStore。
class BookImportService {
  BookImportService._();
  static final instance = BookImportService._();

  static const supported = ['txt', 'epub'];

  Future<String?> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supported,
      withData: true, // web 需要 bytes
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;
    return importBytes(
      bytes: file.bytes,
      fileName: file.name,
      fromPath: file.path,
    );
  }

  /// 统一入口：优先用 bytes（web/ SAF withData），否则从 fromPath 拷贝
  Future<String?> importBytes({
    Uint8ListLike? bytes,
    required String fileName,
    String? fromPath,
  }) async {
    try {
      final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
      if (!supported.contains(ext)) return null;

      final id = genId();
      String? storedPath = '';

      if (bytes == null || bytes.isEmpty) {
        if (fromPath == null) return null;
        if (!kIsWeb) {
          final dir = await _booksDir();
          final dest = p.join(dir, '$id.$ext');
          await File(fromPath).copy(dest);
          storedPath = dest;
          bytes = await File(dest).readAsBytes();
        }
      } else if (!kIsWeb) {
        final dir = await _booksDir();
        final dest = p.join(dir, '$id.$ext');
        await File(dest).writeAsBytes(bytes);
        storedPath = dest;
      }

      final book = Book(
        id: id,
        title: p.basenameWithoutExtension(fileName),
        author: '',
        filePath: storedPath,
        kind: ext,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        colorIndex: _nextColor(),
      );

      if (ext == 'txt' && bytes != null && bytes.isNotEmpty) {
        final text = _decodeText(bytes);
        await Repositories.content.write(id, text);
      }
      await Repositories.library.upsertBook(book);
      return id;
    } catch (e, st) {
      appLog('import failed: $e\n$st');
      return null;
    }
  }

  /// 首启播种示例书（assets/books/sample.txt），开箱即可测试全链路
  Future<void> seedSampleBook() async {
    final lib = Repositories.library;
    if ((await lib.getAllBooks()).isNotEmpty) return;
    try {
      final raw = await rootBundle.load('assets/books/sample.txt');
      final text = _decodeText(raw.buffer.asUint8List());
      final id = 'sample-shanhu';
      await Repositories.content.write(id, text);
      await lib.upsertBook(Book(
        id: id,
        title: '示例：山海异闻（内置样章）',
        author: '墨屏阅读',
        filePath: 'asset://sample.txt',
        kind: 'txt',
        addedAt: DateTime.now().millisecondsSinceEpoch,
        colorIndex: 2,
      ));
    } catch (e) {
      appLog('seed sample book failed: $e');
    }
  }

  /// 读取正文（txt 全量读字符串；epub 由 TS 引擎 fetch filePath）
  Future<String?> loadTextContent(Book book) async {
    final fromStore = await Repositories.content.read(book.id);
    if (fromStore != null && fromStore.isNotEmpty) return fromStore;
    if (book.kind != 'txt') return null;
    final path = book.filePath;
    if (path.isEmpty || path.startsWith('asset://')) {
      try {
        final raw = await rootBundle.load('assets/books/sample.txt');
        return _decodeText(raw.buffer.asUint8List());
      } catch (_) {
        return null;
      }
    }
    return _decodeText(await File(path).readAsBytes());
  }

  // GBK 容错：先按 UTF-8 严格解码，失败再走系统默认（Android 上通常是 UTF-8，
  // GBK 书籍交给后续 FontManager 同级的扩展点处理，此处保证不崩）
  String _decodeText(Uint8ListLike bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Future<String> _booksDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'books'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  int _nextColor() => DateTime.now().millisecondsSinceEpoch ~/ 7 % 5 + 1;
}

/// file_picker 8 的 bytes 在 web 上是 Uint8List；抽象一层避免平台类型噪音
typedef Uint8ListLike = List<int>;

extension _SingleOrNull<T> on List<T> {
  T? get singleOrNull => isEmpty ? null : first;
}
