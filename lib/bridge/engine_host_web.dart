import 'dart:async';
import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import '../core/app_log.dart';
import 'bridge_protocol.dart';
import 'engine_host.dart';

/// 上行报文标识：与 TS 侧 INK_SOURCE 一致，宿主只认这一种 message
const _inkUpSource = 'ink-reader';

/// 下行报文标识：与 TS 侧 INK_DOWN 一致，引擎据此过滤宿主命令
const _inkDown = 'down';

/// 引擎桥接协议版本：与 web_engine/src/bridge.ts 的 ENGINE_PROTOCOL 对齐。
/// 不一致说明 assets/web/main.js 是旧产物（不支持 postMessage 下行）。
const _engineProtocol = engineProtocolVersion;

/// 引擎产物过期时抛给阅读页的合成事件
const _eventStale = 'onEngineStale';

/// 引擎文档的 asset key（与 pubspec 的 `assets/web/` 声明一致）
const _engineAsset = 'assets/web/index.html';

int _hostSeq = 0;

EngineHost? createEngineHost(EngineEventSink onEvent) => WebEngineHost(onEvent);

/// Web 端引擎宿主：把引擎 iframe 直接挂在 document.body 上，双向 postMessage。
///
/// 为什么不用 HtmlElementView：Flutter web 的平台视图要先在
/// `flt-platform-view` 包装里创建，再由渲染管线 `injectPlatformView`
/// 注入到 `<flt-glass-pane>`。注入没发生时，元素停在**游离**的包装里，
/// iframe 拿不到 browsing context：`load` 不触发、`contentWindow` 为 null、
/// 引擎脚本自然也不执行（表现为阅读区空白，且日志里只剩「未就绪」）。
/// 自己 append 到 body 就绕开了整条注入链路。
///
/// 布局约定：iframe 从 [webReaderBarHeight] 之下铺满窗口，
/// 上方那条留给 Flutter 画返回按钮（DOM 盖在画布之上，被盖住的地方点不到）。
class WebEngineHost implements EngineHost {
  WebEngineHost(this._onEvent) {
    _probeAsset();
    // body 在首帧后一定存在，也避免在 build 期间改 DOM
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
    // 兜底：2s 还没就绪就换 srcdoc（src 导航被拦/没触发时也能起）
    Timer(const Duration(seconds: 2), _fallbackToSrcDoc);
  }

  final EngineEventSink _onEvent;
  final int _seq = _hostSeq++;
  final Completer<void> _ready = Completer<void>();
  final List<String> _pending = [];

  html.IFrameElement? _iframe;
  void Function()? _stopListen;
  StreamSubscription<html.Event>? _stopResize;
  bool _disposed = false;

  /// 失败提示期间需要把 iframe 藏起来（DOM 永远盖在画布之上）
  bool _hidden = false;

  /// 探测到的引擎文档原文（用于 srcdoc 兜底）
  String? _engineHtml;
  bool _srcdocUsed = false;

  /// src 导航已到达（load 已触发）；此时未就绪只可能是脚本没执行，
  /// 换 srcdoc 重载文档没用，反而会打断正常导航
  bool _domLoaded = false;

  @override
  bool get isReady => _ready.isCompleted;

  @override
  Future<void> get ready => _ready.future;

  /// web 上 iframe 不参与 Flutter 布局，这里只占位
  @override
  Widget build() => const SizedBox.expand();

  /// 引擎文档在 Flutter web 里的真实 URL。
  ///
  /// 不能写死 `assets/web/index.html`：Flutter 把资源放在「`assets/` + asset key」
  /// 之下，而 key 本身已带 `assets/` 前缀，真实路径是 `assets/assets/web/index.html`。
  String get _engineUrl => ui_web.assetManager.getAssetUrl(_engineAsset);

  // ---------------------------------------------------------------------------
  // DOM 挂载
  // ---------------------------------------------------------------------------

  void _attach() {
    // post-frame 回调可能在页面已 pop 之后才跑到，此时不能再往 body 里塞 iframe
    if (_disposed || _iframe != null) return;
    final iframe = html.IFrameElement()
      ..id = 'ink-engine-$_seq'
      ..className = 'ink-engine-frame'
      ..setAttribute('scrolling', 'no');
    _iframe = iframe;
    _stopListen = _listenUp();
    // 必须在插入前就把几何写好：iframe 一旦以默认尺寸进过布局，
    // 引擎就会按 300×150 分栏，之后只能靠 resize 才纠得回来
    _applyGeometry();
    final body = html.document.body;
    if (body == null) {
      appLog('[engine/web] body 尚未就绪，下一帧再挂');
      _iframe = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
      return;
    }
    iframe.src = _engineUrl;
    body.children.add(iframe);
    appLog('[engine/web] iframe attached -> $_engineUrl');
    _logGeometry('attach');
    // iframe 尺寸变化的感知有两条路：iframe 自己会收到 window.resize，
    // 引擎侧还有 ResizeObserver；这里只管把宿主窗口的尺寸同步下来
    _stopResize = html.window.onResize.listen((_) => _syncGeometry('resize'));
    // attach 时 innerWidth 偶尔还是 0，补两次；顺带把真实矩形打进日志
    Timer(const Duration(milliseconds: 300), () => _syncGeometry('t+300ms'));
    Timer(const Duration(milliseconds: 1200), () => _syncGeometry('t+1.2s'));
    // load 只证明文档到了；引擎是否执行看 onReady
    iframe.onLoad.first.then((_) {
      _domLoaded = true;
      if (!isReady) {
        appLog('[engine/web] 文档已 load 但引擎未执行：'
            'main.js 没跑或抛错（看控制台的脚本报错）');
      }
      _trace('iframe load');
    });
    Timer(const Duration(seconds: 1), () => _trace('t+1s'));
    Timer(const Duration(seconds: 4), () => _trace('t+4s'));
  }

