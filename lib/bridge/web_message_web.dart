import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// web 平台（chrome/edge）的 TS → Dart 上行通道。
///
/// flutter_inappwebview_web 1.1.2 未实现 addJavaScriptHandler（调用会抛
/// UnimplementedError），iframe 内也没有 window.flutter_inappwebview.callHandler；
/// 因此引擎改用 window.parent.postMessage(JSON 字符串) 上行，这里在宿主 window 上收。

typedef EngineMessageSink = void Function(Map<String, dynamic> msg);

void Function() listenEngineMessages(EngineMessageSink sink) {
  void onMessage(html.Event event) {
    if (event is! html.MessageEvent) return;
    final data = event.data;
    if (data is! String) return; // 引擎只发 JSON 字符串
    try {
      final msg = (jsonDecode(data) as Map).cast<String, dynamic>();
      if (msg['source'] != 'ink-reader') return;
      sink(msg);
    } catch (_) {
      // 非本引擎报文（Flutter 自身/浏览器扩展的 message）直接忽略
    }
  }

  html.window.addEventListener('message', onMessage);
  return () => html.window.removeEventListener('message', onMessage);
}
