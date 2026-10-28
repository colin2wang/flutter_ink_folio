import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 日志落盘：`<documents>/logs/app.log`，超过 [maxBytes] 轮转为 `app.log.1`。
///
/// 为什么必须落盘：[AppLog] 只是内存环形缓冲，进程被系统杀掉（黑屏、崩溃、
/// 强制退出）时，出事那一刻之前的日志会跟着一起消失，手机上就没法取证了。
/// 落盘后重开 App，日志页仍能把「上一次会话」整段复制出来。
class LogFile {
  LogFile._(this._file);

  /// 单文件上限 512KB（≈5000 行，能放两三个会话）；只留一份 .1，
  /// 磁盘总占用 < 1MB，墨水屏设备的存储也不心疼
  static const int maxBytes = 512 * 1024;

  final File _file;

  String get path => _file.path;

  /// 打开（必要时先轮转）。失败返回 null：落盘是辅助手段，不能影响主流程
  static Future<LogFile?> open() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'logs', 'app.log'));
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > maxBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
      }
      return LogFile._(file);
    } catch (_) {
      return null;
    }
  }

  Future<void> append(String text) async {
    try {
      await _file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      // 写失败（只读分区/空间满）：静默，内存缓冲仍然可用
    }
  }

  /// 文件尾部 [maxLines] 行；当前文件不够时再从 `.1` 里补一段，
  /// 否则刚好跨过轮转的那次会话会被截掉前半段
  Future<String> readTail({int maxLines = 600}) async {
    try {
      final current = await _tail(_file, maxLines);
      if (current.length >= maxLines) return current;
      final older = await _tail(File('${_file.path}.1'), maxLines - current.length);
      return older.isEmpty ? current : '$older\n$current';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _tail(File f, int maxLines) async {
    if (maxLines <= 0 || !await f.exists()) return '';
    final lines = const LineSplitter().convert(await f.readAsString());
    if (lines.isEmpty) return '';
    final from = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(from).join('\n');
  }
}
