import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import 'bridge_protocol.dart';

typedef TsEventHandler = void Function(String event, Map<String, dynamic> payload);

/// Dart → TS 的调用封装 + TS → Dart 的事件分发（仅 Android/iOS 用）。
///
/// 下行 evaluateJavascript 调 window.__reader.dispatch，上行 JavaScriptHandler。
/// Web(chrome/edge) 不再走这里：该平台没有 addJavaScriptHandler，
/// 阅读页改为自建同源 iframe + postMessage（见 bridge/engine_host.dart）。
class JsBridge {
  JsBridge(this._onEvent);

  final TsEventHandler _onEvent;
  InAppWebViewController? _controller;
  bool _pageReady = false;
  final List<Map<String, dynamic>> _pending = [];

  /// TS → Dart 上行通道绑定（JavaScriptHandler）。
  void bind(InAppWebViewController controller) {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: DartEvent.handlerName,
      callback: (args) {
        if (args.isEmpty) return null;
        try {
          final raw = args.first;
          final Map<String, dynamic> msg;
          if (raw is String) {
            msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
          } else if (raw is Map) {
            msg = raw.cast<String, dynamic>();
          } else {
            return null;
          }
          _handleMessage(msg);
        } catch (e) {
          appLog('JsBridge handler error: $e');
        }
        return null;
      },
    );
  }

  void _handleMessage(Map<String, dynamic> msg) {
    try {
      final event = msg['action'] as String?;
      final payload = (msg['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      if (event == null) return;
      if (event == DartEvent.onReady) _pageReady = true;
      _onEvent(event, payload);
      if (event == DartEvent.onReady) _flushPending();
    } catch (e) {
      appLog('JsBridge message error: $e');
    }
  }

  void detach() {
    _controller = null;
    _pageReady = false;
    _pending.clear();
  }

  /// 页面已 load：`defer` 脚本先于 load 事件执行，此时 `window.__reader` 必定存在。
  ///
  /// 下行不等 onReady：原生桥注入慢/丢包时 onReady 可能到不了，
  /// 那样队列里的 openBook 就永远发不出去（手机白屏）。
  void markPageReady() {
    if (_pageReady) return;
    _pageReady = true;
    _flushPending();
  }

  /// Dart → TS：等 onReady 后再发，未就绪先进队列（页面加载竞态保护）
  Future<void> post(String action, Map<String, dynamic> payload) async {
    final msg = BridgeMessage(action: action, payload: payload).toJson();
    if (!_pageReady) {
      _pending.add(msg);
      return;
    }
    await _send(msg);
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    final list = List.of(_pending);
    _pending.clear();
    for (final msg in list) {
      _send(msg);
    }
  }

  /// 取证用：在页面里跑一段 JS 并把结果拿回来（Android/iOS 才有）。
  ///
  /// 手机白屏时靠它一次问清：脚本/原生桥在不在、正文画出来没有、视口多大。
  Future<String?> evalRaw(String js) async {
    final c = _controller;
    if (c == null) return null;
    try {
      final value = await c.evaluateJavascript(source: js);
      return value == null ? 'null' : value.toString();
    } catch (e) {
      return 'eval failed: $e';
    }
  }

  Future<void> _send(Map<String, dynamic> msg) async {
    final c = _controller;
    if (c == null) return;
    // U+2028/2029 在 JS 源码里是行终结符，JSON 合法但塞进 eval 会变 SyntaxError
    final encoded = jsonEncode(msg)
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
    final source = 'window.__reader && window.__reader.dispatch($encoded);';
    if (source.length > 200000) {
      appLog('JsBridge: 下发报文 ${source.length} 字符，Android 可能被截断',
          level: 'W');
    }
    try {
      await c.evaluateJavascript(source: source);
    } catch (e) {
      appLog('JsBridge post(${msg['action']}) error: $e', level: 'E');
    }
  }
}

/// WebView 初始设置：墨水屏向的关动画/开文件访问。
InAppWebViewSettings webViewSettings() {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    transparentBackground: true,
    // 本地文件：引擎用 XHR 读沙盒里的书籍/字体/epub（fetch 不支持 file://）
    allowFileAccess: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    // 墨水屏：禁掉一切动画与合成层
    disableContextMenu: true,
    disableVerticalScroll: true,
    disableHorizontalScroll: true,
    supportZoom: false,
    cacheEnabled: false,
    clearCache: true,
    textZoom: 100,
  );
}

/// WebView 控制台日志：始终进运行日志缓冲。
///
/// 不能再用 kDebugMode 门控：手机装的是 release APK，而引擎的报错
/// （`main.js` 抛错、`openBook` 失败）只在 WebView 控制台里。
/// 注意 `ConsoleMessageLevel` 的 `==` 是坏的（比的是 int），只能看 toString。
void debugWebConsole(ConsoleMessage message) {
  final level = message.messageLevel.toString();
  final isError = level == 'ERROR';
  appLog('[webview/$level] ${message.message}', level: isError ? 'E' : 'W');
}