  /// 写 iframe 几何：**显式像素宽高**，不用四边定位。
  ///
  /// 曾经写成 `left/right/top/bottom` 四边全给，只要其中一条没生效，
  /// iframe 就退回浏览器默认的 300×150，引擎随之按 300px 栏宽分栏——
  /// 屏幕上只剩左上角一小块正文，而且看不出任何报错。
  /// 现在用「左上角 + 宽高」这种不可误读的组合，窗口尺寸拿不到时才退回百分比。
  ///
  /// 顶部让出 [webReaderBarHeight]、底部让出 [webReaderProgressHeight]：
  /// iframe 是 DOM，压在它上面的 Flutter 组件看不见，因此这两条必须真留白。
  void _applyGeometry() {
    final iframe = _iframe;
    if (iframe == null || _disposed) return;
    // dart:html 的 innerWidth/innerHeight 是 int?（嵌入方可能还没给出视口）
    final w = html.window.innerWidth ?? 0;
    final h = html.window.innerHeight ?? 0;
    final top = webReaderBarHeight.round();
    final bottom = webReaderProgressHeight.round();
    final buf = StringBuffer()
      ..write('position:fixed;left:0;top:${top}px;')
      ..write('border:0;margin:0;padding:0;z-index:0;background:transparent;')
      ..write('display:${_hidden ? 'none' : 'block'};');
    buf.write(w > 0 ? 'width:${w}px;' : 'width:100%;');
    if (h > top + bottom) {
      buf.write('height:${h - top - bottom}px;');
    } else if (h > top) {
      buf.write('height:${h - top}px;');
    } else {
      buf.write('height:calc(100% - ${top + bottom}px);');
    }
    // 一次性写：逐条赋值时任何一条被 over-constraint 规则忽略都很难发现
    iframe.style.cssText = buf.toString();
  }

  void _syncGeometry(String tag) {
    if (_disposed || _iframe == null) return;
    _applyGeometry();
    _logGeometry(tag);
  }

  /// 「正文只占左上角一小块」第一个要看的就是这几个数：
  /// rect 很小 → 宿主几何没生效；rect 正常而引擎里 vp 很小 → 引擎侧没重排。
  void _logGeometry(String tag) {
    final iframe = _iframe;
    if (iframe == null) {
      appLog('[engine/web] geometry $tag: iframe=null');
      return;
    }
    final r = iframe.getBoundingClientRect();
    appLog('[engine/web] geometry $tag: rect=${r.width.round()}x'
        '${r.height.round()} win=${html.window.innerWidth ?? 0}x'
        '${html.window.innerHeight ?? 0}');
  }

  /// 诊断：直接用 XHR 取一次引擎文档，确认资源真的可达；
  /// 拿到原文后还能做 srcdoc 兜底（不依赖资源 HTML 的网络导航）。
  Future<void> _probeAsset() async {
    try {
      final body = await html.HttpRequest.getString(_engineUrl);
      _engineHtml = body;
      appLog('[engine/web] probe ok: ${body.length} chars, '
          'hasPageContainer=${body.contains('page-container')}, '
          'hasMainJs=${body.contains('main.js')}');
      // 探测可能比构造时那条 2s 兜底更慢，拿到原文后再挂一次
      Timer(const Duration(seconds: 1), _fallbackToSrcDoc);
    } catch (e) {
      appLog('[engine/web] probe FAILED: $_engineUrl -> $e');
    }
  }

  /// 兜底：用内存文档（srcdoc）加载引擎。
  ///
  /// srcdoc 文档继承父页面的 origin，postMessage 照常可达；
  /// 里面的 `<script src="./main.js">` 靠注入的 <base> 解析到 assets 目录。
  void _fallbackToSrcDoc() {
    final iframe = _iframe;
    final source = _engineHtml;
    if (_disposed ||
        iframe == null ||
        source == null ||
        isReady ||
        _srcdocUsed ||
        _domLoaded) {
      return;
    }
    _srcdocUsed = true;
    final base = _engineUrl.substring(0, _engineUrl.lastIndexOf('/') + 1);
    final doc = source.replaceFirstMapped(
        RegExp(r'<head[^>]*>'), (m) => '${m[0]}<base href="$base">');
    appLog('[engine/web] fallback -> srcdoc (base=$base)');
    iframe.srcdoc = doc;
  }

