import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../bridge/bridge_protocol.dart';
import '../../bridge/engine_host.dart';
import '../../bridge/epd_channel.dart';
import '../../bridge/js_bridge.dart';
import '../../core/app_log.dart';
import '../../services/book_blob_store.dart';
import '../../services/web_asset_copier.dart';
import '../settings/settings_controller.dart';
import 'reader_controller.dart';
import 'widgets/note_menu.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reading_progress_bar.dart';

/// 阅读页容器：把 L3 TS 引擎托进 WebView / iframe，并做双向桥接。
///
/// 两条平台路线（引擎产物同一个 assets/web/main.js）：
/// - Android：assets/web 拷到 <documents>/webview_root，InAppWebView loadFile
///   加载 index.html（与书籍同盘，JS fetch file:// 书籍/字体可达）；
///   下行 evaluateJavascript，上行 JavaScriptHandler。
/// - Web(chrome/edge)：自建同源 iframe 直接加载 assets/web/index.html，
///   双向都走 postMessage（见 [EngineHost]）。该平台 JS 读不到本地文件，
///   TXT 正文由 Dart 通过 openBook payload 直传，EPUB 二进制走
///   `dataBase64`（内存缓存见 [BookBlobStore]，刷新页面即失效）。
class ReaderPage extends StatefulWidget {
  const ReaderPage(
      {super.key, required this.bookId, required this.settingsController});

  final String bookId;
  final SettingsController settingsController;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  /// 引擎 onReady 等待上限：超过即判定引擎没起来，把原因显示出来
  static const _engineTimeout = Duration(seconds: 10);

  late final ReaderController controller;
  late final JsBridge bridge;

  /// Android 专用：file:// 入口地址
  Future<WebViewEntry>? _entryFuture;
  Future<void>? _bookFuture;

  /// web 专用：自建 iframe 宿主（其他平台为 null）
  EngineHost? _host;

  /// openBook 只发一次：onLoadStop 可能重复触发
  bool _bookOpened = false;

  /// _openBookOnce 的重入保护（await 期间可能被第二次调用插进来）
  bool _openingBook = false;

  /// 非空表示链路失败，直接在阅读区显示原因（而不是留白）
  String? _failure;

  /// 引擎是否发过上行事件（判别「白屏」是没起来还是没画出来）
  bool _engineSpoke = false;

  /// 引擎是否上报过 onPageChanged（= 正文真的排好并回传了）
  bool _bookPainted = false;

  static _ReaderPageState? _active;

  /// JsBridge 的 handler callback 是顶层/闭包签名，这里借活跃实例转发
  static void _dispatchGlobal(String event, Map<String, dynamic> payload) {
    _active?.controller.handleEvent(event, payload);
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    // 上行统一过 _handleEngineEvent：它负责置 _engineSpoke（看门狗依据）
    bridge = JsBridge(_handleEngineEvent);
    controller = ReaderController(
      bookId: widget.bookId,
      settingsController: widget.settingsController,
    );
    controller.onEpdRefresh = (type) {
      // 时序契约：onPageChanged（渲染完成）之后才触发，顺序不能反
      if (type == 'full') {
        EpdChannel.full();
      } else {
        EpdChannel.partial();
      }
    };
    _bookFuture = controller.init();

    if (kIsWeb) {
      _host = EngineHost.create(_handleEngineEvent);
      controller.bindPost(_sendToEngine);
      _startWebEngine();
    } else {
      _entryFuture = _resolveNativeEntry();
    }
  }

  /// 宿主上行事件 → 控制器；合成事件（引擎产物过期）直接展示原因
  void _handleEngineEvent(String event, Map<String, dynamic> payload) {
    _engineSpoke = true;
    if (event == 'onPageChanged') _bookPainted = true;
    appLog('[engine] ← $event ${_brief(payload)}');
    if (event == 'onEngineStale') {
      _fail('阅读引擎产物过旧（协议 ${payload['protocol'] ?? 0}）：\n'
          '请执行 .\\build_web.ps1 同步到 assets/web/ 后重开本书。');
      return;
    }
    if (event == 'onError' && !_bookPainted) {
      // 打开阶段就报错（如 epub 读不到文件）：屏幕上必须写原因，
      // 否则用户只看到一片空白，还得回书架导日志才知道
      _fail('阅读引擎报错：${payload['message'] ?? '(无详情)'}');
    }
    _dispatchGlobal(event, payload);
  }

