import 'engine_host.dart';

/// 非 web 平台占位：阅读页走 InAppWebView，不需要 iframe 宿主。
///
/// web 实现见 engine_host_web.dart（dart:html + dart:ui_web）。
EngineHost? createEngineHost(EngineEventSink onEvent) => null;
