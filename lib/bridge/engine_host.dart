import 'package:flutter/widgets.dart';

import 'engine_host_stub.dart' if (dart.library.html) 'engine_host_web.dart'
    as impl;

/// 引擎上行回调：TS → Dart
typedef EngineEventSink = void Function(
    String event, Map<String, dynamic> payload);

/// web 阅读页顶部 Flutter 条的高度。
///
/// 引擎 iframe 直接挂在 document.body 上、从这条之下开始铺
/// （见 engine_host_web.dart），因此这块区域不会被 DOM 覆盖，
/// 里面画的返回按钮既可见也可点。
const double webReaderBarHeight = 44;

/// web 阅读页底部给进度尺预留的高度。
///
/// iframe 是真实 DOM，永远盖在 Flutter 画布之上——画在 iframe 覆盖区里的
/// Flutter 组件一律看不见（Android 是平台视图，覆盖层正常）。所以底部必须
/// 真留一条空白给 `ReadingProgressBar`，`engine_host_web` 的几何按它让位，
/// 两处高度必须一致。
const double webReaderProgressHeight = 14;

/// 阅读引擎宿主：把 L3 TS 引擎托到一个浏览器上下文里，并保持上下行通道。
///
/// 平台路线：
/// - 非 web：没有实现（工厂返回 null），阅读页用 InAppWebView + file:// 加载
///   assets/web/index.html，下行 evaluateJavascript、上行 JavaScriptHandler。
/// - Web(chrome/edge)：引擎 iframe 直接挂到 document.body，双向都走 postMessage。
///
/// web 既不用 InAppWebView（其 web 实现是 iframe + eval，依赖
/// web_support.js 与 load 回调，任一失败就整页空白，且没有
/// addJavaScriptHandler），也不用 HtmlElementView：平台视图要走
/// `flt-platform-view` 注入链路，注入不发生时 iframe 没有 browsing context
/// （不触发 load、contentWindow 为 null、永远等不到 onReady）。
abstract class EngineHost {
  /// web 平台返回实现；其他平台返回 null
  static EngineHost? create(EngineEventSink onEvent) =>
      impl.createEngineHost(onEvent);

  /// 引擎上报 onReady 后完成（超时由调用方处理）
  Future<void> get ready;

  bool get isReady;

  /// 宿主 Widget：web 上不占位（iframe 由宿主自己插进 DOM）
  Widget build();

  /// Dart → TS：未就绪先入队，onReady 后按序补发
  Future<void> post(String action, Map<String, dynamic> payload);

  /// 隐藏引擎（失败提示要可见：DOM 永远盖在 Flutter 画布之上）
  void hide();

  /// 诊断快照（iframe 是否入 DOM、祖先链、是否就绪），失败提示里直接带上
  String describeState();

  void dispose();
}
