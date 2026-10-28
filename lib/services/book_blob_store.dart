import 'dart:typed_data';

/// web 调试环境的内存二进制缓存。
///
/// 为什么需要它：web 上引擎读不到本地文件——`fetch` 不支持 `file:`
/// （见 `web_engine/src/io.ts`），也没有 `getApplicationDocumentsDirectory`
/// 那样的沙盒路径可写。TXT 可以靠 `openBook.text` 直传，EPUB 是 zip 只能
/// 由引擎自己解析，于是由 Dart 把字节读下来、以 base64 内嵌进 openBook 下发。
///
/// 代价：**只在内存里**，刷新页面即失效，那本书需要重新导入一次。
/// 调试环境可以接受；Android 始终走 `filePath`，不经过这里。
class BookBlobStore {
  BookBlobStore._();
  static final BookBlobStore instance = BookBlobStore._();

  final Map<String, Uint8List> _blobs = <String, Uint8List>{};

  void put(String bookId, Uint8List bytes) => _blobs[bookId] = bytes;

  Uint8List? get(String bookId) => _blobs[bookId];

  bool has(String bookId) => _blobs.containsKey(bookId);

  void remove(String bookId) => _blobs.remove(bookId);
}
