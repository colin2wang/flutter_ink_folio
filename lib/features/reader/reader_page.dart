import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../bridge/epd_channel.dart';
import '../../bridge/js_bridge.dart';
import '../../core/app_log.dart';
import '../../services/web_asset_copier.dart';
import '../settings/settings_controller.dart';
import 'reader_controller.dart';
import 'widgets/note_menu.dart';
import 'widgets/reader_chrome.dart';

/// 阅读页容器：持有 InAppWebView，加载 TS 引擎，双向桥接。
///
/// 加载策略：
/// - Android：把 assets/web 拷贝到 <documents>/webview_root，loadFile 加载
///   （与书籍同盘，JS fetch file:// 书籍/字体均可达）。
/// - Web(chrome/edge)：flutter_inappwebview_web 用 iframe 承载，
///   initialData 会被写成 data: URL（opaque origin，evaluateJavascript 跨源被拒），
///   且 initialUrlRequest 优先于 initialData；因此只加载 about:blank（与宿主同源），
///   引擎源码在 onLoadStop 里用 evaluateJavascript 注入。
///   该平台 JS 无法 fetch 本地文件，txt 正文由 Dart 直接塞进 openBook payload。
class ReaderPage extends StatefulWidget {
  const ReaderPage(
      {super.key, required this.bookId, required this.settingsController});

  final String bookId;
  final SettingsController settingsController;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderController controller;
  late final JsBridge bridge;
  late final Future<WebViewEntry> _entryFuture;
  InAppWebViewController? _webController;
  late final Future<void> _bookFuture;
  bool _engineReady = false;

  /// web 平台注入用的 DOM 骨架：引擎顶层就要取 #page-container，必须先建好
  static const _bootstrapJs = '''
(function(){
  var d = document;
  if (d.getElementById('page-container')) return;
  var st = d.createElement('style');
  st.textContent = 'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent}'
    + '#page-container{position:absolute;inset:0;overflow:hidden}';
  (d.head || d.documentElement).appendChild(st);
  var c = d.createElement('div');
  c.id = 'page-container';
  (d.body || d.documentElement).appendChild(c);
})();
''';

  static _ReaderPageState? _active;

  /// JsBridge 的 handler callback 是顶层/闭包签名，这里借活跃实例转发
  static void _dispatchGlobal(String event, Map<String, dynamic> payload) {
    _active?.controller.handleEvent(event, payload);
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    bridge = JsBridge(_dispatchGlobal);
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
    _entryFuture = _resolveEntry();
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    bridge.detach();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: FutureBuilder<WebViewEntry>(
        future: _entryFuture,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final entry = snap.data!;
          return Stack(
            children: [
              Positioned.fill(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(entry.url)),
                  initialSettings: webViewSettings(),
                  onWebViewCreated: (c) {
                    _webController = c;
                    bridge.bind(c);
                    controller.bindPost((action, payload) {
                      bridge.post(action, payload);
                    });
                  },
                  onLoadStop: (c, url) async {
                    // web 平台：引擎源码在页面就绪后注入（见 _resolveEntry 注释）。
                    // 注入失败不置位，下一次 onLoadStop 会重试。
                    final js = entry.engineJs;
                    if (js != null && !_engineReady) {
                      _engineReady = await _injectEngine(c, js);
                    }
                    // openBook 需要书已读出来，否则 payload 为空 → 页面依旧空白
                    await _bookFuture;
                    // 引擎脚本就绪后引导启动；正式通信等引擎 onReady 回调
                    controller.applyThemeToEngine();
                    await controller.openBookInEngine();
                  },
                  onConsoleMessage: (_, msg) => debugWebConsole(msg),
                ),
              ),
              // 顶栏/底栏：默认隐藏，点中央切换（TS onToggleChrome 驱动）
              ReaderChrome(controller: controller),
              SelectionBar(controller: controller),
            ],
          );
        },
      ),
    );
  }

  Future<WebViewEntry> _resolveEntry() async {
    if (kIsWeb) {
      final js = await rootBundle.loadString('assets/web/main.js');
      return WebViewEntry(url: 'about:blank', engineJs: js);
    }
    final root = await WebAssetCopier.instance.prepare();
    return WebViewEntry(url: 'file://$root/index.html');
  }

  /// about:blank iframe 与宿主同源，可直接 eval：先建容器再装引擎。
  /// 返回引擎是否真的装上了（window.__reader 存在）。
  Future<bool> _injectEngine(InAppWebViewController c, String js) async {
    try {
      await c.evaluateJavascript(source: _bootstrapJs);
      await c.evaluateJavascript(source: js);
      final ok = await c.evaluateJavascript(source: '!!window.__reader');
      if (ok == true || ok == 'true') return true;
      appLog('inject engine: window.__reader missing');
    } catch (e) {
      appLog('inject engine failed: $e');
    }
    return false;
  }
}

class WebViewEntry {
  WebViewEntry({required this.url, this.engineJs});
  final String url;

  /// 非空表示需要由 Dart 注入引擎源码（web 平台）；Android 走 file:// index.html
  final String? engineJs;
}
