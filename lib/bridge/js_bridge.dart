import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import 'bridge_protocol.dart';

typedef TsEventHandler = void Function(String event, Map<String, dynamic> payload);

/// Dart → TS 的调用封装 + TS → Dart 的事件分发。
///
/// 平台差异：
/// - Android/iOS：WebView 从沙盒拷贝目录 loadFile，JS 可 fetch file:// 书籍。
/// - Web(chrome)：flutter_inappwebview 6 的 web 实现（iframe），
///   JS 拿不到本地文件，因此 txt 内容由 Dart 直接塞进 openBook payload。
class JsBridge {
  JsBridge(this._onEvent);

  final TsEventHandler _onEvent;
  InAppWebViewController? _controller;
  bool _pageReady = false;
  final List<Map<String, dynamic>> _pending = [];

  /// JavaScriptHandler：TS 侧统一通过 callHandler('event', msg) 上行
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
          final event = msg['action'] as String?;
          final payload = (msg['payload'] as Map?)?.cast<String, dynamic>() ?? {};
          if (event != null) {
            if (event == DartEvent.onReady) _pageReady = true;
            _onEvent(event, payload);
            if (event == DartEvent.onReady) _flushPending();
          }
        } catch (e) {
          appLog('JsBridge handler error: $e');
        }
        return null;
      },
    );
  }

  void detach() {
    _controller = null;
    _pageReady = false;
    _pending.clear();
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

  Future<void> _send(Map<String, dynamic> msg) async {
    final c = _controller;
    if (c == null) return;
    final encoded = jsonEncode(msg);
    try {
      await c.evaluateJavascript(
        source: 'window.__reader && window.__reader.dispatch($encoded);',
      );
    } catch (e) {
      appLog('JsBridge post($encoded) error: $e');
    }
  }
}

/// WebView 初始设置：墨水屏向的关动画/开文件访问。
InAppWebViewSettings webViewSettings() {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    transparentBackground: true,
    // 本地文件：TS 引擎需 fetch file:/// 沙盒中的书籍（含字体、epub）
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

/// web 调试时的诊断日志
void debugWebConsole(ConsoleMessage message) {
  if (kDebugMode) {
    debugPrint('[webview] ${message.messageLevel}: ${message.message}');
  }
}
