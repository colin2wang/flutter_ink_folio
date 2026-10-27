/// 非 web 平台占位：没有 iframe/postMessage 通道。
///
/// web 实现见 web_message_web.dart（dart:html），由 js_bridge.dart 条件导入。

typedef EngineMessageSink = void Function(Map<String, dynamic> msg);

void Function() listenEngineMessages(EngineMessageSink sink) => () {};