  /// 诊断快照：祖先链 + iframe 实际矩形 + 引擎内部量到的排版尺寸。
  ///
  /// 「正文只占左上角一小块」这类排版问题，靠这几组数字直接定位：
  /// iframe 矩形很小 → 宿主布局算错；iframe 矩形正常而 vp/book 很小 →
  /// 引擎量到的是过期尺寸（ResizeObserver 会纠）。
  @override
  String describeState() {
    final iframe = _iframe;
    if (iframe == null) return 'iframe=null';
    final chain = <String>[];
    html.Node? node = iframe;
    for (var i = 0; i < 8 && node != null; i++) {
      chain.add(node.nodeName ?? '?');
      node = node.parentNode;
    }
    final inDoc = html.document.body?.contains(iframe) ?? false;
    final rect = iframe.getBoundingClientRect();
    final win = iframe.contentWindow;
    var inner = 'n/a';
    if (win is html.Window) {
      try {
        final doc = win.document;
        final vp = doc.querySelector('.ink-viewport')?.getBoundingClientRect();
        final book = doc.querySelector('.ink-book')?.getBoundingClientRect();
        inner = 'vp=${vp?.width.round()}x${vp?.height.round()} '
            'book=${book?.width.round()}x${book?.height.round()}';
      } catch (e) {
        inner = 'unreadable($e)';
      }
    }
    return 'inDoc=$inDoc chain=${chain.join(' < ')} '
        'rect=${rect.width.round()}x${rect.height.round()} '
        'outer=${html.window.innerWidth ?? 0}x${html.window.innerHeight ?? 0} '
        'win=${win == null ? 'null' : 'ok'} inner=$inner ready=$isReady';
  }

  void _trace(String tag) {
    appLog('[engine/web] $tag: ${describeState()}');
  }

  @override
  void hide() {
    if (_iframe == null) return;
    appLog('[engine/web] hide');
    _hidden = true;
    _applyGeometry();
  }

  // ---------------------------------------------------------------------------
  // 上行：TS → Dart
  // ---------------------------------------------------------------------------

  /// 引擎在 iframe 里 window.parent.postMessage(JSON 字符串)
  void Function() _listenUp() {
    void onMessage(html.Event event) {
      if (event is! html.MessageEvent) return;
      final data = event.data;
      if (data is! String) {
        appLog('[engine/web] msg ignored (${data.runtimeType})');
        return;
      }
      // 上行报文原样打点：能看出引擎到底有没有说话
      final preview = data.length > 160 ? data.substring(0, 160) : data;
      final Map<String, dynamic> msg;
      try {
        msg = (jsonDecode(data) as Map).cast<String, dynamic>();
      } catch (_) {
        return; // 非本引擎报文（Flutter 自身/浏览器扩展）
      }
      if (msg['source'] != _inkUpSource) {
        appLog('[engine/web] msg foreign: $preview');
        return;
      }
      final action = msg['action'] as String?;
      if (action == null) return;
      final payload =
          (msg['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (action == 'onReady' && !_ready.isCompleted) {
        final protocol = (payload['protocol'] as num?)?.toInt() ?? 0;
        if (protocol != _engineProtocol) {
          appLog('[engine/web] 引擎协议 $protocol != $_engineProtocol，'
              'assets/web/main.js 需重建（.\\build_web.ps1）');
          _pending.clear();
          _ready.complete();
          _onEvent(_eventStale, payload);
          return;
        }
        appLog('[engine/web] onReady');
        _ready.complete();
        _flush();
      }
      _onEvent(action, payload);
    }

    html.window.addEventListener('message', onMessage);
    return () => html.window.removeEventListener('message', onMessage);
  }

  // ---------------------------------------------------------------------------
  // 下行：Dart → TS
  // ---------------------------------------------------------------------------

  @override
  Future<void> post(String action, Map<String, dynamic> payload) async {
    final raw = jsonEncode({
      '__ink': _inkDown,
      'action': action,
      'payload': payload,
    });
    if (!_ready.isCompleted) {
      _pending.add(raw);
      return;
    }
    _send(raw);
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final queued = List<String>.of(_pending);
    _pending.clear();
    for (final raw in queued) {
      _send(raw);
    }
  }

  void _send(String raw) {
    final win = _iframe?.contentWindow;
    if (win == null) {
      appLog('[engine/web] drop ${raw.length > 80 ? raw.substring(0, 80) : raw}'
          ' (iframe not attached)');
      return;
    }
    win.postMessage(raw, '*');
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListen?.call();
    _stopListen = null;
    _stopResize?.cancel();
    _stopResize = null;
    _iframe?.remove();
    _iframe = null;
    _pending.clear();
  }
}
