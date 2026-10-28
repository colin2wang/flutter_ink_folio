import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// 一条运行日志：时间 + 级别 + 正文。
class LogEntry {
  LogEntry(this.time, this.level, this.message);

  final DateTime time;

  /// I 普通 / W 警告 / E 错误
  final String level;
  final String message;

  String get line => '${_hms(time)} [$level] $message';

  static String _hms(DateTime t) => '${_pad(t.hour, 2)}:${_pad(t.minute, 2)}:'
      '${_pad(t.second, 2)}.${_pad(t.millisecond, 3)}';

  static String _pad(int v, int width) => v.toString().padLeft(width, '0');
}

/// 运行日志环形缓冲 + 全局异常捕获。
///
/// 为什么要自己存一份：release APK 里 `debugPrint` 不进控制台，
/// 手机上的问题只能靠「进 App 里把日志复制出来」定位（入口见书架顶栏）。
/// 缓冲始终生效（debug/release 都一样），上限 [capacity] 条。
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 上限：2000 条。每条几十字节，整体远小于 1MB，墨水屏设备也不吃内存
  static const int capacity = 2000;

  final List<LogEntry> _entries = <LogEntry>[];
  int _dropped = 0;
  Timer? _notify;

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  int get count => _entries.length;

  /// 因超出上限被丢弃的最早条数
  int get dropped => _dropped;

  void add(String level, String message) {
    _entries.add(LogEntry(DateTime.now(), level, message));
    if (_entries.length > capacity) {
      final over = _entries.length - capacity;
      _entries.removeRange(0, over);
      _dropped += over;
    }
    _scheduleNotify();
  }

  void clear() {
    _entries.clear();
    _dropped = 0;
    _scheduleNotify();
  }

  /// 合并通知：引擎一串事件常连打十几条，逐条 notify 会让日志页反复重绘
  void _scheduleNotify() {
    if (_notify != null) return;
    _notify = Timer(const Duration(milliseconds: 150), () {
      _notify = null;
      notifyListeners();
    });
  }

  /// 复制用的纯文本：带环境信息，方便对照平台差异定位
  String dump() {
    final buf = StringBuffer()
      ..writeln('墨屏阅读 运行日志')
      ..writeln('平台: ${_platform()} / ${_mode()}')
      ..writeln('导出时间: ${DateTime.now()}')
      ..writeln('条数: ${_entries.length}'
          '${_dropped > 0 ? '（已丢弃最早 $_dropped 条）' : ''}')
      ..writeln('-' * 48);
    for (final e in _entries) {
      buf.writeln(e.line);
    }
    return buf.toString();
  }

  /// 未处理的 Flutter 异常 / 异步异常也进缓冲，否则它们只会打在控制台里
  void install() {
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      add('E', 'FlutterError: ${details.exceptionAsString()}'
          '${details.stack == null ? '' : '\n${details.stack}'}');
      prevOnError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add('E', '未捕获异常: $error\n$stack');
      return false; // 继续交给平台默认处理（会打控制台）
    };
  }

  static String _platform() => kIsWeb ? 'web' : defaultTargetPlatform.name;

  static String _mode() => kReleaseMode
      ? 'release'
      : kProfileMode
          ? 'profile'
          : 'debug';
}

/// 轻量日志：始终进缓冲；debug 下同时打控制台。
///
/// 签名兼容旧调用（`appLog('...')`），需要标级别时传 `level: 'E'`。
void appLog(String message, {String level = 'I'}) {
  AppLog.instance.add(level, message);
  if (kDebugMode) debugPrint('[inkreader] $message');
}
