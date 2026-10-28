/// web 实现：浏览器沙盒里没有可写的日志路径，日志只留在内存环形缓冲里。
///
/// 接口与 [LogFile]（log_file_io.dart）保持一致，调用方不需要分支。
class LogFile {
  LogFile._();

  static const int maxBytes = 0;

  String get path => '';

  static Future<LogFile?> open() async => null;

  Future<void> append(String text) async {}

  Future<String> readTail({int maxLines = 600}) async => '';
}