  /// Dart → 引擎：两条平台路线都从这走，日志页里能看到每一条下发命令
  void _sendToEngine(String action, Map<String, dynamic> payload) {
    appLog('[engine] → $action ${_brief(payload)}');
    final host = _host;
    if (host != null) {
      host.post(action, payload);
    } else {
      bridge.post(action, payload);
    }
  }

  /// 打点用 payload 摘要：正文可能几十万字/几 MB，只留长度
  static String _brief(Map<String, dynamic> payload) {
    final slim = <String, dynamic>{};
    payload.forEach((k, v) {
      slim[k] = (k == 'text' || k == 'dataBase64') && v is String
          ? '<${v.length} chars>'
          : v;
    });
    final s = jsonEncode(slim);
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    bridge.detach();
    _host?.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 正文用 SafeArea 避开状态栏/手势条后，那两条露出来的是 Scaffold 底色。
    // 让它跟随阅读主题（与引擎 renderer.ts 的 bgOf 一致），
    // 否则夜间/灰阶模式会在屏幕顶部留下一条白边。
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (context, child) => Scaffold(
        backgroundColor:
            _readerBackground(widget.settingsController.settings.themeMode),
        resizeToAvoidBottomInset: false,
        body: child,
      ),
      // child 不随设置变化重建：WebView 平台视图不能因为改字号被重建
      child: kIsWeb ? _buildWeb() : _buildNative(),
    );
  }

  static Color _readerBackground(ReaderThemeMode mode) => switch (mode) {
        ReaderThemeMode.paper => const Color(0xFFFFFFFF),
        ReaderThemeMode.gray => const Color(0xFFECECEC),
        ReaderThemeMode.night => const Color(0xFF111111),
      };

  // ---------------------------------------------------------------------------
  // web：自建 iframe + postMessage
  // ---------------------------------------------------------------------------

  Widget _buildWeb() {
    final host = _host;
    return Column(
      children: [
        // 顶部这条不被 iframe 覆盖（iframe 的 top = webReaderBarHeight），
        // 所以返回按钮既看得见也点得到；失败态也保留它，否则 web 上就没退路了
        SizedBox(
          height: webReaderBarHeight,
          child: _WebReaderBar(
            controller: controller,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ),
        Expanded(
          // 失败时不再画引擎区：DOM 永远盖在 Flutter 画布之上，
          // 此时 iframe 已被 host.hide() 置为 display:none
          child: _failure != null
              ? _FailurePane(_failure!)
              : (host?.build() ?? const SizedBox.expand()),
        ),
        // 底边这一条必须真的留白：iframe 是 DOM，盖在 Flutter 画布之上，
        // 落在 iframe 覆盖区里的进度尺根本看不见。高度与
        // webReaderProgressHeight 一致（engine_host 的几何按它让位）。
        if (_failure == null)
          SizedBox(
            height: webReaderProgressHeight,
            // 进度尺可关（设置对话框）；但这条 14px 空白必须一直留着：
            // iframe 的高度由 engine_host 按这个常量减掉，两边不一致会盖住正文
            child: ListenableBuilder(
              listenable: widget.settingsController,
              builder: (ctx, _) {
                if (!widget.settingsController.settings.showProgress) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ReadingProgressBar(
                    controller: controller,
                    height: webReaderProgressHeight,
                    // 气泡向上溢出会被 iframe 盖住，web 上只保留线本身
                    showLabel: false,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _startWebEngine() async {
    final host = _host;
    if (host == null) return;
    // 超时只提示不放弃：冷启动/慢网络下引擎晚到，就绪后仍继续打开
    final hint = Timer(_engineTimeout, () {
      if (!host.isReady) {
        _fail('阅读引擎未就绪：assets/web/index.html 未能加载。\n'
            '请先执行 .\\build_web.ps1 同步引擎产物，再重试。\n'
            '[${host.describeState()}]');
      }
    });
    await host.ready;
    hint.cancel();
    if (_failure != null) return; // 引擎产物过期等：不再打开书
    await _openBookOnce();
  }

  // ---------------------------------------------------------------------------
  // Android：InAppWebView + file://
  // ---------------------------------------------------------------------------

  Widget _buildNative() {
    return FutureBuilder<WebViewEntry>(
      future: _entryFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final entry = snap.data!;
        return _withOverlays(
          // 正文必须避开系统栏：InAppWebView 是平台视图，不会自己躲开
          // 状态栏/手势条；不包 SafeArea 就会顶到屏幕最上沿，和电量、
          // WiFi 图标叠在一起（状态栏是透明的，且 Android 15 起强制 edge-to-edge）。
          //
          // 只包 surface：顶栏/底栏各自已有 SafeArea，而且它们的背景本就要
          // 延伸到状态栏/手势条下方——在外面统一包一层会把这份 padding 吃掉，
          // 导致顶栏文字重新贴到状态栏上。
          SafeArea(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(entry.url)),
              initialSettings: webViewSettings(),
              onWebViewCreated: (c) {
                appLog('[reader/android] webViewCreated');
                bridge.bind(c);
                controller.bindPost(_sendToEngine);
              },
              onLoadStart: (c, url) {
                appLog('[reader/android] loadStart $url');
              },
              onReceivedError: (c, req, err) {
                appLog(
                    '[reader/android] 加载失败 ${req.url} -> ${err.type} ${err.description}',
                    level: 'E');
              },
              onReceivedHttpError: (c, req, resp) {
                appLog('[reader/android] HTTP ${resp.statusCode} ${req.url}',
                    level: 'E');
              },
              onLoadStop: (c, url) {
                appLog('[reader/android] loadStop $url');
                // 引擎脚本已随 load 就绪：先把下行队列打通，再打开书。
                // 不能等 onReady——原生桥注入慢时它可能永远到不了。
                bridge.markPageReady();
                _watchEngine();
                _openBookOnce();
                // 取证：2s / 6s 各问一次 WebView 内部状态
                Timer(const Duration(seconds: 2), _probeEngineState);
                Timer(const Duration(seconds: 6), _probeEngineState);
              },
              onConsoleMessage: (_, msg) => debugWebConsole(msg),
            ),
          ),
        );
      },
    );
  }

  Future<WebViewEntry> _resolveNativeEntry() async {
    final root = await WebAssetCopier.instance.prepare();
    return WebViewEntry(url: 'file://$root/index.html');
  }

  /// Android 看门狗：只收到 onReady 不算成功，得等 onPageChanged。
  /// 白屏最难排查，宁可把判断写在屏幕上。
  void _watchEngine() {
    Timer(_engineTimeout, () {
      if (_bookPainted || _failure != null) return;
      final why = _engineSpoke
          ? '引擎有响应，但 10 秒内没上报 onPageChanged（正文没画出来）'
          : '引擎 10 秒内没有任何响应';
      _fail('$why。\n可能是 main.js 未执行（assets/web 未同步）'
          '或书籍正文为空，请打开书架右上角的「运行日志」看一眼。');
    });
  }

  /// 取证：直接问 WebView 内部状态——脚本在不在、原生桥在不在、
  /// 正文到底画出来没有、视口尺寸多大。白屏就靠这几个数定位。
  Future<void> _probeEngineState() async {
    final raw = await bridge.evalRaw(_probeJs);
    appLog('[reader/android] probe $raw');
  }

  static const _probeJs = r"""
(function(){
  var vp = document.querySelector('.ink-viewport');
  var book = document.querySelector('.ink-book');
  return JSON.stringify({
    reader: !!window.__reader,
    nativeBridge: !!window.flutter_inappwebview,
    chars: book ? book.textContent.length : -1,
    blocks: document.querySelectorAll('.ink-book p').length,
    vp: vp ? vp.clientWidth + 'x' + vp.clientHeight : 'none',
    // 页边距下在视口 padding 上（Pager 会从尺寸里扣掉），白屏/分栏异常时先看这个
    pad: vp ? (function(){
      var cs = getComputedStyle(vp);
      return cs.paddingLeft + ',' + cs.paddingTop;
    })() : 'none',
    container: (function(){
      var el = document.getElementById('page-container');
      return el ? el.clientWidth + 'x' + el.clientHeight : 'none';
    })(),
    inner: window.innerWidth + 'x' + window.innerHeight,
    book: book ? book.offsetWidth + 'x' + book.offsetHeight : 'none',
    pages: (book && vp) ? Math.round(book.scrollWidth / Math.max(1, vp.clientWidth)) : 0,
    bg: getComputedStyle(document.body).backgroundColor,
    fg: book ? getComputedStyle(book).color : 'none'
  });
})()
""";

  // ---------------------------------------------------------------------------
  // 公共：打开书 + 覆盖层
  // ---------------------------------------------------------------------------

  /// 打开当前书。前提：引擎脚本已就位（Android 由 onLoadStop 保证，
  /// web 由 onReady 保证）；书数据可能还没读完，这里等 _bookFuture。
  Future<void> _openBookOnce() async {
    // 重入保护：两个 onLoadStop / 二次加载会同时跨过 await，
    // 重复下发 openBook 会把引擎重建一遍（多一轮全刷）
    if (_bookOpened || _openingBook) return;
    _openingBook = true;
    try {
      await _bookFuture;
      final book = controller.book;
      if (book == null) {
        _fail('未找到书籍数据（bookId=${widget.bookId}），请回书架重新导入。');
        return;
      }
      if (kIsWeb && book.kind == 'epub' &&
          !BookBlobStore.instance.has(book.id)) {
        // web 没有沙盒可读：EPUB 的 zip 只存在内存（导入时缓存），
        // 刷新过页面就没了，那本书得重新导入一次
        _fail('Web 调试环境读不到 EPUB 的二进制（刷新页面会丢失内存缓存）。\n'
            '请回书架重新导入本书；或改用 Android 设备打开。');
        return;
      }
      _bookOpened = true;
      appLog('[reader] openBook kind=${book.kind} id=${book.id}');
      try {
        await controller.openBookInEngine();
        // 必须在 openBook 之后：引擎此时才创建实例，之前的 applyTheme 会被丢弃
        controller.applyThemeToEngine();
      } catch (e, st) {
        // 不接住就变成一个没人看的异步异常，屏幕上只剩白屏
        appLog('[reader] openBook 失败: $e\n$st', level: 'E');
        _fail('打开书籍失败：$e');
      }
    } finally {
      _openingBook = false;
    }
  }

  void _fail(String message) {
    appLog('[reader] $message', level: 'E');
    if (!mounted) return;
    // DOM 永远在画布之上：不藏掉 iframe，失败提示也会被盖住
    _host?.hide();
    setState(() => _failure = message);
  }

  /// 阅读区 + 失败提示 + 顶栏/底栏（顺序即层级）
  ///
  /// **必须显式铺满**：`ReaderChrome`/`SelectionBar` 平时都是 `SizedBox.shrink()`，
  /// 当 Stack 里只剩这两个 0 尺寸的非定位子时，RenderStack 会把自身尺寸
  /// 取成「子元素最大尺寸」= 0×0，`Positioned.fill` 里的 WebView 就拿到 0×0 约束。
  /// 后果不是简单的“看不见”：WebView 的布局视口也是 0，引擎量到
  /// `clientWidth/Height = 0` → `column-width: 0` → 正文排成 1 字 1 行的几万 px
  /// 长条（手机上表现为白屏，而日志里引擎一切正常）。web 端 iframe 由 CSS 定位，
  /// 不受 Flutter 布局影响，所以只有手机会中招。
  Widget _withOverlays(Widget surface) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          surface,
          if (_failure != null) _FailurePane(_failure!),
          // 底部阅读进度尺：落在 SafeArea 让出的手势条空白里，
          // 既不遮挡正文、也不改变阅读区尺寸（覆盖式，不是布局子）。
          // 开关在设置对话框里，这里单独订阅（外层 child 不随设置重建）
          if (_failure == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: widget.settingsController,
                builder: (ctx, _) {
                  if (!widget.settingsController.settings.showProgress) {
                    return const SizedBox.shrink();
                  }
                  return SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ReadingProgressBar(controller: controller),
                    ),
                  );
                },
              ),
            ),
          // 顶栏/底栏：默认隐藏，点中央切换（TS onToggleChrome 驱动）
          ReaderChrome(controller: controller),
          SelectionBar(controller: controller),
        ],
      ),
    );
  }
}

/// 失败提示：白屏是最难排查的现象，宁可把原因写在屏幕上
class _FailurePane extends StatelessWidget {
  const _FailurePane(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: theme.colorScheme.onSurface.withOpacity(.6)),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withOpacity(.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// web 阅读页顶栏：只放返回 + 书名。
///
/// 引擎 iframe 盖住了整个阅读区，Flutter 画的浮层（目录、设置、划线条）
/// 在 web 上不可见，因此这条只有必选的返回。
class _WebReaderBar extends StatelessWidget {
  const _WebReaderBar({required this.controller, required this.onBack});

  final ReaderController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) => Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回书架',
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                controller.book?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class WebViewEntry {
  WebViewEntry({required this.url});
  final String url;
}
