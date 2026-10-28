import 'log_file_io.dart' if (dart.library.html) 'log_file_stub.dart' as impl;
import 'log_file_io.dart' if (dart.library.html) 'log_file_stub.dart' show LogFile;

export 'log_file_io.dart' if (dart.library.html) 'log_file_stub.dart' show LogFile;

/// 打开（必要时先轮转）日志文件；web 上直接返回 null。
///
/// 平台差异见 `log_file_io.dart` / `log_file_stub.dart`，
/// 调用方（[AppLog]）不需要再判平台。
Future<LogFile?> openLogFile() => impl.LogFile.open();
