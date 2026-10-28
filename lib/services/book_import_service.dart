import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';
import '../core/id_gen.dart';
import '../data/models/book.dart';
import '../data/repo/repositories.dart';
import 'book_blob_store.dart';
import 'file_pick.dart';

/// 导入结果。区分「用户取消」与「真的失败」，
/// 并带上原因——笼统一句「仅支持 .txt / .epub」会把所有失败都归错因。
class ImportResult {
  const ImportResult.ok(String this.bookId) : reason = null;
  const ImportResult.cancelled()
      : bookId = null,
        reason = null;
  const ImportResult.failed(String this.reason) : bookId = null;

  final String? bookId;
  final String? reason;

  /// 用户在文件选择器里点了取消：不该弹错误
  bool get isCancelled => bookId == null && reason == null;
  bool get isOk => bookId != null;
}

/// 导书 + 示例书播种。
/// Android：file_picker(SAF) → 拷贝到 <documents>/books/ → 入库。
/// Web：读 bytes，txt 正文写 WebContentStore，epub 二进制留在 [BookBlobStore]。
class BookImportService {
  BookImportService._();
  static final instance = BookImportService._();

  static const supported = ['txt', 'epub'];

  /// 选择器返回上限：旧版 file_picker 的 web 实现在部分浏览器上
  /// 「用户取消」时不会结束 Future，按钮会永久禁用且毫无反馈。
  /// 超时按取消处理并留日志，至少能把按钮解冻、能重试
  static const _pickTimeout = Duration(minutes: 3);

  Future<ImportResult> pickAndImport() async {
    // web 上不给选择器加扩展名过滤：`accept=".txt,.epub"` 会让 `.epub` 在部分
    // 系统上被当成未知类型置灰（看得见却选不中）。扩展名统一在 importBytes 里校验
    final filter = kIsWeb ? null : supported;
    appLog('[import] 选择器开始 filter=${filter?.join('/') ?? 'any'}');
    PickedFile? picked;
    try {
      picked = await pickSingleFile(extensions: filter)
          .timeout(_pickTimeout, onTimeout: () {
        appLog('[import] 选择器 ${_pickTimeout.inMinutes}min 无响应，按取消处理',
            level: 'W');
        return null;
      });
    } catch (e) {
      appLog('选择器失败: $e', level: 'E');
      return ImportResult.failed('打开文件选择器失败：$e');
    }
    if (picked == null) return const ImportResult.cancelled();
    appLog('pick: name=${picked.name} bytes=${picked.bytes?.length ?? -1} '
        'path=${picked.path}');
    return importBytes(
      bytes: picked.bytes,
      fileName: picked.name,
      fromPath: picked.path,
    );
  }

  /// 统一入口：优先用 bytes（web/ SAF withData），否则从 fromPath 拷贝
  Future<ImportResult> importBytes({
    Uint8ListLike? bytes,
    required String fileName,
    String? fromPath,
  }) async {
    // 扩展名只看文件名：web 上 file_picker 拿不到目录，中文/空格路径一律不参与
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    if (!supported.contains(ext)) {
      return ImportResult.failed('不支持的格式：$fileName（仅 .txt / .epub）');
    }
    try {
      final id = genId();
      String? storedPath = '';

      if (bytes == null || bytes.isEmpty) {
        if (fromPath == null) {
          return const ImportResult.failed('读不到文件内容（既没有数据也没有路径）');
        }
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

      // web 上没有可读的文件路径（file.path 只是 blob URL），字节就是唯一来源，
      // 取不到就是取不到，不能当成功入库
      if (kIsWeb && (bytes == null || bytes.isEmpty)) {
        return const ImportResult.failed('没取到文件字节，请重试或换一个文件');
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

      if (bytes != null && bytes.isNotEmpty) {
        if (ext == 'txt') {
          final text = _decodeText(bytes);
          await Repositories.content.write(id, text);
        } else if (kIsWeb) {
          // web 没有沙盒可落盘：二进制留在内存，openBook 时以 base64 下发
          BookBlobStore.instance.put(
              id, bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
        }
      }
      await Repositories.library.upsertBook(book);
      return ImportResult.ok(id);
    } catch (e, st) {
      appLog('import failed: $e\n$st', level: 'E');
      return ImportResult.failed('导入失败：$e');
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

  /// 读取正文（txt 全量读字符串；epub 由 TS 引擎自己解析：
  /// Android 读 `filePath`，web 读 openBook 里的 `dataBase64`）
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

/// 字节入参的宽松类型：file_picker 与自建选择器都可能给 Uint8List
/// （抽象一层避免平台类型噪音）
typedef Uint8ListLike = List<int>;
